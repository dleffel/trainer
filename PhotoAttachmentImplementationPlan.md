# Photo Attachment Implementation Plan

## Overview
Add the ability to attach photos to messages in the TrainerApp chat interface, supporting both camera capture and photo library selection. Images will be sent to the LLM along with text messages for vision-based analysis.

## Requirements
- ✅ Support photo library selection
- ✅ Support camera capture
- ✅ Display attached images in chat bubbles
- ✅ Send images to LLM API with vision support
- ✅ Persist images with conversation history
- ✅ Handle permissions properly

## Architecture Overview

### 1. Data Model Changes

#### 1.1 Update ChatMessage Model
**File**: `TrainerApp/TrainerApp/Services/ConversationPersistence.swift`

Add image attachment support to `ChatMessage`:

```swift
struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: Role
    let content: String
    let reasoning: String?
    let date: Date
    var state: MessageState
    let attachments: [MessageAttachment]?  // NEW: Optional array of attachments
    
    init(
        id: UUID = UUID(), 
        role: Role, 
        content: String, 
        reasoning: String? = nil, 
        date: Date = Date.current, 
        state: MessageState = .completed,
        attachments: [MessageAttachment]? = nil  // NEW
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.reasoning = reasoning
        self.date = date
        self.state = state
        self.attachments = attachments
    }
}

// NEW: Attachment type
struct MessageAttachment: Codable, Identifiable {
    let id: UUID
    let type: AttachmentType
    let data: Data  // Image data (JPEG compressed)
    let mimeType: String  // e.g., "image/jpeg"
    
    enum AttachmentType: String, Codable {
        case image
        // Future: video, document, etc.
    }
    
    init(id: UUID = UUID(), type: AttachmentType, data: Data, mimeType: String = "image/jpeg") {
        self.id = id
        self.type = type
        self.data = data
        self.mimeType = mimeType
    }
}
```

**Storage Consideration**: Images stored as compressed JPEG data within the message. This keeps everything together but may impact iCloud sync if images are large.

**Alternative Approach** (if needed later): Store image references and save actual files separately in Documents directory with UUID-based filenames.

#### 1.2 Update MessageFactory
**File**: `TrainerApp/TrainerApp/Services/MessageFactory.swift`

Add factory methods for creating messages with attachments:

```swift
enum MessageFactory {
    // ... existing methods ...
    
    /// Create a user message with photo attachments
    /// - Parameters:
    ///   - content: The user's message content
    ///   - images: Array of UIImages to attach
    /// - Returns: A ChatMessage from the user with compressed image attachments
    static func userWithImages(content: String, images: [UIImage]) -> ChatMessage {
        let attachments = images.compactMap { image -> MessageAttachment? in
            guard let jpegData = image.jpegData(compressionQuality: 0.8) else { return nil }
            return MessageAttachment(type: .image, data: jpegData)
        }
        
        return ChatMessage(
            role: .user, 
            content: content,
            attachments: attachments.isEmpty ? nil : attachments
        )
    }
}
```

### 2. UI Changes

#### 2.1 Photo Picker Component
**New File**: `TrainerApp/TrainerApp/Views/PhotoPickerView.swift`

Create a SwiftUI wrapper for PhotosPicker and Camera:

```swift
import SwiftUI
import PhotosUI

struct PhotoAttachmentButton: View {
    @Binding var selectedImages: [UIImage]
    @State private var showPhotoOptions = false
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var sourceType: UIImagePickerController.SourceType = .photoLibrary
    
    var body: some View {
        Menu {
            Button {
                sourceType = .camera
                showCamera = true
            } label: {
                Label("Take Photo", systemImage: "camera")
            }
            
            Button {
                sourceType = .photoLibrary
                showImagePicker = true
            } label: {
                Label("Choose from Library", systemImage: "photo.on.rectangle")
            }
        } label: {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 22))
                .foregroundColor(.blue)
        }
        .sheet(isPresented: $showImagePicker) {
            PhotosPicker(
                selection: $selectedPhotos,
                maxSelectionCount: 5,
                matching: .images
            ) {
                Text("Select Photos")
            }
        }
        .sheet(isPresented: $showCamera) {
            ImagePicker(
                sourceType: .camera,
                selectedImage: Binding(
                    get: { nil },
                    set: { if let image = $0 { selectedImages.append(image) } }
                )
            )
        }
    }
    
    @State private var selectedPhotos: [PhotosPickerItem] = []
    
    // Handle PhotosPickerItem to UIImage conversion
    private func loadSelectedPhotos() {
        Task {
            var images: [UIImage] = []
            for item in selectedPhotos {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    images.append(image)
                }
            }
            selectedImages.append(contentsOf: images)
            selectedPhotos = []
        }
    }
}

// Legacy UIImagePickerController wrapper for camera
struct ImagePicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) var dismiss
    var sourceType: UIImagePickerController.SourceType
    @Binding var selectedImage: UIImage?
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
```

#### 2.2 Update ChatTab Input Bar
**File**: `TrainerApp/TrainerApp/ContentView.swift`

Update the `ChatTab` struct to include photo attachment:

