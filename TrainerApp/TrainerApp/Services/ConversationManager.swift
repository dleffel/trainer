import Foundation
import SwiftUI
import UIKit

/// Manages conversation flow, message handling, and coordination between streaming, tools, and persistence
@MainActor
class ConversationManager: ObservableObject {
    // MARK: - Published Properties
    @Published var messages: [ChatMessage] = []
    @Published var conversationState: ConversationState = .idle
    
    // Reasoning preview state for UI
    @Published private(set) var isStreamingReasoning: Bool = false
    @Published private(set) var latestReasoningChunk: String? = nil
    
    // MARK: - Private Properties
    private let persistence = ConversationPersistence()
    private let toolProcessor = ToolProcessor.shared
    private let llmService: LLMServiceProtocol
    private let config: AppConfiguration
    private let logger = ConversationLogger.shared
    private let streamingCoordinator: StreamingCoordinator
    private let maxConversationTurns = 5
    
    // MARK: - Computed Properties
    
    /// Computed property: messages suitable for API context
    /// This replaces the previous dual-array pattern (messages + conversationHistory)
    private var apiHistory: [ChatMessage] {
        messages.filter { message in
            // Only include completed messages in API history
            message.state == .completed
        }
    }
    
    // MARK: - Initialization
    
    init(
        config: AppConfiguration = .shared,
        llmService: LLMServiceProtocol = LLMService.shared
    ) {
        self.config = config
        self.llmService = llmService
        self.streamingCoordinator = StreamingCoordinator(llmService: llmService)
        
        // Set up streaming delegate after initialization
        Task { @MainActor in
            self.streamingCoordinator.delegate = self
        }
    }
    
    // MARK: - Public Interface
    
    /// Initialize and load existing conversation
    func initialize() async {
        await loadConversation()
    }
    
    /// Send a message - configuration handled internally
    func sendMessage(_ text: String, images: [UIImage] = []) async throws {
        guard config.hasValidApiKey else {
            throw ConfigurationError.missingApiKey
        }
        
        try await sendMessageWithConfig(
            text,
            images: images,
            apiKey: config.apiKey,
            model: config.model,
            systemPrompt: config.systemPrompt
        )
    }
    
    /// Internal implementation with explicit configuration (for testing/flexibility)
    private func sendMessageWithConfig(_ text: String, images: [UIImage], apiKey: String, model: String, systemPrompt: String) async throws {
        // Create and add user message using MessageFactory
        let userMessage = images.isEmpty
            ? MessageFactory.user(content: text)
            : MessageFactory.userWithImages(content: text, images: images)
        
        messages.append(userMessage)
        await persistMessages()
        
        // Start conversation flow
        updateState(.preparingResponse)
        
        try await handleConversationFlow(
            apiKey: apiKey,
            model: model,
            systemPrompt: systemPrompt
        )
    }
    
    /// Load conversation from persistence
    func loadConversation() async {
        do {
            messages = try persistence.load()
        } catch {
            logger.logError(error, context: "loadConversation")
            messages = []
        }
    }
    
    /// Clear all messages and persistence
    func clearConversation() async {
        messages.removeAll()
        do {
            try persistence.clear()
        } catch {
            logger.logError(error, context: "clearConversation")
        }
    }
    
    // MARK: - Conversation Flow
    
    /// Handle the complete conversation flow with streaming and tool processing
    private func handleConversationFlow(
        apiKey: String,
        model: String,
        systemPrompt: String
    ) async throws {
        var responseState = AssistantResponseState()
        var turns = 0
        
        repeat {
            turns += 1
            
            // Get assistant response (streaming on first turn, non-streaming on follow-ups)
            responseState = try await (turns == 1
                ? handleInitialResponse(apiKey: apiKey, model: model, systemPrompt: systemPrompt)
                : handleFollowUpResponse(apiKey: apiKey, model: model, systemPrompt: systemPrompt))
            
            // Process tool calls if any
            let toolResult = try await processToolCallsIfNeeded(responseState)
            
            if toolResult.hasTools {
                // Continue loop for assistant's response to tools
                continue
            } else {
                // Finalize and exit
                try await finalizeResponse(responseState)
                break
            }
            
        } while turns < maxConversationTurns
        
        await persistMessages()
        
        // Brief pause before returning to idle
        try? await Task.sleep(for: .milliseconds(200))
        updateState(.idle)
    }
    
