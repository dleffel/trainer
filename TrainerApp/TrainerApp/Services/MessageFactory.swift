import Foundation
import UIKit

/// Factory for creating ChatMessage instances with consistent patterns
///
/// This factory ensures all messages are created with proper parameters,
/// preventing bugs like missing reasoning fields. It provides type-safe
/// construction methods for different message types and scenarios.
enum MessageFactory {
    // MARK: - Assistant Messages
    
    /// Create an assistant message with content and optional reasoning
    /// - Parameters:
    ///   - content: The message content
    ///   - reasoning: Optional reasoning tokens from reasoning models
    ///   - state: The message state (defaults to completed)
    /// - Returns: A ChatMessage from the assistant
    static func assistant(
        content: String,
        reasoning: String? = nil,
        state: MessageState = .completed
    ) -> ChatMessage {
        ChatMessage(
            role: .assistant,
            content: content,
            reasoning: reasoning,
            state: state
        )
    }
    
    /// Create a streaming assistant message
    /// - Parameters:
    ///   - content: The current content being streamed
    ///   - reasoning: Optional reasoning being streamed
    /// - Returns: A ChatMessage in streaming state
    static func assistantStreaming(
        content: String,
        reasoning: String? = nil
    ) -> ChatMessage {
        ChatMessage(
            role: .assistant,
            content: content,
            reasoning: reasoning,
            state: .streaming
        )
    }
    
    /// Create an assistant message from AssistantResponseState
    /// - Parameters:
    ///   - state: The response state to convert
    ///   - messageState: The desired message state (defaults to completed)
    /// - Returns: A ChatMessage with all data from the response state
    static func from(
        _ state: AssistantResponseState,
        messageState: MessageState = .completed
    ) -> ChatMessage {
        state.toMessage(state: messageState)
    }
    
    // MARK: - System Messages
    
    /// Create a system message
    /// - Parameter content: The system message content
    /// - Returns: A ChatMessage from the system
    static func system(content: String) -> ChatMessage {
        ChatMessage(role: .system, content: content)
    }
    
    // MARK: - User Messages
    
    /// Create a user message
    /// - Parameter content: The user's message content
    /// - Returns: A ChatMessage from the user
    static func user(content: String) -> ChatMessage {
        ChatMessage(role: .user, content: content)
    }
    
    /// Create a user message with photo attachments
    /// - Parameters:
    ///   - content: The user's message content
    ///   - images: Array of UIImages to attach (will be compressed to JPEG)
    /// - Returns: A ChatMessage from the user with compressed image attachments
    static func userWithImages(content: String, images: [UIImage]) -> ChatMessage {
        let attachments = images.compactMap { image -> MessageAttachment? in
            // Compress image to JPEG with 0.8 quality
            guard let jpegData = image.jpegData(compressionQuality: 0.8) else { return nil }
            return MessageAttachment(type: .image, data: jpegData)
        }
        
        return ChatMessage(
            role: .user,
            content: content,
            attachments: attachments.isEmpty ? nil : attachments
        )
    }
    
    // MARK: - Message Updates
    
    /// Update an existing message preserving its identity
    /// - Parameters:
    ///   - message: The message to update
    ///   - content: New content (nil to keep existing)
    ///   - reasoning: New reasoning (nil to keep existing)
    ///   - state: New state (nil to keep existing)
    /// - Returns: A new ChatMessage with updated fields
    static func updated(
        _ message: ChatMessage,
        content: String? = nil,
        reasoning: String? = nil,
        state: MessageState? = nil
    ) -> ChatMessage {
        ChatMessage(
            id: message.id,
            role: message.role,
            content: content ?? message.content,
            reasoning: reasoning ?? message.reasoning,
            date: message.date,
            state: state ?? message.state
        )
    }
    
    /// Update message content only, preserving everything else including reasoning
    /// - Parameters:
    ///   - message: The message to update
    ///   - content: The new content
    /// - Returns: A new ChatMessage with updated content
    static func withContent(
        _ message: ChatMessage,
        _ content: String
    ) -> ChatMessage {
        ChatMessage(
            id: message.id,
            role: message.role,
            content: content,
            reasoning: message.reasoning,
            date: message.date,
            state: message.state
        )
    }
    
    /// Mark a message as completed
    /// - Parameter message: The message to mark complete
    /// - Returns: A new ChatMessage in completed state
    static func completed(_ message: ChatMessage) -> ChatMessage {
        ChatMessage(
            id: message.id,
            role: message.role,
            content: message.content,
            reasoning: message.reasoning,
            date: message.date,
            state: .completed
        )
    }
}