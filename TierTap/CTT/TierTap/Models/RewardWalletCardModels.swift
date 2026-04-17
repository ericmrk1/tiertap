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

    init(
        id: UUID = UUID(),
        rewardProgram: String,
        currentTier: String,
        expirationDate: Date?,
        notes: String,
        createdAt: Date = Date(),
        tierHistory: [TierHistoryEntry]? = nil
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
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case rewardProgram
        case currentTier
        case expirationDate
        case notes
        case createdAt
        case tierHistory
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
            return
        }
        cards = decoded.sorted { $0.createdAt < $1.createdAt }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(cards) else { return }
        try? data.write(to: jsonURL, options: .atomic)
    }

    #if os(iOS)
    @discardableResult
    func addCard(image: UIImage, rewardProgram: String, currentTier: String, expirationDate: Date?, notes: String) -> Bool {
        let id = UUID()
        guard WalletCardPhotoStorage.saveImage(image, cardID: id) else { return false }
        let card = RewardWalletCard(
            id: id,
            rewardProgram: rewardProgram,
            currentTier: currentTier,
            expirationDate: expirationDate,
            notes: notes
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
