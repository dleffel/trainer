import SwiftUI
import UIKit
import PhotosUI

// MARK: - Photo Attachment Button

/// A menu button that allows users to select photos from camera or library.
/// Supports both camera capture (if available) and photo library selection.
struct PhotoAttachmentButton: View {
    @Binding var selectedImages: [UIImage]
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    
    var body: some View {
        Menu {
            // Only show camera option if available (prevents crashes on simulator/devices without camera)
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    showCamera = true
                } label: {
                    Label("Take Photo", systemImage: "camera")
                }
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
    
    // MARK: - Private Helpers
    
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