    /// Handle initial response with streaming
    private func handleInitialResponse(
        apiKey: String,
        model: String,
        systemPrompt: String
    ) async throws -> AssistantResponseState {
        updateState(.streaming(progress: nil))
        
        let requestStart = Date()
        logger.logTiming("request_start", timestamp: requestStart.timeIntervalSince1970)
        
        var state: AssistantResponseState
        
        // Attempt streaming
        do {
            state = try await streamResponse(
                apiKey: apiKey,
                model: model,
                systemPrompt: systemPrompt
            )
        } catch {
            // Clean up any dangling .streaming message before fallback
            if let lastMessage = messages.last, lastMessage.state == .streaming {
                messages.removeLast()
                logger.log(ConversationLogger.LogLevel.debug, "Removed dangling streaming message before fallback", context: "handleInitialResponse")
            }
            
            // Fallback to non-streaming
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
        updateState(.preparingResponse)
        
        do {
            let result = try await llmService.complete(
                apiKey: apiKey,
                model: model,
                systemPrompt: systemPrompt,
                history: apiHistory
            )
            
            logger.log(ConversationLogger.LogLevel.debug, "Raw AI response: '\(result.content)'", context: "handleFollowUpResponse")
            if let reasoning = result.reasoning {
                logger.log(ConversationLogger.LogLevel.debug, "Reasoning: '\(reasoning)'", context: "handleFollowUpResponse")
            }
            
            let processedResponse = try await toolProcessor.processResponseWithToolCalls(result.content)
            let finalResponse = processedResponse.cleanedResponse
            
            logger.log(ConversationLogger.LogLevel.debug, "Cleaned response: '\(finalResponse)'", context: "handleFollowUpResponse")
            logger.log(ConversationLogger.LogLevel.debug, "Tool results count: \(processedResponse.toolResults.count)", context: "handleFollowUpResponse")
            
            // Create state from response
            var state = AssistantResponseState()
            
            if !finalResponse.isEmpty {
                state.setContent(finalResponse)
                state.setReasoning(result.reasoning)
                
                // Append new message for follow-up
                let message = MessageFactory.assistant(
                    content: finalResponse,
                    reasoning: result.reasoning
                )
                messages.append(message)
                state.setMessageIndex(messages.count - 1)
                
                logger.log(ConversationLogger.LogLevel.debug, "Appended new assistant message", context: "handleFollowUpResponse")
            } else {
                logger.log(ConversationLogger.LogLevel.warning, "Follow-up response is empty after processing!", context: "handleFollowUpResponse")
                
                // Generate meaningful response from tool results
                let meaningfulResponse = generateMeaningfulResponseContent(from: apiHistory)
                state.setContent(meaningfulResponse)
                state.setReasoning(result.reasoning)
                
                let message = MessageFactory.assistant(
                    content: meaningfulResponse,
                    reasoning: result.reasoning
                )
                messages.append(message)
                state.setMessageIndex(messages.count - 1)
                
                logger.log(ConversationLogger.LogLevel.info, "Generated meaningful response from tool results", context: "handleFollowUpResponse")
            }
            
            updateState(.finalizing)
            return state
            
        } catch LLMError.missingContent {
            // Create a meaningful response based on tool results
            return try await handleEmptyResponse()
        }
    }
    
    /// Handle empty LLM responses by generating meaningful content from tool results
    private func handleEmptyResponse() async throws -> AssistantResponseState {
        logger.log(ConversationLogger.LogLevel.debug, "AI returned empty content, generating response from tool results", context: "handleEmptyResponse")
        
        let meaningfulResponse = generateMeaningfulResponseContent(from: apiHistory)
        
        var state = AssistantResponseState()
        state.setContent(meaningfulResponse)
        
        // Append message
        let message = MessageFactory.assistant(content: meaningfulResponse)
        messages.append(message)
        state.setMessageIndex(messages.count - 1)
        
        logger.log(ConversationLogger.LogLevel.info, "Generated meaningful response from tool results: '\(meaningfulResponse)'", context: "handleEmptyResponse")
        
        updateState(.finalizing)
        return state
    }
    
    // MARK: - Tool Processing
    
    /// Result of tool processing
    private struct ToolProcessingResult {
        let hasTools: Bool
        let toolResults: [ToolProcessor.ToolCallResult]
        let cleanedResponse: String
    }
    
    /// Process tool calls if present in the response
    private func processToolCallsIfNeeded(
        _ responseState: AssistantResponseState
    ) async throws -> ToolProcessingResult {
        let processed = try await toolProcessor.processResponseWithToolCalls(responseState.content)
        
        if !processed.toolResults.isEmpty {
            logger.logTiming("tools_start", timestamp: Date().timeIntervalSince1970)
            
            // Show tool processing UI (no artificial delay - tools complete quickly)
            for result in processed.toolResults {
                updateState(.processingTool(
                    name: result.toolName,
                    description: "Processing \(result.toolName)..."
                ))
            }
            
            // Update in-flight streaming message with cleaned content and mark as completed
            if let idx = responseState.messageIndex, idx < messages.count {
                let cleanContent = extractCleanContentBeforeTools(from: responseState.content)
                if !cleanContent.isEmpty {
                    messages[idx] = MessageFactory.updated(
                        messages[idx],
                        content: cleanContent,
                        state: .completed
                    )
                } else {
                    messages[idx] = MessageFactory.completed(messages[idx])
                }
            }
            
            // Note: No need to append a separate assistant message here
            // The streaming message has been finalized and will be included in apiHistory
            // when its state is .completed
            
            // Add tool results as system message
            let toolMessage = MessageFactory.system(
                content: toolProcessor.formatToolResults(processed.toolResults)
            )
            messages.append(toolMessage)
            
            logger.logTiming("tools_complete", timestamp: Date().timeIntervalSince1970)
            
            return ToolProcessingResult(
                hasTools: true,
                toolResults: processed.toolResults,
                cleanedResponse: processed.cleanedResponse
            )
        }
        
        return ToolProcessingResult(
            hasTools: false,
            toolResults: [],
            cleanedResponse: processed.cleanedResponse
        )
    }
    
    /// Finalize the response (no tool calls)
    private func finalizeResponse(_ state: AssistantResponseState) async throws {
        var finalContent = state.content
        
        // Defensive check: if content is empty, create fallback
        if finalContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            logger.log(ConversationLogger.LogLevel.warning, "Final response is empty, using fallback", context: "finalizeResponse")
            finalContent = "I've processed your request, but encountered an issue generating a response. Please try again."
        }
        
        guard let idx = state.messageIndex, idx < messages.count else {
            // No existing message, create one
            let message = MessageFactory.assistant(
                content: finalContent,
                reasoning: state.reasoning
            )
            messages.append(message)
            updateState(.finalizing)
            return
        }
        
        // Update existing message if still streaming
        if messages[idx].state == .streaming {
            messages[idx] = MessageFactory.updated(
                messages[idx],
                content: finalContent,
                state: .completed
            )
        }
        
        updateState(.finalizing)
    }
    
