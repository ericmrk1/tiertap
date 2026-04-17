// Intentionally left blank; file added in error.
import SwiftUI
import UIKit

struct ProfilePhotoCaptureView: UIViewControllerRepresentable {
    @Environment(\.presentationMode) private var presentationMode
    @Binding var image: UIImage?
    var preferredSourceType: UIImagePickerController.SourceType = .camera
    /// Called on the main thread after `image` is set and before the picker dismisses (e.g. to chain another sheet).
    var onFinishedPicking: ((UIImage) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        if UIImagePickerController.isSourceTypeAvailable(preferredSourceType) {
            picker.sourceType = preferredSourceType
        } else {
            picker.sourceType = .photoLibrary
        }
        picker.delegate = context.coordinator
        picker.allowsEditing = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ProfilePhotoCaptureView

        init(parent: ProfilePhotoCaptureView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            let key: UIImagePickerController.InfoKey = info[.editedImage] != nil ? .editedImage : .originalImage
            if let pickedImage = info[key] as? UIImage {
                parent.image = pickedImage
                parent.onFinishedPicking?(pickedImage)
            }
            parent.presentationMode.wrappedValue.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

