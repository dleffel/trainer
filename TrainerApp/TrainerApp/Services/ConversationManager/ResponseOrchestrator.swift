import Foundation
import SwiftUI

/// Delegate protocol for response orchestration state updates
protocol ResponseOrchestrationDelegate: AnyObject {
    /// Update conversation state
    func orchestrationDidUpdateState(_ state: ConversationState)
    
    /// Get current message history for API calls
    func orchestrationNeedsAPIHistory() -> [ChatMessage]
    
    /// Append a message to the conversation
    func orchestrationDidCreateMessage(_ message: ChatMessage)
    
    /// Update a message in the conversation
    func orchestrationDidUpdateMessage(at index: Int, with message: ChatMessage)
    
    /// Get message at index
    func orchestrationNeedsMessage(at index: Int) -> ChatMessage?
    
    /// Get current message count
    func orchestrationNeedsMessageCount() -> Int
    
    /// Generate meaningful response from tool results
    func orchestrationNeedsMeaningfulResponse(from history: [ChatMessage]) -> String
}

/// Orchestrates complete conversation flows including streaming, tool execution, and follow-ups
/// This is the high-level coordinator that manages the conversation turn-by-turn
@MainActor
class ResponseOrchestrator {
    
    // MARK: - Dependencies
    
    private let streamingCoordinator: StreamingCoordinator
    private let toolCoordinator: ToolExecutionCoordinator
    private let llmService: LLMServiceProtocol
    private let logger = ConversationLogger.shared
    weak var delegate: ResponseOrchestrationDelegate?
    
    // MARK: - Configuration
    
    private let maxConversationTurns: Int
    
    // MARK: - Initialization
    
    init(
        streamingCoordinator: StreamingCoordinator,
        toolCoordinator: ToolExecutionCoordinator,
        llmService: LLMServiceProtocol,
        maxTurns: Int = 5
    ) {
        self.streamingCoordinator = streamingCoordinator
        self.toolCoordinator = toolCoordinator
        self.llmService = llmService
        self.maxConversationTurns = maxTurns
    }
    
    // MARK: - Public Interface
    
    /// Result of conversation orchestration
    struct OrchestrationResult {
        let finalState: AssistantResponseState
        let turns: Int
        let hadTools: Bool
    }
    
    /// Execute complete conversation flow for a user message
    /// Handles streaming, tool execution, and follow-up responses in a turn-based loop
    func executeConversationFlow(
        apiKey: String,
        model: String,
        systemPrompt: String
    ) async throws -> OrchestrationResult {
        var responseState = AssistantResponseState()
        var turns = 0
        var hadAnyTools = false
        
        repeat {
            turns += 1
            
            // Get assistant response (streaming on first turn, non-streaming on follow-ups)
            responseState = try await (turns == 1
                ? handleInitialResponse(apiKey: apiKey, model: model, systemPrompt: systemPrompt)
                : handleFollowUpResponse(apiKey: apiKey, model: model, systemPrompt: systemPrompt))
            
            // Process tool calls if any
            let toolResult = try await processToolCallsIfNeeded(responseState)
            
            if toolResult.hasTools {
                hadAnyTools = true
                // Add tool result message for next turn
                if let systemMessage = toolResult.systemMessage {
                    delegate?.orchestrationDidCreateMessage(systemMessage)
                }
                // Continue loop for assistant's response to tools
                continue
            } else {
                // Finalize and exit
                try await finalizeResponse(responseState)
                break
            }
            
        } while turns < maxConversationTurns
        
        // Brief pause before returning to idle
        try? await Task.sleep(for: .milliseconds(200))
        delegate?.orchestrationDidUpdateState(.idle)
        
        return OrchestrationResult(
            finalState: responseState,
            turns: turns,
            hadTools: hadAnyTools
        )
    }
    
    // MARK: - Response Handling
    