    // MARK: - Streaming Support
    
    /// Stream response from LLM service (delegates to StreamingCoordinator)
    private func streamResponse(
        apiKey: String,
        model: String,
        systemPrompt: String
    ) async throws -> AssistantResponseState {
        let result = try await streamingCoordinator.streamResponse(
            apiKey: apiKey,
            model: model,
            systemPrompt: systemPrompt,
            history: apiHistory
        )
        
        // Message already added via delegate, just return the state
        return result.state
    }
    
    /// Fallback to non-streaming when streaming fails
    private func fallbackNonStreaming(
        apiKey: String,
        model: String,
        systemPrompt: String
    ) async throws -> AssistantResponseState {
        var state = AssistantResponseState()
        let result = try await llmService.complete(
            apiKey: apiKey,
            model: model,
            systemPrompt: systemPrompt,
            history: apiHistory
        )
        
        state.setContent(result.content)
        state.setReasoning(result.reasoning)
        
        // Create or update message
        if let idx = state.messageIndex, idx < messages.count, messages[idx].state == .streaming {
            // Update existing streaming message
            messages[idx] = MessageFactory.updated(
                messages[idx],
                content: result.content,
                reasoning: result.reasoning,
                state: .completed
            )
        } else {
            // Create new message
            let message = MessageFactory.assistant(
                content: result.content,
                reasoning: result.reasoning
            )
            messages.append(message)
            state.setMessageIndex(messages.count - 1)
        }
        
        return state
    }
    
