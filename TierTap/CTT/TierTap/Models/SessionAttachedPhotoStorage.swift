import Foundation
#if os(iOS)
import UIKit
#endif

/// Local JPEG storage for user-attached session photos. Filenames are photo UUIDs only.
enum SessionAttachedPhotoStorage {
    private static let directoryName = "session_photos"

    #if os(iOS)
    @discardableResult
    static func saveImage(_ image: UIImage) -> UUID? {
        let photoID = UUID()
        guard let data = image.jpegData(compressionQuality: 0.9) else { return nil }
        return saveJPEGData(data, photoID: photoID) ? photoID : nil
    }
    #endif

    @discardableResult
    static func saveJPEGData(_ data: Data, photoID: UUID) -> Bool {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return false
        }
        let dir = documents.appendingPathComponent(directoryName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("\(photoID.uuidString).jpg")
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            print("Error saving session attached photo: \(error)")
            return false
        }
    }

    static func url(for photoID: UUID) -> URL? {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = documents.appendingPathComponent(directoryName, isDirectory: true)
        return dir.appendingPathComponent("\(photoID.uuidString).jpg")
    }

    static func deleteImage(photoID: UUID) {
        guard let url = url(for: photoID) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func deleteImages(photoIDs: [UUID]) {
        for id in photoIDs {
            deleteImage(photoID: id)
        }
    }
}
