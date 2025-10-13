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
struct ChatInputBar: View {
    @Binding var input: String
    @Binding var selectedImages: [UIImage]
    let chatState: ChatState
    let canSend: Bool
    let onSend: () async -> Void
    
    // Track photo IDs alongside images for stable removal
    @State private var photoWrappers: [IdentifiablePhoto] = []
    
    var body: some View {
        VStack(spacing: 0) {
            // Image preview row (if images selected)
            if !photoWrappers.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(photoWrappers) { photo in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: photo.image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 80, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                
                                // Remove button - remove by stable ID
                                Button {
                                    removePhoto(withId: photo.id)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.white)
                                        .background(Circle().fill(Color.black.opacity(0.6)))
                                }
                                .padding(4)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                .background(Color(.systemGray6))
            }
            
            // Input controls
            HStack(spacing: 10) {
                PhotoAttachmentButton(selectedImages: $selectedImages)
                
                TextField("Message…", text: $input, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .disabled(chatState != .idle)

                Button {
                    Task { await onSend() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(canSend ? Color.blue : Color.gray)
                }
                .disabled(!canSend)
            }
            .padding(.all, 10)
            .background(.ultraThinMaterial)
        }
        .onChange(of: selectedImages) { _, newImages in
            // Sync photoWrappers when selectedImages changes from external sources
            syncPhotoWrappers(with: newImages)
        }
        .onAppear {
            // Initialize photoWrappers on first appear
            syncPhotoWrappers(with: selectedImages)
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