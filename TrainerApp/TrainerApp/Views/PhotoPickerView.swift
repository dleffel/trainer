import SwiftUI
import PhotosUI

// MARK: - Photo Attachment Button

struct PhotoAttachmentButton: View {
    @Binding var selectedImages: [UIImage]
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    
    var body: some View {
        Menu {
            Button {
                showCamera = true
            } label: {
                Label("Take Photo", systemImage: "camera")
            }
            
            Button {
                showPhotoPicker = true
            } label: {
                Label("Choose from Library", systemImage: "photo.on.rectangle")
            }
        } label: {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 22))
                .foregroundColor(.blue)
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $selectedPhotoItems,
            maxSelectionCount: 5,
            matching: .images
        )
        .onChange(of: selectedPhotoItems) { _, newItems in
            Task {
                await loadSelectedPhotos(from: newItems)
            }
        }
        .sheet(isPresented: $showCamera) {
            ImagePicker(
                sourceType: .camera,
                onImageSelected: { image in
                    selectedImages.append(image)
                }
            )
        }
    }
    
    @MainActor
    private func loadSelectedPhotos(from items: [PhotosPickerItem]) async {
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                selectedImages.append(image)
            }
        }
        selectedPhotoItems = []
    }
}

// MARK: - Image Picker (Camera Wrapper)

struct ImagePicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) var dismiss
    var sourceType: UIImagePickerController.SourceType
    var onImageSelected: (UIImage) -> Void
    
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
                parent.onImageSelected(image)
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}