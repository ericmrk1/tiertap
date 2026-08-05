import Foundation
import UIKit

enum ChipEstimatorPhotoStorage {
    private static let directoryName = "chip_photos"

    /// Save or replace the chip estimator image for the given session.
    /// Returns the filename that should be stored on the `Session`.
    static func saveImage(_ image: UIImage, for sessionID: UUID) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.9) else { return nil }
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = documents.appendingPathComponent(directoryName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            // Deterministic filename per session so edits replace the prior photo.
            let fileName = "\(sessionID.uuidString).jpg"
            let url = dir.appendingPathComponent(fileName)
            try data.write(to: url, options: .atomic)
            return fileName
        } catch {
            print("Error saving chip estimator image: \(error)")
            return nil
        }
    }

    /// Resolve a previously saved filename into a file URL.
    static func url(for fileName: String) -> URL? {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = documents.appendingPathComponent(directoryName, isDirectory: true)
        return dir.appendingPathComponent(fileName)
    }
}