    /// Handle initial response with streaming
    private func handleInitialResponse(
        apiKey: String,
        model: String,
        systemPrompt: String
    ) async throws -> AssistantResponseState {
        delegate?.orchestrationDidUpdateState(.streaming(progress: nil))
        
        let requestStart = Date()
        logger.logTiming("request_start", timestamp: requestStart.timeIntervalSince1970)
        
        var state: AssistantResponseState
        
        // Attempt streaming
        do {
            guard let history = delegate?.orchestrationNeedsAPIHistory() else {
                throw NSError(domain: "ResponseOrchestrator", code: -1, userInfo: [NSLocalizedDescriptionKey: "No API history available"])
            }
            
            let result = try await streamingCoordinator.streamResponse(
                apiKey: apiKey,
                model: model,
                systemPrompt: systemPrompt,
                history: history
            )
            state = result.state
            
        } catch {
            // Clean up any dangling .streaming message before fallback
            if let messageCount = delegate?.orchestrationNeedsMessageCount(),
               messageCount > 0,
               let lastMessage = delegate?.orchestrationNeedsMessage(at: messageCount - 1),
               lastMessage.state == .streaming {
                // Note: Delegate should handle removal if needed
                logger.log(ConversationLogger.LogLevel.debug, "Detected dangling streaming message before fallback", context: "handleInitialResponse")
            }
            
            // Clear reasoning UI flags before fallback
            if let streamingDelegate = delegate as? StreamingStateDelegate {
                streamingDelegate.streamingDidUpdateReasoningState(isStreaming: false, latestChunk: nil)
            }
            
// Fallback to non-streaming
delegate?.orchestrationDidUpdateState(.preparingResponse)
logger.log(ConversationLogger.LogLevel.warning, "Streaming failed, falling back to non-streaming: \(error.localizedDescription)", context: "handleInitialResponse")
state = try await fallbackNonStreaming(
    apiKey: apiKey,
    model: model,
    systemPrompt: systemPrompt
)
        }
        
        logger.logTiming("response_complete", timestamp: Date().timeIntervalSince1970)
        return state
    }
    
    /// Handle follow-up responses (non-streaming)
    private func handleFollowUpResponse(
        apiKey: String,
        model: String,
        systemPrompt: String
    ) async throws -> AssistantResponseState {
        delegate?.orchestrationDidUpdateState(.preparingResponse)
        
        guard let history = delegate?.orchestrationNeedsAPIHistory() else {
            throw NSError(domain: "ResponseOrchestrator", code: -1, userInfo: [NSLocalizedDescriptionKey: "No API history available"])
        }
        
        do {
            let result = try await llmService.complete(
                apiKey: apiKey,
                model: model,
                systemPrompt: systemPrompt,
                history: history
            )
            
            logger.log(ConversationLogger.LogLevel.debug, "Raw AI response: '\(result.content)'", context: "handleFollowUpResponse")
            if let reasoning = result.reasoning {
                logger.log(ConversationLogger.LogLevel.debug, "Reasoning: '\(reasoning)'", context: "handleFollowUpResponse")
            }
            
            // Create state from RAW response (tool processing happens in processToolCallsIfNeeded)
            var state = AssistantResponseState()
            state.setContent(result.content)  // Keep raw content for tool detection downstream
            state.setReasoning(result.reasoning)
            
            // Create message - will be updated by tool coordinator with cleaned content
            let message = MessageFactory.assistant(
                content: result.content,  // Start with raw content
                reasoning: result.reasoning
            )
            delegate?.orchestrationDidCreateMessage(message)
            
            if let messageCount = delegate?.orchestrationNeedsMessageCount() {
                state.setMessageIndex(messageCount - 1)
            }
            
            logger.log(ConversationLogger.LogLevel.debug, "Created assistant message for follow-up", context: "handleFollowUpResponse")
            
            return state
            
        } catch LLMError.missingContent {
            // Create a meaningful response based on tool results
            return try await handleEmptyResponse()
        }
    }
    
