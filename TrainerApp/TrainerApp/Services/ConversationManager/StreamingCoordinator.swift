import Foundation

/// Delegate protocol for streaming state updates
@MainActor
protocol StreamingStateDelegate: AnyObject {
    /// Called when a streaming message is created, returns the index where it was added
    func streamingDidCreateMessage(_ message: ChatMessage) -> Int
    
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
    
    // MARK: - Static Configuration
    
    /// Precompiled regex for tool detection (avoid recompiling per token)
    private static let toolRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"\[TOOL_CALL:\s*(\w+)(?:\((.*?)\))?\]"#)
    }()
    
    /// Maximum size of token buffer (prevents unbounded growth)
    private static let maxTokenBufferSize = 2000
    
    /// Update interval for batching UI updates (50ms = 20 FPS)
    private static let updateInterval: TimeInterval = 0.05
    
    // MARK: - Batching State
    
    /// Pending message update to be flushed
    private var pendingUpdate: (index: Int, message: ChatMessage)?
    
    /// Timer for batched updates
    private var updateTimer: Timer?
    
    // MARK: - Initialization
    init(llmService: LLMServiceProtocol) {
        self.llmService = llmService
    }
    
    // MARK: - Public Interface
    
    /// Result of streaming operation
    struct StreamingResult {
        let state: AssistantResponseState
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
        var messageIndex: Int? = nil
        
        let result = try await llmService.streamComplete(
            apiKey: apiKey,
            model: model,
            systemPrompt: systemPrompt,
            history: history,
            onToken: { [weak self] token in
                guard let self = self else { return }
                
                tokenBuffer.append(token)
                
                // Bound tokenBuffer to prevent unbounded growth (keep last 2k chars)
                if tokenBuffer.count > Self.maxTokenBufferSize {
                    let startIndex = tokenBuffer.index(tokenBuffer.endIndex, offsetBy: -Self.maxTokenBufferSize)
                    tokenBuffer = String(tokenBuffer[startIndex...])
                }
                
                // Diagnostic logging
                if tokenBuffer.count % 50 == 0 {
                    self.logger.logStreamingEvent(.tokenReceived(count: tokenBuffer.count))
                }
                
                // Check for tool pattern - only switch to buffering if we have a complete match
                if !isBufferingTool, let toolName = self.extractToolName(from: tokenBuffer) {
                    // Full regex match found - switch to buffering mode
                    isBufferingTool = true
                    self.logger.log(.debug, "Tool detected - switching to buffering mode", context: "Streaming")
                    
                    let description = self.getToolDescription(toolName)
                    Task { @MainActor in
                        self.delegate?.streamingDidDetectTool(name: toolName, description: description)
                    }
                } else if !isBufferingTool {
                    // Only append non-tool content
                    streamedContent.append(token)
                    
                    Task { @MainActor in
                        if !messageCreated && !streamedContent.isEmpty {
                            // Create streaming message (immediate - only happens once)
                            let message = MessageFactory.assistantStreaming(
                                content: streamedContent,
                                reasoning: streamedReasoning.isEmpty ? nil : streamedReasoning
                            )
                            messageCreated = true
                            // Get index from delegate
                            if let idx = self.delegate?.streamingDidCreateMessage(message) {
                                messageIndex = idx
                                self.logger.logStreamingEvent(.messageCreated(index: idx))
                            }
                        } else if messageCreated, let idx = messageIndex {
                            // Schedule batched update instead of immediate update
                            let updated = MessageFactory.assistantStreaming(
                                content: streamedContent,
                                reasoning: streamedReasoning.isEmpty ? nil : streamedReasoning
                            )
                            self.scheduleMessageUpdate(at: idx, with: updated)
                        }
                    }
                }
                
                // When tool detected, don't truncate content - use separate buffer
                // streamedContent already has all non-tool tokens up to detection point
                // tokenBuffer continues growing for full tool call capture
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
                        // Create streaming message with reasoning (immediate - only happens once)
                        let message = MessageFactory.assistantStreaming(
                            content: streamedContent,
                            reasoning: streamedReasoning
                        )
                        messageCreated = true
                        // Get index from delegate
                        if let idx = self.delegate?.streamingDidCreateMessage(message) {
                            messageIndex = idx
                            self.logger.logStreamingEvent(.messageCreated(index: idx))
                        }
                    } else if messageCreated, let idx = messageIndex {
                        // Schedule batched update instead of immediate update
                        let updated = MessageFactory.assistantStreaming(
                            content: streamedContent,
                            reasoning: streamedReasoning
                        )
                        self.scheduleMessageUpdate(at: idx, with: updated)
                    }
                }
            }
        )
        
        // Store final content
        state.setContent(result.content)
        state.setReasoning(result.reasoning)
        
        // Set the messageIndex on state if we created a message
        if let idx = messageIndex {
            state.setMessageIndex(idx)
        }
        
        // Clear reasoning streaming state
        delegate?.streamingDidUpdateReasoningState(isStreaming: false, latestChunk: nil)
        
        // Stop batching timer and flush any final update
        stopUpdateTimer()
        
        logger.logStreamingEvent(.completed)
        
        return StreamingResult(state: state)
    }
    
    // MARK: - Batching Helpers
    
    /// Schedule a message update to be batched
    private func scheduleMessageUpdate(at index: Int, with message: ChatMessage) {
        // Store the pending update (overwrites previous if exists)
        pendingUpdate = (index, message)
        
        // Create timer if not exists
        if updateTimer == nil {
            updateTimer = Timer.scheduledTimer(
                withTimeInterval: Self.updateInterval,
                repeats: true
            ) { [weak self] _ in
                self?.flushPendingUpdate()
            }
            RunLoop.main.add(updateTimer!, forMode: .common)
        }
    }
    
    /// Flush the pending update to the delegate
    private func flushPendingUpdate() {
        guard let update = pendingUpdate else { return }
        
        // Send batched update to delegate
        delegate?.streamingDidUpdateMessage(at: update.index, with: update.message)
        
        // Clear pending
        pendingUpdate = nil
    }
    
    /// Stop the update timer and flush any remaining update
    private func stopUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
        
        // Flush any final pending update
        flushPendingUpdate()
    }
    
    // MARK: - Private Helpers
    
    /// Extract tool name from token buffer using precompiled regex
    private func extractToolName(from buffer: String) -> String? {
        guard let regex = Self.toolRegex else { return nil }
        
        let range = NSRange(buffer.startIndex..., in: buffer)
        guard let match = regex.firstMatch(in: buffer, range: range),
              let toolNameRange = Range(match.range(at: 1), in: buffer) else {
            return nil
        }
        
        return String(buffer[toolNameRange])
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