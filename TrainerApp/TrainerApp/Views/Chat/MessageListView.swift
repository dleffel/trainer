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
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(messages) { msg in
                        bubble(for: msg)
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
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _, _ in
                scrollToBottom(proxy: proxy, animated: true)
            }
            .onChange(of: chatState) { _, newValue in
                // Only scroll when transitioning to non-idle state
                if newValue != .idle {
                    scrollToBottom(proxy: proxy, animated: true)
                }
            }
            .onAppear {
                // Scroll to bottom when view appears (delayed for layout)
                if messages.count > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        scrollToBottom(proxy: proxy, animated: true)
                    }
                }
            }
        }
    }
    
    // MARK: - Private Helpers
    
    @ViewBuilder
    private func bubble(for message: ChatMessage) -> some View {
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
                        attachments: message.attachments
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
                        attachments: message.attachments
                    )
                    .environmentObject(navigationState)
                }
            }
            .padding(.vertical, 2)
        }
    }
    
    /// Centralized scroll-to-bottom logic
    /// - Parameters:
    ///   - proxy: The ScrollViewProxy for controlling scroll position
    ///   - animated: Whether to animate the scroll
    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        let scrollAction = {
            if chatState != .idle {
                // When processing, scroll to show status indicator
                proxy.scrollTo("status-indicator", anchor: .bottom)
            } else {
                // When idle, scroll to bottom spacer to ensure last message is fully visible
                proxy.scrollTo("bottom-spacer", anchor: .bottom)
            }
        }
        
        if animated {
            withAnimation(.easeOut(duration: 0.25)) {
                scrollAction()
            }
        } else {
            scrollAction()
        }
    }
}