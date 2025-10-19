import SwiftUI

// MARK: - Message List View

/// Scrollable list of chat messages with auto-scroll functionality and status indicators.
/// Manages message rendering, scroll position, and chat state visualization.
struct MessageListView: View {
    let messages: [ChatMessage]
    let chatState: ChatState
    @ObservedObject var conversationManager: ConversationManager
    
    @EnvironmentObject var navigationState: NavigationState
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(Array(messages.enumerated()), id: \.element.id) { index, msg in
                    bubble(for: msg, at: index)
                        .id(msg.id)
                }
                
                // Use the unified status view from ChatStateComponents
                if chatState != .idle {
                    ChatStatusView(state: chatState)
                        .id("status-indicator")
                        .padding(.horizontal, 4)
                }
                
                // Add invisible spacer at bottom to ensure last message isn't cut off
                Color.clear
                    .frame(height: 20)
                    .id("bottom-spacer")
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
        .defaultScrollAnchor(.bottom)
        .scrollDismissesKeyboard(.interactively)
    }
    
    // MARK: - Private Helpers
    
    @ViewBuilder
    private func bubble(for message: ChatMessage, at index: Int) -> some View {
        // Don't show system messages in the UI
        if message.role == .system {
            EmptyView()
        } else {
            // Compute isLastMessage once here to avoid repeated array lookups in every Bubble
            let isLastMessage = messages.last?.id == message.id
            
            HStack {
                if message.role == .assistant {
                    MessageBubble(
                        messageId: message.id,
                        text: message.content,
                        reasoning: message.reasoning,
                        isUser: false,
                        isLastMessage: isLastMessage,
                        conversationManager: conversationManager,
                        attachments: message.attachments,
                        sendStatus: nil,  // Assistant messages don't have send status
                        messageIndex: index
                    )
                    .environmentObject(navigationState)
                    Spacer(minLength: 40)
                } else {
                    Spacer(minLength: 40)
                    MessageBubble(
                        messageId: message.id,
                        text: message.content,
                        reasoning: nil,
                        isUser: true,
                        isLastMessage: isLastMessage,
                        conversationManager: conversationManager,
                        attachments: message.attachments,
                        sendStatus: message.sendStatus,  // Pass user message send status
                        messageIndex: index
                    )
                    .environmentObject(navigationState)
                }
            }
            .padding(.vertical, 2)
        }
    }
}