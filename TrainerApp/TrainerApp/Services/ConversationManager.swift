import Foundation
import SwiftUI

/// Manages conversation flow, message handling, and coordination between streaming, tools, and persistence
@MainActor
class ConversationManager: ObservableObject {
    // MARK: - Published Properties
    @Published var messages: [ChatMessage] = []
    @Published var conversationState: ConversationState = .idle
    
    // MARK: - Private Properties
    private let persistence = ConversationPersistence()
    private let toolProcessor = ToolProcessor.shared
    private let maxConversationTurns = 5
    
    // MARK: - Public Interface
    
    /// Initialize and load existing conversation
    func initialize() async {
        await loadConversation()
    }
    
    /// Send a message and handle the complete conversation flow
    func sendMessage(_ text: String, apiKey: String, model: String, systemPrompt: String) async throws {
        // Create and add user message
        let userMessage = ChatMessage(role: .user, content: text)
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
            print("❌ Failed to load conversation: \(error)")
            messages = []
        }
    }
    
    /// Clear all messages and persistence
    func clearConversation() async {
        messages.removeAll()
        do {
            try persistence.clear()
        } catch {
            print("❌ Failed to clear conversation: \(error)")
        }
    }
    
    // MARK: - Private Implementation
    
    /// Handle the complete conversation flow with streaming and tool processing
    private func handleConversationFlow(
        apiKey: String,
        model: String,
        systemPrompt: String
    ) async throws {
        var conversationHistory = messages
        var finalResponse = ""
        var turns = 0
        var assistantIndex: Int? = nil
        
        repeat {
            turns += 1
            
            if turns == 1 {
                // First turn: Handle streaming response
                let streamingResult = try await handleStreamingResponse(
                    apiKey: apiKey,
                    model: model,
                    systemPrompt: systemPrompt,
                    conversationHistory: conversationHistory
                )
                assistantIndex = streamingResult.assistantIndex
                finalResponse = streamingResult.finalResponse
            } else {
                // Follow-up turns: Handle non-streaming response
                finalResponse = try await handleFollowUpResponse(
                    apiKey: apiKey,
                    model: model,
                    systemPrompt: systemPrompt,
                    conversationHistory: conversationHistory,
                    assistantIndex: assistantIndex
                )
                break
            }
            
            // Process tool calls if any
            let processedResponse = try await toolProcessor.processResponseWithToolCalls(finalResponse)
            
            if !processedResponse.toolResults.isEmpty {
                print("⏱️ tools_start: \(Date().timeIntervalSince1970)")
                
                // Show tool processing states
                for result in processedResponse.toolResults {
                    updateState(.processingTool(name: result.toolName, description: getToolDescription(result.toolName)))
                    try? await Task.sleep(for: .milliseconds(500))
                }
                
                // ALWAYS preserve the original assistant message with clean content
                if let idx = assistantIndex, idx < messages.count {
                    // Extract clean content (everything before first tool call)
                    let cleanContent = extractCleanContentBeforeTools(from: finalResponse)
                    if !cleanContent.isEmpty {
                        messages[idx] = ChatMessage(
                            id: messages[idx].id,
                            role: .assistant,
                            content: cleanContent,
                            date: messages[idx].date,
                            state: .completed
                        )
                    } else {
                        messages[idx] = messages[idx].markCompleted()
                    }
                }
                
                // Update conversation history with cleaned response
                if !processedResponse.cleanedResponse.isEmpty {
                    conversationHistory.append(
                        ChatMessage(role: .assistant, content: processedResponse.cleanedResponse)
                    )
                }
                
                // Add tool results as system message
                let toolResultsMessage = toolProcessor.formatToolResults(processedResponse.toolResults)
                conversationHistory.append(
                    ChatMessage(role: .system, content: toolResultsMessage)
                )
                
                print("⏱️ tools_complete: \(Date().timeIntervalSince1970)")
                // ALWAYS continue loop for AI's response to tool results
            } else {
                // No tool calls, finalize the response
                finalResponse = processedResponse.cleanedResponse
                
                // DEBUG: Log the response processing state
                print("🔍 DEBUG ConversationManager: Response processing state:")
                print("🔍   cleanedResponse: '\(processedResponse.cleanedResponse)'")
                print("🔍   toolResults.count: \(processedResponse.toolResults.count)")
                print("🔍   requiresFollowUp: \(processedResponse.requiresFollowUp)")
                print("🔍   finalResponse: '\(finalResponse)'")
                
                // Defensive check: if cleaned response is empty, use a fallback
                if finalResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    print("⚠️ ConversationManager: Cleaned response is empty, checking tool results...")
                    
                    // If we have tool results but they didn't trigger follow-up, format them
                    if !processedResponse.toolResults.isEmpty {
                        print("🔍 DEBUG: Tool results exist but no follow-up - this is the fallback trigger!")
                        let toolResultsMessage = toolProcessor.formatToolResults(processedResponse.toolResults)
                        finalResponse = "Task completed successfully.\n\n\(toolResultsMessage)"
                        print("✅ ConversationManager: Using tool results as fallback response")
                    } else {
                        print("🚨 DEBUG: No tool results and empty response - showing error message!")
                        finalResponse = "I've processed your request, but encountered an issue generating a response. Please try again."
                        print("⚠️ ConversationManager: Using generic fallback response")
                    }
                }
                
                // For final responses without tool follow-up, update only if streaming or append new message
                if let idx = assistantIndex, idx < messages.count {
                    if messages[idx].state == .streaming {
                        // Update streaming message with final content and mark completed
                        messages[idx] = ChatMessage(
                            id: messages[idx].id,
                            role: .assistant,
                            content: finalResponse,
                            date: messages[idx].date,
                            state: .completed
                        )
                    }
                } else {
                    // Fallback: append new message if no streaming message exists
                    messages.append(ChatMessage(role: .assistant, content: finalResponse, state: .completed))
                }
                updateState(.finalizing)
                break
            }
            
        } while turns < maxConversationTurns
        
        await persistMessages()
        
        // Brief pause before returning to idle
        try? await Task.sleep(for: .milliseconds(200))
        updateState(.idle)
    }
    
    /// Handle streaming response for first turn
    private func handleStreamingResponse(
        apiKey: String,
        model: String,
        systemPrompt: String,
        conversationHistory: [ChatMessage]
    ) async throws -> (assistantIndex: Int?, finalResponse: String) {
        updateState(.streaming(progress: nil))
        
        let requestStart = Date()
        print("⏱️ request_start: \(requestStart.timeIntervalSince1970)")
        
        var streamedFullText = ""
        var tokenBuffer = ""
        var isBufferingTool = false
        var messageCreated = false
        var assistantIndex: Int? = nil
        
        let assistantText: String
        
        do {
            assistantText = try await LLMClient.streamComplete(
                apiKey: apiKey,
                model: model,
                systemPrompt: systemPrompt,
                history: conversationHistory,
                onToken: { [weak self] token in
                    guard let self = self else { return }
                    
                    // Buffer tokens to detect tool patterns early
                    tokenBuffer.append(token)
                    
                    // 🔍 DIAGNOSTIC: Log token buffering
                    if tokenBuffer.count % 50 == 0 || tokenBuffer.contains("[TOOL_CALL:") {
                        print("🔍 STREAM_DEBUG: Buffer length=\(tokenBuffer.count), isBuffering=\(isBufferingTool)")
                        print("🔍 STREAM_DEBUG: Last 100 chars: '\(String(tokenBuffer.suffix(100)))'")
                    }
                    
                    // Check for tool pattern in buffer
                    if tokenBuffer.contains("[TOOL_CALL:") && !isBufferingTool {
                        isBufferingTool = true
                        print("🔍 STREAM_DEBUG: TOOL DETECTED - Switching to buffering mode")
                        print("🔍 STREAM_DEBUG: Buffer at detection: '\(tokenBuffer)'")
                        
                        // Extract tool name for specific feedback
                        if let toolName = self.extractToolName(from: tokenBuffer) {
                            print("🔍 STREAM_DEBUG: Extracted tool name: '\(toolName)'")
                            Task { @MainActor in
                                self.updateState(.processingTool(
                                    name: toolName,
                                    description: self.getToolDescription(toolName)
                                ))
                            }
                        } else {
                            print("🔍 STREAM_DEBUG: Failed to extract tool name from buffer")
                        }
                    } else if !isBufferingTool {
                        // Only append non-tool content to visible message
                        streamedFullText.append(token)
                        Task { @MainActor in
                            // Create message on first content token
                            if !messageCreated && !streamedFullText.isEmpty {
                                let newMessage = ChatMessage(role: .assistant, content: streamedFullText, state: .streaming)
                                self.messages.append(newMessage)
                                assistantIndex = self.messages.count - 1
                                messageCreated = true
                                print("🔍 STREAM_DEBUG: Created streaming message")
                            } else if let idx = assistantIndex, idx < self.messages.count, self.messages[idx].state == .streaming {
                                // Only update if message is still in streaming state
                                if let updatedMessage = self.messages[idx].updatedContent(streamedFullText) {
                                    self.messages[idx] = updatedMessage
                                }
                            }
                        }
                    }
                    
                    // Keep full text for processing
                    if isBufferingTool {
                        streamedFullText = tokenBuffer
                        print("🔍 STREAM_DEBUG: Updated streamedFullText length: \(streamedFullText.count)")
                    }
                }
            )
        } catch {
            // Fallback to non-streaming
            print("⚠️ Streaming failed: \(error). Falling back to non-streaming.")
            let fallbackText = try await LLMClient.complete(
                apiKey: apiKey,
                model: model,
                systemPrompt: systemPrompt,
                history: conversationHistory
            )
            
            // Ensure user sees a response
            if let idx = assistantIndex, idx < messages.count {
                if messages[idx].state == .streaming {
                    // Update streaming message with fallback content and mark completed
                    messages[idx] = ChatMessage(
                        id: messages[idx].id,
                        role: .assistant,
                        content: fallbackText,
                        date: messages[idx].date,
                        state: .completed
                    )
                }
            } else {
                messages.append(ChatMessage(role: .assistant, content: fallbackText, state: .completed))
                assistantIndex = messages.count - 1
            }
            streamedFullText = fallbackText
            assistantText = fallbackText
        }
        
        print("⏱️ response_complete (streamed): \(Date().timeIntervalSince1970)")
        print("🔍 STREAM_DEBUG: Final assistantText length: \(assistantText.count)")
        print("🔍 STREAM_DEBUG: Final streamedFullText length: \(streamedFullText.count)")
        print("🔍 STREAM_DEBUG: Final assistantText preview: '\(String(assistantText.prefix(200)))...'")
        
        return (assistantIndex: assistantIndex, finalResponse: assistantText)
    }
    
    /// Handle non-streaming response for follow-up turns
    private func handleFollowUpResponse(
        apiKey: String,
        model: String,
        systemPrompt: String,
        conversationHistory: [ChatMessage],
        assistantIndex: Int?
    ) async throws -> String {
        updateState(.preparingResponse)
        
        do {
            let assistantText = try await LLMClient.complete(
                apiKey: apiKey,
                model: model,
                systemPrompt: systemPrompt,
                history: conversationHistory
            )
            
            // DEBUG: Log the full response before processing
            print("🔍 DEBUG handleFollowUpResponse: Raw AI response: '\(assistantText)'")
            
            let processedResponse = try await toolProcessor.processResponseWithToolCalls(assistantText)
            let finalResponse = processedResponse.cleanedResponse
            
            print("🔍 DEBUG handleFollowUpResponse: Cleaned response: '\(finalResponse)'")
            print("🔍 DEBUG handleFollowUpResponse: Tool results count: \(processedResponse.toolResults.count)")
            
            // For follow-up responses, always append a new message instead of replacing
            if !finalResponse.isEmpty {
                messages.append(ChatMessage(role: .assistant, content: finalResponse, state: .completed))
                print("📝 Follow-up response: Appended new assistant message with content: '\(finalResponse)'")
            } else {
                print("⚠️ WARNING: Follow-up response is empty after processing!")
                
                // Try to generate meaningful response from tool results instead of showing raw tool calls
                let meaningfulResponse = try await generateMeaningfulResponse(from: conversationHistory)
                messages.append(ChatMessage(role: .assistant, content: meaningfulResponse, state: .completed))
                print("✅ RECOVERY: Generated meaningful response from tool results: '\(meaningfulResponse)'")
            }
            
            updateState(.finalizing)
            return finalResponse
        } catch LLMError.missingContent {
            // Create a meaningful response based on tool results
            return try await handleEmptyResponse(conversationHistory: conversationHistory)
        }
    }
    /// Handle empty responses by generating meaningful content from tool results
    private func handleEmptyResponse(conversationHistory: [ChatMessage]) async throws -> String {
        print("🔍 handleEmptyResponse: AI returned empty content, generating response from tool results")
        
        // Extract meaningful information from recent tool results
        let recentSystemMessages = conversationHistory.suffix(3).filter { $0.role == .system }
        var responseComponents: [String] = []
        
        // Look for specific tool result patterns
        for message in recentSystemMessages {
            if message.content.contains("[Structured Workout Planned]") {
                // Extract workout details
                let lines = message.content.components(separatedBy: "\n")
                for line in lines {
                    if line.contains("• Workout: ") || line.contains("• Exercises: ") || line.contains("• Duration: ") {
                        responseComponents.append(line.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }
            }
            
            if message.content.contains("[Training Status]") || message.content.contains("Current Block:") {
                responseComponents.append("I've checked your training status and everything is set up.")
            }
            
            if message.content.contains("Hypertrophy-Strength") {
                responseComponents.append("You're in the Hypertrophy-Strength phase - perfect for building strength and muscle.")
            }
        }
        
        let meaningfulResponse = responseComponents.isEmpty
            ? "Great! I've completed the requested actions and everything is set up for you."
            : "Perfect! I've completed the setup:\n\n" + responseComponents.joined(separator: "\n")
        
        // Append new message with meaningful content
        messages.append(ChatMessage(role: .assistant, content: meaningfulResponse, state: .completed))
        print("✅ Generated meaningful response from tool results: '\(meaningfulResponse)'")
        
        updateState(.finalizing)
        return meaningfulResponse
    }
    
    /// Generate meaningful response from recent tool results
    private func generateMeaningfulResponse(from conversationHistory: [ChatMessage]) async throws -> String {
        print("🔧 generateMeaningfulResponse: Generating response from tool results")
        
        // Extract meaningful information from recent tool results
        let recentSystemMessages = conversationHistory.suffix(3).filter { $0.role == .system }
        var responseComponents: [String] = []
        
        // Look for specific tool result patterns
        for message in recentSystemMessages {
            if message.content.contains("[Structured Workout Planned]") {
                // Extract workout details
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
            print("💾 Persist called with \(messages.count) messages")
        } catch {
            print("❌ Persist error: \(error)")
        }
    }
    
    /// Extract tool name from token buffer
    private func extractToolName(from buffer: String) -> String? {
        if let colonRange = buffer.range(of: ":"),
           let toolNameStart = buffer.index(colonRange.upperBound, offsetBy: 1, limitedBy: buffer.endIndex) {
            let toolNameEnd = buffer.firstIndex(of: "(") ?? buffer.firstIndex(of: "]") ?? buffer.endIndex
            return String(buffer[toolNameStart..<toolNameEnd]).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
    
    /// Get tool description for UI display
    private func getToolDescription(_ toolName: String) -> String {
        return toolDescriptions[toolName]?.description ?? "Processing \(toolName)..."
    }
    
    /// Extract clean content before the first tool call
    private func extractCleanContentBeforeTools(from response: String) -> String {
        // Find the first occurrence of [TOOL_CALL:
        if let toolCallRange = response.range(of: "[TOOL_CALL:") {
            let cleanContent = String(response[..<toolCallRange.lowerBound])
            return cleanContent.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // No tool calls found, return the entire response
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