    /// Handle empty LLM responses by generating meaningful content from tool results
    private func handleEmptyResponse() async throws -> AssistantResponseState {
        logger.log(ConversationLogger.LogLevel.debug, "AI returned empty content, generating response from tool results", context: "handleEmptyResponse")
        
        guard let history = delegate?.orchestrationNeedsAPIHistory(),
              let meaningfulResponse = delegate?.orchestrationNeedsMeaningfulResponse(from: history) else {
            throw NSError(domain: "ResponseOrchestrator", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to generate meaningful response"])
        }
        
        var state = AssistantResponseState()
        state.setContent(meaningfulResponse)
        
        // Append message
        let message = MessageFactory.assistant(content: meaningfulResponse)
        delegate?.orchestrationDidCreateMessage(message)
        
        if let messageCount = delegate?.orchestrationNeedsMessageCount() {
            state.setMessageIndex(messageCount - 1)
        }
        
        logger.log(ConversationLogger.LogLevel.info, "Generated meaningful response from tool results: '\(meaningfulResponse)'", context: "handleEmptyResponse")
        
        return state
    }
    
    /// Fallback to non-streaming when streaming fails
    private func fallbackNonStreaming(
        apiKey: String,
        model: String,
        systemPrompt: String
    ) async throws -> AssistantResponseState {
        guard let history = delegate?.orchestrationNeedsAPIHistory() else {
            throw NSError(domain: "ResponseOrchestrator", code: -1, userInfo: [NSLocalizedDescriptionKey: "No API history available"])
        }
        
        var state = AssistantResponseState()
        let result = try await llmService.complete(
            apiKey: apiKey,
            model: model,
            systemPrompt: systemPrompt,
            history: history
        )
        
        state.setContent(result.content)
        state.setReasoning(result.reasoning)
        
        // Check if we need to update existing streaming message or create new one
        if let messageCount = delegate?.orchestrationNeedsMessageCount(),
           messageCount > 0,
           let lastMessage = delegate?.orchestrationNeedsMessage(at: messageCount - 1),
           lastMessage.state == .streaming {
            // Update existing streaming message
            let updatedMessage = MessageFactory.updated(
                lastMessage,
                content: result.content,
                reasoning: result.reasoning,
                state: .completed
            )
            delegate?.orchestrationDidUpdateMessage(at: messageCount - 1, with: updatedMessage)
            state.setMessageIndex(messageCount - 1)
        } else {
            // Create new message
            let message = MessageFactory.assistant(
                content: result.content,
                reasoning: result.reasoning
            )
            delegate?.orchestrationDidCreateMessage(message)
            if let messageCount = delegate?.orchestrationNeedsMessageCount() {
                state.setMessageIndex(messageCount - 1)
            }
        }
        
        return state
    }
    
    // MARK: - Tool Processing
    
    /// Process tool calls if present in the response
    private func processToolCallsIfNeeded(
        _ responseState: AssistantResponseState
    ) async throws -> ToolExecutionCoordinator.ToolExecutionResult {
        let result = try await toolCoordinator.processToolCalls(
            in: responseState,
            messageIndex: responseState.messageIndex
        )
        
        // Tool coordinator has already updated the message via its delegate
        // Just return the result
        return result
    }
    
    /// Finalize the response (no tool calls)
    private func finalizeResponse(_ state: AssistantResponseState) async throws {
        var finalContent = state.content
        
        // Defensive check: if content is empty, create fallback
        if finalContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            logger.log(ConversationLogger.LogLevel.warning, "Final response is empty, using fallback", context: "finalizeResponse")
            finalContent = "I've processed your request, but encountered an issue generating a response. Please try again."
        }
        
        guard let idx = state.messageIndex,
              let message = delegate?.orchestrationNeedsMessage(at: idx) else {
            // No existing message, create one
            let message = MessageFactory.assistant(
                content: finalContent,
                reasoning: state.reasoning
            )
            delegate?.orchestrationDidCreateMessage(message)
            delegate?.orchestrationDidUpdateState(.finalizing)
            return
        }
        
        // Update existing message (works for both streaming and non-streaming)
        // Always preserve reasoning when finalizing
        let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let contentToApply = trimmed.isEmpty ? finalContent : message.content
        let updatedMessage = MessageFactory.updated(
            message,
            content: contentToApply,
            reasoning: state.reasoning,
            state: .completed
        )
        delegate?.orchestrationDidUpdateMessage(at: idx, with: updatedMessage)
        
        delegate?.orchestrationDidUpdateState(.finalizing)
    }
}