```swift
private struct ChatTab: View {
    // ... existing properties ...
    @State private var selectedImages: [UIImage] = []
    
    private var inputBar: some View {
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
                    Task { await send() }
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
    
    private var canSend: Bool {
        let hasText = !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasImages = !selectedImages.isEmpty
        return (hasText || hasImages) && conversationManager.conversationState == .idle
    }
    
    private func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = selectedImages
        
        // Must have either text or images
        guard !text.isEmpty || !images.isEmpty else { return }
        
        input = ""
        selectedImages = []
        
        do {
            try await conversationManager.sendMessage(text, images: images)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
```

#### 2.3 Update Bubble View for Images
**File**: `TrainerApp/TrainerApp/ContentView.swift`

Update the `Bubble` view to display image attachments:

```swift
private struct Bubble: View, Equatable {
    // ... existing properties ...
    let attachments: [MessageAttachment]?
    
    static func == (lhs: Bubble, rhs: Bubble) -> Bool {
        lhs.messageId == rhs.messageId &&
        lhs.text == rhs.text &&
        lhs.reasoning == rhs.reasoning &&
        lhs.isUser == rhs.isUser &&
        lhs.isLastMessage == rhs.isLastMessage &&
        lhs.attachments?.count == rhs.attachments?.count
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Show images if present
            if let attachments = attachments, !attachments.isEmpty {
                ForEach(attachments) { attachment in
                    if attachment.type == .image,
                       let image = UIImage(data: attachment.data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 250)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            
            // ... existing reasoning and text content ...
        }
        // ... rest of bubble styling ...
    }
}
```

Update bubble creation in `ChatTab`:

```swift
@ViewBuilder
private func bubble(for message: ChatMessage) -> some View {
    if message.role == .system {
        EmptyView()
    } else {
        let isLastMessage = messages.last?.id == message.id
        
        HStack {
            if message.role == .assistant {
                Bubble(
                    messageId: message.id,
                    text: message.content,
                    reasoning: message.reasoning,
                    isUser: false,
                    isLastMessage: isLastMessage,
                    conversationManager: conversationManager,
                    attachments: message.attachments  // NEW
                )
                .environmentObject(navigationState)
                Spacer(minLength: 40)
            } else {
                Spacer(minLength: 40)
                Bubble(
                    messageId: message.id,
                    text: message.content,
                    reasoning: nil,
                    isUser: true,
                    isLastMessage: isLastMessage,
                    conversationManager: conversationManager,
                    attachments: message.attachments  // NEW
                )
                .environmentObject(navigationState)
            }
        }
        .padding(.vertical, 2)
    }
}
```

### 3. LLM Service Integration

#### 3.1 Update LLM API Message Format
**File**: `TrainerApp/TrainerApp/Services/LLMService.swift`

Update the API message structure to support vision content:

```swift
// Update APIMessage to support vision format
private struct APIMessage: Codable {
    let role: String
    let content: Content
    
    enum Content: Codable {
        case text(String)
        case multipart([ContentPart])
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .text(let string):
                try container.encode(string)
            case .multipart(let parts):
                try container.encode(parts)
            }
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                self = .text(string)
            } else if let parts = try? container.decode([ContentPart].self) {
                self = .multipart(parts)
            } else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Content must be string or array"
                    )
                )
            }
        }
    }
    
    struct ContentPart: Codable {
        let type: String
        let text: String?
        let image_url: ImageURL?
        
        struct ImageURL: Codable {
            let url: String  // base64 data URL
        }
    }
}
```

#### 3.2 Update Message Conversion
**File**: `TrainerApp/TrainerApp/Services/LLMService.swift`

Update the `convertToAPIMessage` helper:

```swift
private func convertToAPIMessage(_ message: ChatMessage) -> APIMessage {
    let role: String = {
        switch message.role {
        case .user: return "user"
        case .assistant: return "assistant"
        case .system: return "system"
        }
    }()
    
    // If message has attachments, use multipart content
    if let attachments = message.attachments, !attachments.isEmpty {
        var parts: [APIMessage.ContentPart] = []
        
        // Add text content if present
        if !message.content.isEmpty {
            let timestamp = formatMessageTimestamp(message.date)
            let enhancedContent = message.role == .user || message.role == .assistant 
                ? "[\(timestamp)]\n\(message.content)"
                : message.content
            
            parts.append(APIMessage.ContentPart(
                type: "text",
                text: enhancedContent,
                image_url: nil
            ))
        }
        
        // Add image attachments
        for attachment in attachments where attachment.type == .image {
            let base64 = attachment.data.base64EncodedString()
            let dataUrl = "data:\(attachment.mimeType);base64,\(base64)"
            
            parts.append(APIMessage.ContentPart(
                type: "image_url",
                text: nil,
                image_url: APIMessage.ContentPart.ImageURL(url: dataUrl)
            ))
        }
        
        return APIMessage(role: role, content: .multipart(parts))
    } else {
        // Text-only message
        let timestamp = formatMessageTimestamp(message.date)
        let enhancedContent = message.role == .user || message.role == .assistant
            ? "[\(timestamp)]\n\(message.content)"
            : message.content
        
        return APIMessage(role: role, content: .text(enhancedContent))
    }
}
```

