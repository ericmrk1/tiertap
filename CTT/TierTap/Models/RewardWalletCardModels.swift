import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#endif

// MARK: - Photo files (documents/reward_wallet_photos)

enum WalletCardPhotoStorage {
    private static let directoryName = "reward_wallet_photos"

    private static var directoryURL: URL? {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return documents.appendingPathComponent(directoryName, isDirectory: true)
    }

    @discardableResult
    static func saveJPEGData(_ data: Data, cardID: UUID) -> Bool {
        guard let dir = directoryURL else { return false }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("\(cardID.uuidString).jpg")
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    #if os(iOS)
    @discardableResult
    static func saveImage(_ image: UIImage, cardID: UUID) -> Bool {
        guard let data = image.jpegData(compressionQuality: 0.88) else { return false }
        return saveJPEGData(data, cardID: cardID)
    }

    static func loadImage(cardID: UUID) -> UIImage? {
        guard let url = url(for: cardID) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
    #endif

    static func url(for cardID: UUID) -> URL? {
        directoryURL?.appendingPathComponent("\(cardID.uuidString).jpg")
    }

    static func deleteImage(cardID: UUID) {
        guard let url = url(for: cardID) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - Card record (JSON)

struct RewardWalletCard: Identifiable, Codable, Equatable {
    struct TierHistoryEntry: Identifiable, Codable, Equatable {
        var id: UUID
        var tier: String
        var recordedAt: Date

        init(id: UUID = UUID(), tier: String, recordedAt: Date = Date()) {
            self.id = id
            self.tier = tier
            self.recordedAt = recordedAt
        }
    }

    var id: UUID
    var rewardProgram: String
    var currentTier: String
    /// Stored as time interval since reference date when set; `nil` means no expiration.
    var expirationDate: Date?
    var notes: String
    var createdAt: Date
    var tierHistory: [TierHistoryEntry]
    /// Optional next-tier / status threshold in loyalty points.
    var tierGoalPoints: Int?
    /// Optional label for the goal (e.g. "NOIR", "Diamond").
    var tierGoalLabel: String?

    init(
        id: UUID = UUID(),
        rewardProgram: String,
        currentTier: String,
        expirationDate: Date?,
        notes: String,
        createdAt: Date = Date(),
        tierHistory: [TierHistoryEntry]? = nil,
        tierGoalPoints: Int? = nil,
        tierGoalLabel: String? = nil
    ) {
        self.id = id
        self.rewardProgram = rewardProgram
        self.currentTier = currentTier
        self.expirationDate = expirationDate
        self.notes = notes
        self.createdAt = createdAt
        self.tierHistory = RewardWalletCard.bootstrapTierHistory(
            explicitHistory: tierHistory,
            currentTier: currentTier,
            fallbackDate: createdAt
        )
        self.tierGoalPoints = tierGoalPoints
        self.tierGoalLabel = tierGoalLabel
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case rewardProgram
        case currentTier
        case expirationDate
        case notes
        case createdAt
        case tierHistory
        case tierGoalPoints
        case tierGoalLabel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        rewardProgram = try container.decode(String.self, forKey: .rewardProgram)
        currentTier = try container.decode(String.self, forKey: .currentTier)
        expirationDate = try container.decodeIfPresent(Date.self, forKey: .expirationDate)
        notes = try container.decode(String.self, forKey: .notes)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        let decodedHistory = try container.decodeIfPresent([TierHistoryEntry].self, forKey: .tierHistory)
        tierHistory = RewardWalletCard.bootstrapTierHistory(
            explicitHistory: decodedHistory,
            currentTier: currentTier,
            fallbackDate: createdAt
        )
        tierGoalPoints = try container.decodeIfPresent(Int.self, forKey: .tierGoalPoints)
        tierGoalLabel = try container.decodeIfPresent(String.self, forKey: .tierGoalLabel)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(rewardProgram, forKey: .rewardProgram)
        try container.encode(currentTier, forKey: .currentTier)
        try container.encodeIfPresent(expirationDate, forKey: .expirationDate)
        try container.encode(notes, forKey: .notes)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(tierHistory, forKey: .tierHistory)
        try container.encodeIfPresent(tierGoalPoints, forKey: .tierGoalPoints)
        try container.encodeIfPresent(tierGoalLabel, forKey: .tierGoalLabel)
    }

    private static func bootstrapTierHistory(
        explicitHistory: [TierHistoryEntry]?,
        currentTier: String,
        fallbackDate: Date
    ) -> [TierHistoryEntry] {
        if let explicitHistory, !explicitHistory.isEmpty {
            return explicitHistory.sorted { $0.recordedAt < $1.recordedAt }
        }
        let trimmedTier = currentTier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTier.isEmpty else { return [] }
        return [TierHistoryEntry(tier: trimmedTier, recordedAt: fallbackDate)]
    }
}

// MARK: - Store

@MainActor
final class RewardWalletStore: ObservableObject {
    @Published private(set) var cards: [RewardWalletCard] = []

    private let jsonURL: URL

    #if os(iOS)
    /// In-memory JPEG decode cache so wallet stack scrolling does not re-hit disk every frame.
    private var imageMemoryCache: [UUID: UIImage] = [:]
    #endif

    init(fileManager: FileManager = .default) {
        let dir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let folder = dir.appendingPathComponent("reward_wallet", isDirectory: true)
        jsonURL = folder.appendingPathComponent("cards.json")
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        load()
    }

    func load() {
        #if os(iOS)
        imageMemoryCache.removeAll()
        #endif
        guard let data = try? Data(contentsOf: jsonURL),
              let decoded = try? JSONDecoder().decode([RewardWalletCard].self, from: data) else {
            cards = []
            #if os(iOS)
            seedWatchTierGoalsBaseline()
            #endif
            return
        }
        cards = decoded.sorted { $0.createdAt < $1.createdAt }
        #if os(iOS)
        seedWatchTierGoalsBaseline()
        #endif
    }

    #if os(iOS)
    /// Establishes the Watch sync baseline without celebrating already-complete goals.
    private func seedWatchTierGoalsBaseline() {
        guard TierTapProductEnhancements.isEnabled else {
            SessionSyncManager.shared.pushTierGoals([])
            return
        }
        SessionSyncManager.shared.pushTierGoals(Self.watchSyncedTierGoals(from: cards))
    }
    #endif

    private func persist() {
        guard let data = try? JSONEncoder().encode(cards) else { return }
        try? data.write(to: jsonURL, options: .atomic)
        #if os(iOS)
        syncTierGoalsToWatch()
        NotificationCenter.default.post(name: NSNotification.Name("RepublishHomeWidgetSnapshot"), object: nil)
        #endif
    }

    #if os(iOS)
    /// Mirrors wallet tier goals to the Watch and fires a celebration when a goal newly hits 100%.
    private func syncTierGoalsToWatch() {
        guard TierTapProductEnhancements.isEnabled else {
            SessionSyncManager.shared.pushTierGoals([])
            return
        }
        let previous = SessionSyncManager.shared.latestTierGoals()
        let previousByID = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
        let goals = Self.watchSyncedTierGoals(from: cards)
        TierTapCelebrationController.shared.noteTierGoalsSnapshot(goals)
        SessionSyncManager.shared.pushTierGoals(goals)
        for goal in goals where goal.isComplete {
            // Only celebrate a real crossing: we must have seen this goal incomplete before.
            guard let prior = previousByID[goal.id], !prior.isComplete else { continue }
            let event = WatchTierGoalCompletionEvent(
                goal: goal,
                previousProgress: min(prior.progress, 0.98),
                completedAt: Date().timeIntervalSince1970
            )
            SessionSyncManager.shared.notifyTierGoalCompleted(event)
            TierTapCelebrationController.shared.enqueueTierGoal(event)
        }
    }

    static func watchSyncedTierGoals(from cards: [RewardWalletCard]) -> [WatchSyncedTierGoal] {
        cards
            .compactMap { card -> WatchSyncedTierGoal? in
                guard card.hasTierGoal, let goal = card.tierGoalPoints, goal > 0 else { return nil }
                let program = card.rewardProgram.trimmingCharacters(in: .whitespacesAndNewlines)
                let label = card.tierGoalLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
                return WatchSyncedTierGoal(
                    id: card.id.uuidString,
                    programName: program.isEmpty ? "Loyalty" : program,
                    goalLabel: (label?.isEmpty == false) ? label : nil,
                    currentPoints: card.parsedCurrentTierPoints ?? 0,
                    goalPoints: goal
                )
            }
            .sorted { lhs, rhs in
                if lhs.currentPoints != rhs.currentPoints {
                    return lhs.currentPoints > rhs.currentPoints
                }
                return lhs.goalPoints > rhs.goalPoints
            }
    }
    #endif

    #if os(iOS)
    @discardableResult
    func addCard(
        image: UIImage,
        rewardProgram: String,
        currentTier: String,
        expirationDate: Date?,
        notes: String,
        tierGoalPoints: Int? = nil,
        tierGoalLabel: String? = nil
    ) -> Bool {
        let id = UUID()
        guard WalletCardPhotoStorage.saveImage(image, cardID: id) else { return false }
        let card = RewardWalletCard(
            id: id,
            rewardProgram: rewardProgram,
            currentTier: currentTier,
            expirationDate: expirationDate,
            notes: notes,
            tierGoalPoints: tierGoalPoints,
            tierGoalLabel: tierGoalLabel
        )
        cards.append(card)
        persist()
        imageMemoryCache[id] = image
        return true
    }

    func updateCard(_ card: RewardWalletCard, newImage: UIImage?) {
        guard let idx = cards.firstIndex(where: { $0.id == card.id }) else { return }
        let previous = cards[idx]
        if let img = newImage {
            _ = WalletCardPhotoStorage.saveImage(img, cardID: card.id)
            imageMemoryCache[card.id] = img
        }
        var updated = card
        if normalizedTier(previous.currentTier) != normalizedTier(updated.currentTier) {
            let trimmedTier = updated.currentTier.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedTier.isEmpty {
                updated.tierHistory.append(
                    RewardWalletCard.TierHistoryEntry(tier: trimmedTier, recordedAt: Date())
                )
            }
        }
        updated.tierHistory = updated.tierHistory.sorted { $0.recordedAt < $1.recordedAt }
        cards[idx] = updated
        persist()
    }

    func resetTierHistory(for cardID: UUID, preserveCurrentTierSnapshot: Bool = true) {
        guard let idx = cards.firstIndex(where: { $0.id == cardID }) else { return }
        let trimmedTier = cards[idx].currentTier.trimmingCharacters(in: .whitespacesAndNewlines)
        if preserveCurrentTierSnapshot, !trimmedTier.isEmpty {
            cards[idx].tierHistory = [
                RewardWalletCard.TierHistoryEntry(tier: trimmedTier, recordedAt: Date())
            ]
        } else {
            cards[idx].tierHistory = []
        }
        persist()
    }
    #endif

    func deleteCard(id: UUID) {
        cards.removeAll { $0.id == id }
        #if os(iOS)
        imageMemoryCache.removeValue(forKey: id)
        #endif
        WalletCardPhotoStorage.deleteImage(cardID: id)
        persist()
    }

    #if os(iOS)
    func image(for card: RewardWalletCard) -> UIImage? {
        if let cached = imageMemoryCache[card.id] { return cached }
        guard let loaded = WalletCardPhotoStorage.loadImage(cardID: card.id) else { return nil }
        imageMemoryCache[card.id] = loaded
        return loaded
    }

    /// Warms the decode cache for every on-disk card photo (call when opening the wallet).
    func preloadAllCardImages() {
        for card in cards {
            if imageMemoryCache[card.id] != nil { continue }
            if let img = WalletCardPhotoStorage.loadImage(cardID: card.id) {
                imageMemoryCache[card.id] = img
            }
        }
    }

    func invalidateImageCache(for cardID: UUID) {
        imageMemoryCache.removeValue(forKey: cardID)
    }
    #endif

    private func normalizedTier(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
