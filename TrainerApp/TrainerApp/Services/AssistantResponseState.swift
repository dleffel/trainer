import Foundation

/// Encapsulates the complete state of an assistant's response
/// 
/// This struct serves as the single source of truth for all data related to an assistant's response,
/// preventing state fragmentation and ensuring reasoning is never lost.
struct AssistantResponseState {
    // MARK: - Properties
    
    /// The accumulated content of the response
    private(set) var content: String = ""
    
    /// The accumulated reasoning tokens (optional for non-reasoning models)
    private(set) var reasoning: String? = nil
    
    /// Index in the messages array where this response lives (if created)
    private(set) var messageIndex: Int? = nil
    
    /// Whether the response is complete
    private(set) var isComplete: Bool = false
    
    // MARK: - State Mutations
    
    /// Append a chunk of content to the response
    mutating func appendContent(_ chunk: String) {
        content += chunk
    }
    
    /// Append a chunk of reasoning to the response
    mutating func appendReasoning(_ chunk: String) {
        if reasoning == nil {
            reasoning = chunk
        } else {
            reasoning! += chunk
        }
    }
    
    /// Set the content directly (used for non-streaming responses)
    mutating func setContent(_ newContent: String) {
        content = newContent
    }
    
    /// Set the reasoning directly (used for non-streaming responses)
    mutating func setReasoning(_ newReasoning: String?) {
        reasoning = newReasoning
    }
    
    /// Set the index of the message in the messages array
    mutating func setMessageIndex(_ index: Int) {
        messageIndex = index
    }
    
    /// Mark the response as complete
    mutating func markComplete() {
        isComplete = true
    }
    
    // MARK: - Conversions
    
    /// Convert to ChatMessage for UI/persistence
    /// - Parameters:
    ///   - id: UUID for the message (generates new if not provided)
    ///   - date: Date of the message (defaults to current date)
    ///   - state: MessageState (defaults to completed)
    /// - Returns: A ChatMessage with all accumulated state
    func toMessage(
        id: UUID = UUID(),
        date: Date = Date.current,
        state: MessageState = .completed
    ) -> ChatMessage {
        ChatMessage(
            id: id,
            role: .assistant,
            content: content,
            reasoning: reasoning,
            date: date,
            state: state
        )
    }
    
    /// Create message for streaming (uses existing ID if available)
    /// - Parameter existingId: Optional existing UUID to preserve message identity
    /// - Returns: A ChatMessage in streaming state
    func toStreamingMessage(existingId: UUID? = nil) -> ChatMessage {
        ChatMessage(
            id: existingId ?? UUID(),
            role: .assistant,
            content: content,
            reasoning: reasoning,
            state: .streaming
        )
    }
    
    /// Check if the response has any content
    var hasContent: Bool {
        !content.isEmpty
    }
    
    /// Check if the response has reasoning
    var hasReasoning: Bool {
        reasoning != nil && !reasoning!.isEmpty
    }
}