### 4. ConversationManager Updates

#### 4.1 Update sendMessage Method
**File**: `TrainerApp/TrainerApp/Services/ConversationManager.swift`

Add image parameter to sendMessage:

```swift
/// Send a message with optional images
func sendMessage(_ text: String, images: [UIImage] = []) async throws {
    guard config.hasValidApiKey else {
        throw ConfigurationError.missingApiKey
    }
    
    try await sendMessageWithConfig(
        text,
        images: images,
        apiKey: config.apiKey,
        model: config.model,
        systemPrompt: config.systemPrompt
    )
}

private func sendMessageWithConfig(
    _ text: String, 
    images: [UIImage],
    apiKey: String, 
    model: String, 
    systemPrompt: String
) async throws {
    // Create user message with images using MessageFactory
    let userMessage = images.isEmpty 
        ? MessageFactory.user(content: text)
        : MessageFactory.userWithImages(content: text, images: images)
    
    messages.append(userMessage)
    await persistMessages()
    
    // Start conversation flow
    updateState(.preparingResponse)
    
    try await handleConversationFlow(
        apiKey: apiKey,
        model: model,
        systemPrompt: systemPrompt
    )
}
```

### 5. Permissions & Configuration

#### 5.1 Update Info.plist
**File**: `TrainerApp/TrainerApp/Info.plist`

Add required permission descriptions:

```xml
<key>NSCameraUsageDescription</key>
<string>TrainerApp needs camera access to take photos for workout form analysis and progress tracking.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>TrainerApp needs photo library access to select images for workout analysis and progress tracking.</string>
```

### 6. Persistence Updates

#### 6.1 Update ConversationPersistence
**File**: `TrainerApp/TrainerApp/Services/ConversationPersistence.swift`

Ensure StoredMessage handles attachments:

```swift
private struct StoredMessage: Codable {
    let id: UUID
    let role: String
    let content: String
    let reasoning: String?
    let date: Date
    let state: String?
    let attachments: [MessageAttachment]?  // NEW
    
    init(
        id: UUID, 
        role: String, 
        content: String, 
        reasoning: String? = nil, 
        date: Date, 
        state: String? = nil,
        attachments: [MessageAttachment]? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.reasoning = reasoning
        self.date = date
        self.state = state
        self.attachments = attachments
    }
}
```

Update conversion methods to preserve attachments.

### 7. Storage Optimization (Optional Future Enhancement)

If image data causes issues with conversation persistence size:

**Alternative: Separate File Storage**
- Store images in `Documents/MessageAttachments/{messageId}_{attachmentId}.jpg`
- Store only file references in ChatMessage
- Implement cleanup for orphaned images
- Consider compression strategies

## Implementation Order

1. ✅ **Phase 1: Data Model** (Low Risk)
   - Update ChatMessage with attachments field
   - Update MessageFactory with image support
   - Update persistence to handle attachments
   - Test: Verify messages with attachments save/load correctly

2. ✅ **Phase 2: UI Components** (Medium Risk)
   - Create PhotoAttachmentButton component
   - Add image preview in input bar
   - Update Bubble to display images
   - Test: Verify UI shows/hides images correctly

3. ✅ **Phase 3: Permissions** (Low Risk)
   - Add Info.plist permission strings
   - Test: Verify permission prompts appear

4. ✅ **Phase 4: LLM Integration** (High Risk)
   - Update API message format for vision
   - Update message conversion logic
   - Test: Send message with image to API

5. ✅ **Phase 5: Integration** (Medium Risk)
   - Update ConversationManager.sendMessage
   - Wire up photo attachment button
   - End-to-end testing

## Testing Strategy

### Manual Testing
1. **Photo Library Selection**
   - Select 1 image → verify preview shows
   - Select multiple images → verify all show
   - Remove images from preview
   - Send message with images → verify appears in chat
   
2. **Camera Capture**
   - Take photo → verify preview shows
   - Send photo → verify appears in chat
   
3. **Persistence**
   - Send message with images
   - Close and reopen app
   - Verify images persist in conversation

4. **LLM Integration**
   - Send image with question about it
   - Verify LLM responds appropriately to image content

### Edge Cases
- Large images (>5MB) - ensure compression works
- Multiple images in one message
- Images only (no text)
- Permission denials
- Network failures during image upload

## Risks & Mitigations

### Risk: Large Images Impact Performance
**Mitigation**: Compress images to 0.8 JPEG quality, limit max dimension to 2048px

### Risk: iCloud Sync Size Limits
**Mitigation**: Monitor conversation size, implement file-based storage if needed

### Risk: API Rate Limits with Vision
**Mitigation**: Same error handling as text messages

### Risk: Old Conversations Missing Attachments Field
**Mitigation**: Make attachments optional, provide migration path

## Future Enhancements
- Video attachment support
- Image editing (crop, rotate) before sending
- Image compression settings
- Separate file storage for large attachments
- Image captions/descriptions
- Multiple image selection limit settings