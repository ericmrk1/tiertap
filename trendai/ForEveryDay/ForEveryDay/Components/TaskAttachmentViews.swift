import PhotosUI
import SwiftUI
import UIKit

// MARK: - Image compression

extension UIImage {
    /// Downscales and JPEG-encodes for storing on `HabitTask` (keeps JSON reasonably small).
    func preparedTaskAttachmentJPEG(maxDimension: CGFloat = 960, quality: CGFloat = 0.82) -> Data? {
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension, maxSide > 0 else {
            return jpegData(compressionQuality: quality)
        }
        let scale = maxDimension / maxSide
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let scaled = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
        return scaled.jpegData(compressionQuality: quality)
    }
}

// MARK: - List / row leading attachment

struct TaskLeadingAttachmentView: View {
    let task: HabitTask
    var onImageTap: () -> Void

    var body: some View {
        if let data = task.attachmentImageData, let ui = UIImage(data: data) {
            Button(action: onImageTap) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View photo full screen")
        } else if let sym = task.resolvedSystemSymbolName {
            Image(systemName: sym)
                .font(.system(size: 22))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
        } else if let emoji = task.iconEmoji, !emoji.isEmpty {
            Text(emoji)
                .font(.system(size: 26))
                .frame(width: 44, height: 44)
                .multilineTextAlignment(.center)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Full screen image

struct TaskAttachmentFullScreenView: View {
    let image: UIImage
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        HapticButton.lightImpact()
                        dismiss()
                    }
                    .tint(.white)
                }
            }
        }
    }
}

struct FullScreenTaskImageItem: Identifiable {
    let id: UUID
    let image: UIImage
    let title: String
}

enum TaskAttachmentEditorSupport {
    static func loadPhotoData(from item: PhotosPickerItem?) async -> Data? {
        guard let item else { return nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        guard let ui = UIImage(data: data) else { return nil }
        return ui.preparedTaskAttachmentJPEG()
    }
}
