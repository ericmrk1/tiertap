import Foundation
#if os(iOS)
import UIKit
#endif

/// Local JPEG storage for comp receipt photos. Files are named by `CompEvent.id` only — no path or
/// filename is stored on `Session` or `CompEvent`, so nothing syncs in session JSON or community payloads.
enum CompPhotoStorage {
    private static let directoryName = "comp_photos"

    @discardableResult
    static func saveJPEGData(_ data: Data, compEventID: UUID) -> Bool {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return false
        }
        let dir = documents.appendingPathComponent(directoryName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("\(compEventID.uuidString).jpg")
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            print("Error saving comp photo: \(error)")
            return false
        }
    }

    #if os(iOS)
    @discardableResult
    static func saveImage(_ image: UIImage, compEventID: UUID) -> Bool {
        guard let data = image.jpegData(compressionQuality: 0.9) else { return false }
        return saveJPEGData(data, compEventID: compEventID)
    }
    #endif

    static func url(for compEventID: UUID) -> URL? {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = documents.appendingPathComponent(directoryName, isDirectory: true)
        return dir.appendingPathComponent("\(compEventID.uuidString).jpg")
    }

    static func deleteImage(compEventID: UUID) {
        guard let url = url(for: compEventID) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func deleteImages(for compEvents: [CompEvent]) {
        for ev in compEvents {
            deleteImage(compEventID: ev.id)
        }
    }
}
