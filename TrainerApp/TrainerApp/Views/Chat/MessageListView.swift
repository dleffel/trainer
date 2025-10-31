import SwiftUI

// MARK: - Message List View

/// Scrollable list of chat messages with auto-scroll functionality and status indicators.
/// Manages message rendering, scroll position, and chat state visualization.
struct MessageListView: View {
    let messages: [ChatMessage]
    let chatState: ChatState
    let canLoadMore: Bool
    let totalMessageCount: Int
    let onLoadMore: () -> Void
    @ObservedObject var conversationManager: ConversationManager
    
    @EnvironmentObject var navigationState: NavigationState
    @State private var isLoadingMore = false
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                // Load More button at the top
                if canLoadMore {
                    HStack {
                        Spacer()
                        LoadMoreButton(
                            availableCount: totalMessageCount - messages.count,
                            isLoading: isLoadingMore,
                            action: loadMore
                        )
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                
                ForEach(Array(messages.enumerated()), id: \.element.id) { index, msg in
                    bubble(for: msg, at: index)
                        .id(msg.id)
                }
                
                // Use the unified status view from ChatStateComponents
                if chatState != .idle {
                    ChatStatusView(state: chatState)
                        .padding(.horizontal, 4)
                }
                
                // Add invisible spacer at bottom to ensure last message isn't cut off
                Color.clear
                    .frame(height: 20)
                    .id("bottom-anchor")
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 8)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: navigationState.scrollToBottomTrigger) { _, _ in
                withAnimation {
                    proxy.scrollTo("bottom-anchor", anchor: .bottom)
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func loadMore() {
        guard !isLoadingMore else { return }
        
        isLoadingMore = true
        
        // Small delay for smooth animation
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            onLoadMore()
            isLoadingMore = false
        }
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
                    // Calculate global index for user messages (needed for retry functionality)
                    // Formula: globalIndex = (totalMessageCount - displayMessages.count) + displayIndex
                    let globalIndex = (totalMessageCount - messages.count) + index
                    MessageBubble(
                        messageId: message.id,
                        text: message.content,
                        reasoning: nil,
                        isUser: true,
                        isLastMessage: isLastMessage,
                        conversationManager: conversationManager,
                        attachments: message.attachments,
                        sendStatus: message.sendStatus,  // Pass user message send status
                        messageIndex: globalIndex
                    )
                    .environmentObject(navigationState)
                }
            }
            .padding(.vertical, 2)
        }
    }
}