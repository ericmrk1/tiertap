import Foundation
import UIKit

final class TripStore: ObservableObject {
    @Published private(set) var trips: [Trip] = []

    private let defaultsKey = "ctt_trips_v1"
    private var defaults: UserDefaults {
        UserDefaults(suiteName: "group.com.app.tiertap") ?? .standard
    }

    private var mediaRoot: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("trip_media", isDirectory: true)
    }

    init() {
        load()
    }

    func trips(forSessionID sessionID: UUID) -> [Trip] {
        trips.filter { $0.sessionIDs.contains(sessionID) }
    }

    func add(_ trip: Trip) {
        var t = trip
        t.updatedAt = Date()
        trips.insert(t, at: 0)
        normalizeSort()
        save()
    }

    func update(_ trip: Trip) {
        guard let idx = trips.firstIndex(where: { $0.id == trip.id }) else { return }
        var t = trip
        t.updatedAt = Date()
        trips[idx] = t
        normalizeSort()
        save()
    }

    /// Appends completed-session IDs that are not already on the trip (stable order, new IDs at the end).
    func linkSessionIDs(_ newIDs: [UUID], to tripId: UUID) {
        guard let idx = trips.firstIndex(where: { $0.id == tripId }) else { return }
        var t = trips[idx]
        var seen = Set(t.sessionIDs)
        for id in newIDs where !seen.contains(id) {
            t.sessionIDs.append(id)
            seen.insert(id)
        }
        update(t)
    }

    func delete(_ trip: Trip) {
        trips.removeAll { $0.id == trip.id }
        removeAllPhotos(for: trip.id)
        save()
    }

    func replaceAll(with newTrips: [Trip]) {
        trips = newTrips
        normalizeSort()
        save()
    }

    // MARK: - Photos

    func directoryURL(forTripId id: UUID) -> URL {
        mediaRoot.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    @discardableResult
    func addPhoto(_ image: UIImage, to tripId: UUID, jpegQuality: CGFloat = 0.82) -> String? {
        guard let idx = trips.firstIndex(where: { $0.id == tripId }) else { return nil }
        guard let data = image.jpegData(compressionQuality: jpegQuality) else { return nil }

        let folder = directoryURL(forTripId: tripId)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let fileName = "\(UUID().uuidString).jpg"
        let fileURL = folder.appendingPathComponent(fileName)
        do {
            try data.write(to: fileURL, options: .atomic)
            trips[idx].photoFilenames.append(fileName)
            trips[idx].updatedAt = Date()
            normalizeSort()
            save()
            return fileName
        } catch {
            return nil
        }
    }

    func loadPhoto(tripId: UUID, filename: String) -> UIImage? {
        let url = directoryURL(forTripId: tripId).appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    func removePhoto(tripId: UUID, filename: String) {
        guard let idx = trips.firstIndex(where: { $0.id == tripId }) else { return }
        let url = directoryURL(forTripId: tripId).appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
        trips[idx].photoFilenames.removeAll { $0 == filename }
        trips[idx].updatedAt = Date()
        normalizeSort()
        save()
    }

    private func removeAllPhotos(for tripId: UUID) {
        let folder = directoryURL(forTripId: tripId)
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: - Persistence

    private func normalizeSort() {
        trips.sort { a, b in
            if a.endDate != b.endDate {
                return a.endDate > b.endDate
            }
            return a.startDate > b.startDate
        }
    }

    private func load() {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([Trip].self, from: data) else {
            trips = []
            return
        }
        trips = decoded
        normalizeSort()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(trips) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}
