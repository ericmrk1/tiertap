import Foundation
#if os(iOS)
import UIKit
#endif

enum SessionPhotoKind: String, Codable, Hashable {
    case chipTable
    case comp
    case attached
}

/// Stable reference to a photo that belongs to a session (chip/table, comp receipt, or user attachment).
struct SessionPhotoRef: Hashable, Codable, Identifiable {
    var kind: SessionPhotoKind
    var objectID: String

    var storageKey: String { "\(kind.rawValue):\(objectID)" }

    var id: String { storageKey }

    static func chipTable() -> SessionPhotoRef {
        SessionPhotoRef(kind: .chipTable, objectID: "chip")
    }

    static func comp(_ compEventID: UUID) -> SessionPhotoRef {
        SessionPhotoRef(kind: .comp, objectID: compEventID.uuidString)
    }

    static func attached(_ photoID: UUID) -> SessionPhotoRef {
        SessionPhotoRef(kind: .attached, objectID: photoID.uuidString)
    }

    static func parse(storageKey: String) -> SessionPhotoRef? {
        let parts = storageKey.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let kind = SessionPhotoKind(rawValue: parts[0]) else { return nil }
        return SessionPhotoRef(kind: kind, objectID: parts[1])
    }
}

enum SessionPhotoCatalog {
    struct Item: Identifiable, Hashable {
        let ref: SessionPhotoRef
        let title: String
        let subtitle: String?

        var id: String { ref.storageKey }
    }

    static func items(for session: Session) -> [Item] {
        var out: [Item] = []

        if let fileName = session.chipEstimatorImageFilename,
           let url = ChipEstimatorPhotoStorage.url(for: fileName),
           FileManager.default.fileExists(atPath: url.path) {
            out.append(Item(ref: .chipTable(), title: "Chip / table", subtitle: nil))
        }

        for ev in session.compEvents {
            guard let url = CompPhotoStorage.url(for: ev.id),
                  FileManager.default.fileExists(atPath: url.path) else { continue }
            let subtitle = "\(ev.kind.title) · \(ev.timestamp.formatted(date: .omitted, time: .shortened))"
            out.append(Item(ref: .comp(ev.id), title: "Comp receipt", subtitle: subtitle))
        }

        for photoID in session.sessionAttachedPhotoIDs {
            guard let url = SessionAttachedPhotoStorage.url(for: photoID),
                  FileManager.default.fileExists(atPath: url.path) else { continue }
            out.append(Item(ref: .attached(photoID), title: "Session photo", subtitle: nil))
        }

        return out
    }

    static func hasPhotos(for session: Session) -> Bool {
        !items(for: session).isEmpty
    }

    struct FeedEntry: Identifiable, Hashable {
        let sessionID: UUID
        let sessionTitle: String
        let sessionDate: Date
        let ref: SessionPhotoRef

        var id: String { "\(sessionID.uuidString)-\(ref.storageKey)" }
    }

    static func feedEntries(from sessions: [Session]) -> [FeedEntry] {
        let orderedSessions = sessions.sorted { lhs, rhs in
            let lhsDate = lhs.endTime ?? lhs.startTime
            let rhsDate = rhs.endTime ?? rhs.startTime
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            return lhs.startTime > rhs.startTime
        }

        var entries: [FeedEntry] = []
        for session in orderedSessions {
            let sessionTitle = feedTitle(for: session)
            let sessionDate = session.endTime ?? session.startTime
            for item in items(for: session) {
                entries.append(
                    FeedEntry(
                        sessionID: session.id,
                        sessionTitle: sessionTitle,
                        sessionDate: sessionDate,
                        ref: item.ref
                    )
                )
            }
        }
        return entries
    }

    static func feedTitle(for session: Session) -> String {
        let casino = session.casino.trimmingCharacters(in: .whitespacesAndNewlines)
        let game = session.game.trimmingCharacters(in: .whitespacesAndNewlines)
        if !casino.isEmpty, !game.isEmpty { return "\(casino) · \(game)" }
        if !casino.isEmpty { return casino }
        if !game.isEmpty { return game }
        return "Session"
    }

    static func photoURL(for ref: SessionPhotoRef, session: Session) -> URL? {
        switch ref.kind {
        case .chipTable:
            guard let fileName = session.chipEstimatorImageFilename else { return nil }
            return ChipEstimatorPhotoStorage.url(for: fileName)
        case .comp:
            guard let uuid = UUID(uuidString: ref.objectID) else { return nil }
            return CompPhotoStorage.url(for: uuid)
        case .attached:
            guard let uuid = UUID(uuidString: ref.objectID) else { return nil }
            return SessionAttachedPhotoStorage.url(for: uuid)
        }
    }

    static func resolvedPrimaryRef(for session: Session) -> SessionPhotoRef? {
        if let key = session.primarySessionPhotoRefKey,
           let ref = SessionPhotoRef.parse(storageKey: key),
           items(for: session).contains(where: { $0.ref == ref }) {
            return ref
        }
        return items(for: session).first?.ref
    }

    #if os(iOS)
    static func image(for ref: SessionPhotoRef, session: Session) -> UIImage? {
        switch ref.kind {
        case .chipTable:
            guard let fileName = session.chipEstimatorImageFilename,
                  let url = ChipEstimatorPhotoStorage.url(for: fileName) else { return nil }
            return UIImage(contentsOfFile: url.path)
        case .comp:
            guard let uuid = UUID(uuidString: ref.objectID),
                  let url = CompPhotoStorage.url(for: uuid) else { return nil }
            return UIImage(contentsOfFile: url.path)
        case .attached:
            guard let uuid = UUID(uuidString: ref.objectID),
                  let url = SessionAttachedPhotoStorage.url(for: uuid) else { return nil }
            return UIImage(contentsOfFile: url.path)
        }
    }
    #endif
}
