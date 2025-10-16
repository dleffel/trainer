import Foundation
import SwiftUI

/// Delegate protocol for streaming state updates
@MainActor
protocol StreamingStateDelegate: AnyObject {
    /// Called when a streaming message is created
    func streamingDidCreateMessage(_ message: ChatMessage)
    
    /// Called when a streaming message is updated
    func streamingDidUpdateMessage(at index: Int, with message: ChatMessage)
    
    /// Called when a tool is detected during streaming
    func streamingDidDetectTool(name: String, description: String)
    
    /// Called when reasoning stream state changes
    func streamingDidUpdateReasoningState(isStreaming: Bool, latestChunk: String?)
}

/// Coordinates streaming responses from the LLM service
///
/// Handles token buffering, tool detection during streaming, reasoning accumulation,
/// and message creation/updates. Delegates UI state updates back to ConversationManager.
@MainActor
class StreamingCoordinator {
    // MARK: - Dependencies
    private let llmService: LLMServiceProtocol
    private let logger = ConversationLogger.shared
    weak var delegate: StreamingStateDelegate?
    
    // MARK: - Initialization
    init(llmService: LLMServiceProtocol) {
        self.llmService = llmService
    }
    
    // MARK: - Public Interface
    
    /// Result of streaming operation
    struct StreamingResult {
        let state: AssistantResponseState
        let createdMessage: ChatMessage?
        let detectedToolCall: Bool
    }
    
    /// Stream a response and return the final state
    /// - Parameters:
    ///   - apiKey: The API key for authentication
    ///   - model: The model identifier
    ///   - systemPrompt: The system prompt
    ///   - history: The conversation history for context
    /// - Returns: StreamingResult containing the final state
    func streamResponse(
        apiKey: String,
        model: String,
        systemPrompt: String,
        history: [ChatMessage]
    ) async throws -> StreamingResult {
        logger.logStreamingEvent(.started)
        
        var state = AssistantResponseState()
        var streamedContent = ""
        var streamedReasoning = ""
        var tokenBuffer = ""
        var isBufferingTool = false
        var messageCreated = false
        var createdMessage: ChatMessage? = nil
        var messageIndex: Int? = nil
        
        let result = try await llmService.streamComplete(
            apiKey: apiKey,
            model: model,
            systemPrompt: systemPrompt,
            history: history,
            onToken: { [weak self] token in
                guard let self = self else { return }
                
                tokenBuffer.append(token)
                
                // Diagnostic logging
                if tokenBuffer.count % 50 == 0 || tokenBuffer.contains("[TOOL_CALL:") {
                    self.logger.logStreamingEvent(.tokenReceived(count: tokenBuffer.count))
                }
                
                // Check for tool pattern
                if tokenBuffer.contains("[TOOL_CALL:") && !isBufferingTool {
                    isBufferingTool = true
                    self.logger.log(.debug, "Tool detected - switching to buffering mode", context: "Streaming")
                    
                    if let toolName = self.extractToolName(from: tokenBuffer) {
                        let description = self.getToolDescription(toolName)
                        Task { @MainActor in
                            self.delegate?.streamingDidDetectTool(name: toolName, description: description)
                        }
                    }
                } else if !isBufferingTool {
                    // Only append non-tool content
                    streamedContent.append(token)
                    
                    Task { @MainActor in
                        if !messageCreated && !streamedContent.isEmpty {
                            // Create streaming message
                            let message = MessageFactory.assistantStreaming(
                                content: streamedContent,
                                reasoning: streamedReasoning.isEmpty ? nil : streamedReasoning
                            )
                            createdMessage = message
                            messageCreated = true
                            self.logger.logStreamingEvent(.messageCreated(index: 0))
                            self.delegate?.streamingDidCreateMessage(message)
                        } else if messageCreated, let message = createdMessage {
                            // Update streaming message
                            if let updated = message.updatedContent(
                                streamedContent,
                                reasoning: streamedReasoning.isEmpty ? nil : streamedReasoning
                            ) {
                                createdMessage = updated
                                if let idx = messageIndex {
                                    self.delegate?.streamingDidUpdateMessage(at: idx, with: updated)
                                }
                            }
                        }
                    }
                }
                
                // Keep full text for processing
                if isBufferingTool {
                    streamedContent = tokenBuffer
                }
            },
            onReasoning: { [weak self] reasoning in
                guard let self = self else { return }
                streamedReasoning += reasoning
                self.logger.logStreamingEvent(.reasoningReceived(length: streamedReasoning.count))
                
                // Update message with reasoning in real-time
                Task { @MainActor in
                    // Publish reasoning chunk for preview UI
                    self.delegate?.streamingDidUpdateReasoningState(isStreaming: true, latestChunk: reasoning)
                    
                    if !messageCreated && !streamedReasoning.isEmpty {
                        // Create streaming message with reasoning (even if no content yet)
                        let message = MessageFactory.assistantStreaming(
                            content: streamedContent,
                            reasoning: streamedReasoning
                        )
                        createdMessage = message
                        messageCreated = true
                        self.logger.logStreamingEvent(.messageCreated(index: 0))
                        self.delegate?.streamingDidCreateMessage(message)
                    } else if messageCreated, let message = createdMessage {
                        // Update existing streaming message with new reasoning
                        if let updated = message.updatedContent(
                            streamedContent,
                            reasoning: streamedReasoning
                        ) {
                            createdMessage = updated
                            if let idx = messageIndex {
                                self.delegate?.streamingDidUpdateMessage(at: idx, with: updated)
                            }
                        }
                    }
                }
            }
        )
        
        // Store final content
        state.setContent(result.content)
        state.setReasoning(result.reasoning)
        
        // Clear reasoning streaming state
        delegate?.streamingDidUpdateReasoningState(isStreaming: false, latestChunk: nil)
        
        logger.logStreamingEvent(.completed)
        
        return StreamingResult(
            state: state,
            createdMessage: createdMessage,
            detectedToolCall: isBufferingTool
        )
    }
    
    // MARK: - Private Helpers
    
    /// Extract tool name from token buffer
    private func extractToolName(from buffer: String) -> String? {
        // Use canonical regex pattern to match complete tool calls only
        let pattern = #"\[TOOL_CALL:\s*(\w+)(?:\((.*?)\))?\]"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: buffer, range: NSRange(buffer.startIndex..., in: buffer)),
           let toolNameRange = Range(match.range(at: 1), in: buffer) {
            return String(buffer[toolNameRange])
        }
        return nil
    }
    
    /// Get tool description for UI display
    private func getToolDescription(_ toolName: String) -> String {
        let descriptions: [String: String] = [
            "get_health_data": "Fetching your health data from HealthKit",
            "start_training_program": "Starting your training program",
            "get_training_status": "Checking your training status",
            "get_schedule_snapshot": "Getting your training schedule",
            "plan_structured_workout": "Planning your workout",
            "update_structured_workout": "Updating your workout",
            "log_workout_set": "Logging your workout set"
        ]
        return descriptions[toolName] ?? "Processing \(toolName)..."
    }
}