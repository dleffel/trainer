import SwiftUI
import UIKit

// MARK: - Identifiable Photo Wrapper

/// Wrapper to provide stable identity for UIImage in SwiftUI lists
struct IdentifiablePhoto: Identifiable {
    let id = UUID()
    let image: UIImage
}

// MARK: - Chat Input Bar

/// Input bar for the chat interface with text field, photo attachments, and send button.
/// Handles multi-line text input, photo preview thumbnails, and send state management.
/// Modernized with iOS 16+ patterns: focus state, haptic feedback, and smooth animations.
struct ChatInputBar: View {
    @Binding var input: String
    @Binding var selectedImages: [UIImage]
    let chatState: ChatState
    let canSend: Bool
    let onSend: () async -> Void
    
    // Track photo IDs alongside images for stable removal
    @State private var photoWrappers: [IdentifiablePhoto] = []
    
    // Focus state for keyboard management
    @FocusState private var isInputFocused: Bool
    
    // Track if view has appeared to prevent initial animation
    @State private var hasAppeared = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Image preview row (if images selected) with smooth transitions
            if !photoWrappers.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(photoWrappers) { photo in
                            photoThumbnail(for: photo)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .background(Color(.systemGray6))
                .animation(hasAppeared ? .spring(response: 0.3, dampingFraction: 0.7) : nil, value: photoWrappers.count)
            }
            
            // Input controls with modern styling
            HStack(spacing: 12) {
                PhotoAttachmentButton(selectedImages: $selectedImages)
                    .accessibilityLabel("Attach photo")
                
                TextField("Message…", text: $input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(.quaternarySystemFill))
                    )
                    .lineLimit(1...5)
                    .disabled(chatState != .idle)
                    .focused($isInputFocused)
                    .accessibilityLabel("Message input")
                    .accessibilityHint("Type your message to send")

                sendButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial)
        }
        .onChange(of: selectedImages) { _, newImages in
            // Sync photoWrappers when selectedImages changes from external sources
            syncPhotoWrappers(with: newImages)
        }
        .onAppear {
            // Initialize photoWrappers on first appear
            syncPhotoWrappers(with: selectedImages)
            // Set appeared flag after sync to prevent initial animation
            hasAppeared = true
        }
    }
    
    // MARK: - View Components
    
    /// Modern send button with haptic feedback and smooth animations
    private var sendButton: some View {
        Button {
            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            
            Task { await onSend() }
        } label: {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(canSend ? Color.blue : Color(.quaternaryLabel))
        }
        .scaleEffect(canSend ? 1.0 : 0.85)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: canSend)
        .disabled(!canSend)
        .buttonStyle(.borderless)
        .accessibilityLabel(canSend ? "Send message" : "Send disabled")
        .accessibilityHint(canSend ? "Tap to send your message" : "Type a message to enable sending")
    }
    
    /// Photo thumbnail with modern styling and haptic feedback on removal
    private func photoThumbnail(for photo: IdentifiablePhoto) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: photo.image)
                .resizable()
                .scaledToFill()
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color(.separator).opacity(0.3), lineWidth: 0.5)
                )
            
            // Remove button with haptic feedback
            Button {
                // Haptic feedback
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    removePhoto(withId: photo.id)
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
                    .background(
                        Circle()
                            .fill(Color.black.opacity(0.6))
                            .padding(-4)
                    )
            }
            .buttonStyle(.borderless)
            .padding(6)
            .accessibilityLabel("Remove photo")
        }
    }
    
    // MARK: - Private Helpers
    
    private func removePhoto(withId id: UUID) {
        guard let index = photoWrappers.firstIndex(where: { $0.id == id }) else { return }
        photoWrappers.remove(at: index)
        selectedImages.remove(at: index)
    }
    
    private func syncPhotoWrappers(with images: [UIImage]) {
        // Only rebuild if count changed (avoids unnecessary recreation)
        guard images.count != photoWrappers.count else { return }
        photoWrappers = images.map { IdentifiablePhoto(image: $0) }
    }
}