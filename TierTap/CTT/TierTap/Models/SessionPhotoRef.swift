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
        let contextTags: [SessionPhotoContextTag]
        let customContextLabels: [String]

        var id: String { ref.storageKey }
    }

    struct ContextFilterOption: Identifiable, Hashable {
        let id: String
        let label: String
    }

    static func items(for session: Session) -> [Item] {
        var out: [Item] = []

        if let fileName = session.chipEstimatorImageFilename,
           let url = ChipEstimatorPhotoStorage.url(for: fileName),
           FileManager.default.fileExists(atPath: url.path) {
            let ref = SessionPhotoRef.chipTable()
            out.append(Item(
                ref: ref,
                title: "Chip / table",
                subtitle: nil,
                contextTags: session.contextTags(for: ref),
                customContextLabels: session.customContextLabels(for: ref)
            ))
        }

        for ev in session.compEvents {
            guard let url = CompPhotoStorage.url(for: ev.id),
                  FileManager.default.fileExists(atPath: url.path) else { continue }
            let subtitle = "\(ev.kind.title) · \(ev.timestamp.formatted(date: .omitted, time: .shortened))"
            let ref = SessionPhotoRef.comp(ev.id)
            out.append(Item(
                ref: ref,
                title: "Comp receipt",
                subtitle: subtitle,
                contextTags: session.contextTags(for: ref),
                customContextLabels: session.customContextLabels(for: ref)
            ))
        }

        for photoID in session.sessionAttachedPhotoIDs {
            guard let url = SessionAttachedPhotoStorage.url(for: photoID),
                  FileManager.default.fileExists(atPath: url.path) else { continue }
            let ref = SessionPhotoRef.attached(photoID)
            out.append(Item(
                ref: ref,
                title: "Session photo",
                subtitle: nil,
                contextTags: session.contextTags(for: ref),
                customContextLabels: session.customContextLabels(for: ref)
            ))
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

    /// Unique context filter chips across all photos in the given sessions (preset + custom).
    static func contextFilterOptions(from sessions: [Session]) -> [ContextFilterOption] {
        var seen = Set<String>()
        var options: [ContextFilterOption] = []
        for session in sessions {
            for item in items(for: session) {
                for tag in item.contextTags {
                    let key = SessionPhotoContextFilterKey.preset(tag)
                    if seen.insert(key).inserted {
                        options.append(ContextFilterOption(id: key, label: tag.label))
                    }
                }
                for label in item.customContextLabels {
                    let key = SessionPhotoContextFilterKey.custom(label)
                    if seen.insert(key).inserted {
                        options.append(ContextFilterOption(id: key, label: label))
                    }
                }
            }
        }
        return options.sorted {
            $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
        }
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

extension SessionPhotoContextTag {
    static func autoTags(for kind: SessionPhotoKind, compKind: CompKind? = nil) -> Set<SessionPhotoContextTag> {
        switch kind {
        case .chipTable:
            return [.chips]
        case .comp:
            var tags: Set<SessionPhotoContextTag> = [.comps]
            if compKind == .foodBeverage {
                tags.insert(.drinks)
                tags.insert(.food)
            } else {
                tags.insert(.receipt)
            }
            return tags
        case .attached:
            return []
        }
    }
}

enum SessionPhotoContextFilterKey {
    static func preset(_ tag: SessionPhotoContextTag) -> String { "p:\(tag.rawValue)" }
    static func custom(_ label: String) -> String { "c:\(label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())" }
}

extension Session {
    func contextTags(for ref: SessionPhotoRef) -> [SessionPhotoContextTag] {
        sessionPhotoContextTagsByRefKey[ref.storageKey] ?? []
    }

    func customContextLabels(for ref: SessionPhotoRef) -> [String] {
        sessionPhotoCustomContextByRefKey[ref.storageKey] ?? []
    }

    func photoContextFilterKeys(for ref: SessionPhotoRef) -> Set<String> {
        var keys = Set(contextTags(for: ref).map { SessionPhotoContextFilterKey.preset($0) })
        keys.formUnion(customContextLabels(for: ref).map { SessionPhotoContextFilterKey.custom($0) })
        return keys
    }

    func matchesContextFilters(_ filterKeys: Set<String>, for ref: SessionPhotoRef) -> Bool {
        guard !filterKeys.isEmpty else { return true }
        return !photoContextFilterKeys(for: ref).isDisjoint(with: filterKeys)
    }

    mutating func setContextTags(_ tags: [SessionPhotoContextTag], for ref: SessionPhotoRef) {
        if tags.isEmpty {
            sessionPhotoContextTagsByRefKey.removeValue(forKey: ref.storageKey)
        } else {
            sessionPhotoContextTagsByRefKey[ref.storageKey] = SessionPhotoContextTag.sorted(tags)
        }
    }

    mutating func setCustomContextLabels(_ labels: [String], for ref: SessionPhotoRef) {
        let normalized = Self.normalizedCustomContextLabels(labels)
        if normalized.isEmpty {
            sessionPhotoCustomContextByRefKey.removeValue(forKey: ref.storageKey)
        } else {
            sessionPhotoCustomContextByRefKey[ref.storageKey] = normalized
        }
    }

    static func normalizedCustomContextLabels(_ labels: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in labels {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            out.append(trimmed)
        }
        return out
    }

    /// Drops tag entries whose photo ref no longer exists on this session.
    mutating func pruneOrphanPhotoContextTags() {
        let validKeys = Set(SessionPhotoCatalog.items(for: self).map(\.ref.storageKey))
        sessionPhotoContextTagsByRefKey = sessionPhotoContextTagsByRefKey.filter { validKeys.contains($0.key) }
        sessionPhotoCustomContextByRefKey = sessionPhotoCustomContextByRefKey.filter { validKeys.contains($0.key) }
    }
}
