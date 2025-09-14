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
            
            if processedResponse.requiresFollowUp && !processedResponse.toolResults.isEmpty {
                print("⏱️ tools_start: \(Date().timeIntervalSince1970)")
                
                // Show tool processing states
                for result in processedResponse.toolResults {
                    updateState(.processingTool(name: result.toolName, description: getToolDescription(result.toolName)))
                    try? await Task.sleep(for: .milliseconds(500))
                }
                
                // Update conversation history with cleaned response
                if !processedResponse.cleanedResponse.isEmpty {
                    conversationHistory.append(
                        ChatMessage(role: .assistant, content: processedResponse.cleanedResponse)
                    )
                    
                    // Update visible message
                    if let idx = assistantIndex {
                        messages[idx] = ChatMessage(role: .assistant, content: processedResponse.cleanedResponse)
                    }
                }
                
                // Add tool results as system message
                let toolResultsMessage = toolProcessor.formatToolResults(processedResponse.toolResults)
                conversationHistory.append(
                    ChatMessage(role: .system, content: toolResultsMessage)
                )
                
                print("⏱️ tools_complete: \(Date().timeIntervalSince1970)")
                // Continue loop for AI's response to tool results
            } else {
                // No tool calls, finalize the response
                finalResponse = processedResponse.cleanedResponse
                if let idx = assistantIndex {
                    messages[idx] = ChatMessage(role: .assistant, content: finalResponse)
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
                    
                    // Check for tool pattern in buffer
                    if tokenBuffer.contains("[TOOL_CALL:") && !isBufferingTool {
                        isBufferingTool = true
                        // Extract tool name for specific feedback
                        if let toolName = self.extractToolName(from: tokenBuffer) {
                            Task { @MainActor in
                                self.updateState(.processingTool(
                                    name: toolName,
                                    description: self.getToolDescription(toolName)
                                ))
                            }
                        }
                    } else if !isBufferingTool {
                        // Only append non-tool content to visible message
                        streamedFullText.append(token)
                        Task { @MainActor in
                            // Create message on first content token
                            if !messageCreated && !streamedFullText.isEmpty {
                                let newMessage = ChatMessage(role: .assistant, content: streamedFullText)
                                self.messages.append(newMessage)
                                assistantIndex = self.messages.count - 1
                                messageCreated = true
                            } else if let idx = assistantIndex {
                                // Update existing message
                                self.messages[idx] = ChatMessage(role: .assistant, content: streamedFullText)
                            }
                        }
                    }
                    
                    // Keep full text for processing
                    if isBufferingTool {
                        streamedFullText = tokenBuffer
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
            if let idx = assistantIndex {
                messages[idx] = ChatMessage(role: .assistant, content: fallbackText)
            } else {
                messages.append(ChatMessage(role: .assistant, content: fallbackText))
                assistantIndex = messages.count - 1
            }
            streamedFullText = fallbackText
            assistantText = fallbackText
        }
        
        print("⏱️ response_complete (streamed): \(Date().timeIntervalSince1970)")
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
        
        let assistantText = try await LLMClient.complete(
            apiKey: apiKey,
            model: model,
            systemPrompt: systemPrompt,
            history: conversationHistory
        )
        
        let processedResponse = try await toolProcessor.processResponseWithToolCalls(assistantText)
        let finalResponse = processedResponse.cleanedResponse
        
        if let idx = assistantIndex {
            messages[idx] = ChatMessage(role: .assistant, content: finalResponse)
        } else {
            // Fallback: append if no streaming bubble present
            messages.append(ChatMessage(role: .assistant, content: finalResponse))
        }
        
        updateState(.finalizing)
        return finalResponse
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