    // MARK: - Helper Methods
    
    /// Generate meaningful response content from tool results
    private func generateMeaningfulResponseContent(from history: [ChatMessage]) -> String {
        let recentSystemMessages = history.suffix(3).filter { $0.role == .system }
        var responseComponents: [String] = []
        
        for message in recentSystemMessages {
            if message.content.contains("[Structured Workout Planned]") {
                let lines = message.content.components(separatedBy: "\n")
                for line in lines {
                    if line.contains("• Workout: ") || line.contains("• Exercises: ") || line.contains("• Duration: ") {
                        responseComponents.append(line.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }
            }
            
            if message.content.contains("[Training Status]") || message.content.contains("Current Block:") {
                responseComponents.append("I've checked your training status and you're all set!")
            }
            
            if message.content.contains("Hypertrophy-Strength") {
                responseComponents.append("You're in the Hypertrophy-Strength phase - perfect for building strength.")
            }
        }
        
        return responseComponents.isEmpty
            ? "Great! I've completed the requested actions and everything is set up for you."
            : "Perfect! I've completed the setup:\n\n" + responseComponents.joined(separator: "\n")
    }
    
    /// Update conversation state with animation
    private func updateState(_ newState: ConversationState) {
        withAnimation(.easeInOut(duration: 0.3)) {
            conversationState = newState
        }
    }
    
    /// Persist messages to storage
    private func persistMessages() async {
        do {
            try persistence.save(messages)
            logger.logPersistence("save", messageCount: messages.count)
        } catch {
            logger.logError(error, context: "persistMessages")
        }
    }
    
    
    /// Extract clean content before the first tool call
    private func extractCleanContentBeforeTools(from response: String) -> String {
        if let toolCallRange = response.range(of: "[TOOL_CALL:") {
            let cleanContent = String(response[..<toolCallRange.lowerBound])
            return cleanContent.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Conversation State

/// Represents the current state of the conversation
enum ConversationState: Equatable {
    case idle
    case preparingResponse
    case streaming(progress: String?)
    case processingTool(name: String, description: String)
    case finalizing
    case error(String)
}

// MARK: - State Mapping Extension

extension ConversationState {
    /// Map ConversationState to ChatState for UI compatibility
    var chatState: ChatState {
        switch self {
        case .idle:
            return .idle
        case .preparingResponse:
            return .preparingResponse
        case .streaming(let progress):
            return .streaming(progress: progress)
        case .processingTool(let name, let description):
            return .processingTool(name: name, description: description)
        case .finalizing:
            return .finalizing
        case .error:
            return .idle // Handle errors via separate error message in UI
        }
    }
}

// MARK: - StreamingStateDelegate

extension ConversationManager: StreamingStateDelegate {
    func streamingDidCreateMessage(_ message: ChatMessage) -> Int {
        // Append the message and return its index
        messages.append(message)
        let index = messages.count - 1
        logger.log(ConversationLogger.LogLevel.debug, "Streaming message created at index \(index)", context: "Streaming")
        return index
    }
    
    func streamingDidUpdateMessage(at index: Int, with message: ChatMessage) {
        // Update our messages array with the latest version
        if index < messages.count {
            messages[index] = message
        }
    }
    
    func streamingDidDetectTool(name: String, description: String) {
        updateState(.processingTool(name: name, description: description))
    }
    
    func streamingDidUpdateReasoningState(isStreaming: Bool, latestChunk: String?) {
        self.isStreamingReasoning = isStreaming
        self.latestReasoningChunk = latestChunk
    }
}