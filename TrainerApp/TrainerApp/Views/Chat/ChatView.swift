import SwiftUI

// MARK: - Chat View

/// Complete chat interface that assembles message list and input bar components.
/// Manages the chat navigation stack, toolbar, and error handling.
struct ChatView: View {
    @ObservedObject var conversationManager: ConversationManager
    @Binding var showSettings: Bool
    let iCloudAvailable: Bool
    
    @EnvironmentObject var navigationState: NavigationState
    @State private var input: String = ""
    @State private var errorMessage: String?
    @State private var selectedImages: [UIImage] = []
    
    // MARK: - Computed Properties
    
    private var messages: [ChatMessage] {
        conversationManager.messages
    }
    
    private var chatState: ChatState {
        conversationManager.conversationState.chatState
    }
    
    private var canSend: Bool {
        let hasText = !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasImages = !selectedImages.isEmpty
        return (hasText || hasImages) && conversationManager.conversationState == .idle
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                MessageListView(
                    messages: messages,
                    chatState: chatState,
                    conversationManager: conversationManager
                )
                
                ChatInputBar(
                    input: $input,
                    selectedImages: $selectedImages,
                    chatState: chatState,
                    canSend: canSend,
                    onSend: send
                )
            }
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if iCloudAvailable {
                        Image(systemName: "icloud.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    } else {
                        Image(systemName: "icloud.slash")
                            .foregroundColor(.orange)
                            .font(.caption)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.body)
                    }
                    .accessibilityLabel("Settings")
                }
            }
        }
        .alert("Error", isPresented: .constant(errorMessage != nil), actions: {
            Button("OK") { errorMessage = nil }
        }, message: {
            Text(errorMessage ?? "")
        })
    }
    
    // MARK: - Actions
    
    private func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = selectedImages
        
        // Must have either text or images
        guard !text.isEmpty || !images.isEmpty else { return }
        
        // Clear input text immediately for better UX
        input = ""
        
        do {
            try await conversationManager.sendMessage(text, images: images)
            // Only clear images on successful send to prevent data loss
            selectedImages = []
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            // Images remain in selectedImages for retry on failure
        }
    }
}