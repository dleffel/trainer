import SwiftUI
import UIKit

// MARK: - Chat Input Bar

/// Input bar for the chat interface with text field, photo attachments, and send button.
/// Handles multi-line text input, photo preview thumbnails, and send state management.
struct ChatInputBar: View {
    @Binding var input: String
    @Binding var selectedImages: [UIImage]
    let chatState: ChatState
    let canSend: Bool
    let onSend: () async -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Image preview row (if images selected)
            if !selectedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 80, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                
                                // Remove button
                                Button {
                                    selectedImages.remove(at: index)
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
    }
}