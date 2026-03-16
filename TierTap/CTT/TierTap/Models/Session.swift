import Foundation

enum SessionStatus: String, Codable, CaseIterable {
    case complete
    case requiringMoreInfo
}

/// Emotional state after a session (stored in session metadata).
enum SessionMood: String, Codable, CaseIterable {
    case epic      // amazing
    case great
    case good
    case okay
    case meh
    case disappointed
    case frustrated
    case tilt
    case rough

    var label: String {
        switch self {
        case .epic: return "Epic"
        case .great: return "Great"
        case .good: return "Good"
        case .okay: return "Okay"
        case .meh: return "Meh"
        case .disappointed: return "Disappointed"
        case .frustrated: return "Frustrated"
        case .tilt: return "Tilt"
        case .rough: return "Rough"
        }
    }

    /// Used for downswing detection: disappointed, frustrated, tilt, rough.
    var isDownswingMood: Bool {
        switch self {
        case .disappointed, .frustrated, .tilt, .rough: return true
        default: return false
        }
    }
}

struct BuyInEvent: Identifiable, Codable, Hashable {
    var id = UUID()
    var amount: Int
    var timestamp: Date
}

enum SessionGameCategory: String, Codable {
    case table
    case poker
}

enum SessionPokerGameKind: String, Codable {
    case cash
    case tournament
}

struct Session: Identifiable, Codable, Equatable {
    var id = UUID()
    var game: String
    var casino: String
    var startTime: Date
    var endTime: Date?
    var startingTierPoints: Int
    var endingTierPoints: Int?
    var buyInEvents: [BuyInEvent] = []
    var cashOut: Int?
    var avgBetActual: Int?
    var avgBetRated: Int?
    var isLive: Bool = false
    var status: SessionStatus = .complete
    var sessionMood: SessionMood?
    /// Private notes; stored locally only, never shared to community/database.
    var privateNotes: String?
    /// Optional filename for a locally stored chip estimator photo associated with this session.
    var chipEstimatorImageFilename: String?

    /// Optional structured metadata describing the type of game.
    /// Older sessions may have these unset; fall back to `game` string if needed.
    var gameCategory: SessionGameCategory?
    var pokerGameKind: SessionPokerGameKind?
    var pokerAllowsRebuy: Bool?
    var pokerAllowsAddOn: Bool?
    var pokerHasFreeOut: Bool?
    var pokerVariant: String?
    /// Optional structured metadata for poker game structure (cash and tournaments).
    /// Blinds/ante are typically used for cash games; level clock and starting stack for tournaments.
    var pokerSmallBlind: Int?
    var pokerBigBlind: Int?
    var pokerAnte: Int?
    var pokerLevelMinutes: Int?
    var pokerStartingStack: Int?

    var isComplete: Bool { status == .complete }
    var requiresMoreInfo: Bool { status == .requiringMoreInfo }

    enum CodingKeys: String, CodingKey {
        case id, game, casino, startTime, endTime, startingTierPoints, endingTierPoints
        case buyInEvents, cashOut, avgBetActual, avgBetRated, isLive, status, sessionMood, privateNotes
        case chipEstimatorImageFilename
        case gameCategory, pokerGameKind, pokerAllowsRebuy, pokerAllowsAddOn, pokerHasFreeOut, pokerVariant
        case pokerSmallBlind, pokerBigBlind, pokerAnte, pokerLevelMinutes, pokerStartingStack
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        game = try c.decode(String.self, forKey: .game)
        casino = try c.decode(String.self, forKey: .casino)
        startTime = try c.decode(Date.self, forKey: .startTime)
        endTime = try c.decodeIfPresent(Date.self, forKey: .endTime)
        startingTierPoints = try c.decode(Int.self, forKey: .startingTierPoints)
        endingTierPoints = try c.decodeIfPresent(Int.self, forKey: .endingTierPoints)
        buyInEvents = try c.decodeIfPresent([BuyInEvent].self, forKey: .buyInEvents) ?? []
        cashOut = try c.decodeIfPresent(Int.self, forKey: .cashOut)
        avgBetActual = try c.decodeIfPresent(Int.self, forKey: .avgBetActual)
        avgBetRated = try c.decodeIfPresent(Int.self, forKey: .avgBetRated)
        isLive = try c.decodeIfPresent(Bool.self, forKey: .isLive) ?? false
        status = try c.decodeIfPresent(SessionStatus.self, forKey: .status) ?? .complete
        sessionMood = try c.decodeIfPresent(SessionMood.self, forKey: .sessionMood)
        privateNotes = try c.decodeIfPresent(String.self, forKey: .privateNotes)
        chipEstimatorImageFilename = try c.decodeIfPresent(String.self, forKey: .chipEstimatorImageFilename)
        gameCategory = try c.decodeIfPresent(SessionGameCategory.self, forKey: .gameCategory)
        pokerGameKind = try c.decodeIfPresent(SessionPokerGameKind.self, forKey: .pokerGameKind)
        pokerAllowsRebuy = try c.decodeIfPresent(Bool.self, forKey: .pokerAllowsRebuy)
        pokerAllowsAddOn = try c.decodeIfPresent(Bool.self, forKey: .pokerAllowsAddOn)
        pokerHasFreeOut = try c.decodeIfPresent(Bool.self, forKey: .pokerHasFreeOut)
        pokerVariant = try c.decodeIfPresent(String.self, forKey: .pokerVariant)
        pokerSmallBlind = try c.decodeIfPresent(Int.self, forKey: .pokerSmallBlind)
        pokerBigBlind = try c.decodeIfPresent(Int.self, forKey: .pokerBigBlind)
        pokerAnte = try c.decodeIfPresent(Int.self, forKey: .pokerAnte)
        pokerLevelMinutes = try c.decodeIfPresent(Int.self, forKey: .pokerLevelMinutes)
        pokerStartingStack = try c.decodeIfPresent(Int.self, forKey: .pokerStartingStack)
    }

    init(id: UUID = UUID(), game: String, casino: String, startTime: Date, endTime: Date? = nil,
         startingTierPoints: Int, endingTierPoints: Int? = nil, buyInEvents: [BuyInEvent] = [],
         cashOut: Int? = nil, avgBetActual: Int? = nil, avgBetRated: Int? = nil, isLive: Bool = false,
         status: SessionStatus = .complete, sessionMood: SessionMood? = nil, privateNotes: String? = nil,
         chipEstimatorImageFilename: String? = nil,
         gameCategory: SessionGameCategory? = nil,
         pokerGameKind: SessionPokerGameKind? = nil,
         pokerAllowsRebuy: Bool? = nil,
         pokerAllowsAddOn: Bool? = nil,
         pokerHasFreeOut: Bool? = nil,
         pokerVariant: String? = nil,
         pokerSmallBlind: Int? = nil,
         pokerBigBlind: Int? = nil,
         pokerAnte: Int? = nil,
         pokerLevelMinutes: Int? = nil,
         pokerStartingStack: Int? = nil) {
        self.id = id
        self.game = game
        self.casino = casino
        self.startTime = startTime
        self.endTime = endTime
        self.startingTierPoints = startingTierPoints
        self.endingTierPoints = endingTierPoints
        self.buyInEvents = buyInEvents
        self.cashOut = cashOut
        self.avgBetActual = avgBetActual
        self.avgBetRated = avgBetRated
        self.isLive = isLive
        self.status = status
        self.sessionMood = sessionMood
        self.privateNotes = privateNotes
        self.chipEstimatorImageFilename = chipEstimatorImageFilename
        self.gameCategory = gameCategory
        self.pokerGameKind = pokerGameKind
        self.pokerAllowsRebuy = pokerAllowsRebuy
        self.pokerAllowsAddOn = pokerAllowsAddOn
        self.pokerHasFreeOut = pokerHasFreeOut
        self.pokerVariant = pokerVariant
        self.pokerSmallBlind = pokerSmallBlind
        self.pokerBigBlind = pokerBigBlind
        self.pokerAnte = pokerAnte
        self.pokerLevelMinutes = pokerLevelMinutes
        self.pokerStartingStack = pokerStartingStack
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(game, forKey: .game)
        try c.encode(casino, forKey: .casino)
        try c.encode(startTime, forKey: .startTime)
        try c.encodeIfPresent(endTime, forKey: .endTime)
        try c.encode(startingTierPoints, forKey: .startingTierPoints)
        try c.encodeIfPresent(endingTierPoints, forKey: .endingTierPoints)
        try c.encode(buyInEvents, forKey: .buyInEvents)
        try c.encodeIfPresent(cashOut, forKey: .cashOut)
        try c.encodeIfPresent(avgBetActual, forKey: .avgBetActual)
        try c.encodeIfPresent(avgBetRated, forKey: .avgBetRated)
        try c.encode(isLive, forKey: .isLive)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(sessionMood, forKey: .sessionMood)
        try c.encodeIfPresent(privateNotes, forKey: .privateNotes)
        try c.encodeIfPresent(chipEstimatorImageFilename, forKey: .chipEstimatorImageFilename)
        try c.encodeIfPresent(gameCategory, forKey: .gameCategory)
        try c.encodeIfPresent(pokerGameKind, forKey: .pokerGameKind)
        try c.encodeIfPresent(pokerAllowsRebuy, forKey: .pokerAllowsRebuy)
        try c.encodeIfPresent(pokerAllowsAddOn, forKey: .pokerAllowsAddOn)
        try c.encodeIfPresent(pokerHasFreeOut, forKey: .pokerHasFreeOut)
        try c.encodeIfPresent(pokerVariant, forKey: .pokerVariant)
        try c.encodeIfPresent(pokerSmallBlind, forKey: .pokerSmallBlind)
        try c.encodeIfPresent(pokerBigBlind, forKey: .pokerBigBlind)
        try c.encodeIfPresent(pokerAnte, forKey: .pokerAnte)
        try c.encodeIfPresent(pokerLevelMinutes, forKey: .pokerLevelMinutes)
        try c.encodeIfPresent(pokerStartingStack, forKey: .pokerStartingStack)
    }

    var totalBuyIn: Int { buyInEvents.reduce(0) { $0 + $1.amount } }

    var duration: TimeInterval {
        (endTime ?? Date()).timeIntervalSince(startTime)
    }
    var hoursPlayed: Double { duration / 3600.0 }

    var winLoss: Int? {
        guard let c = cashOut else { return nil }
        return c - totalBuyIn
    }
    /// Net result per hour (win rate) in currency units, if both win/loss and hours are available.
    var winRatePerHour: Double? {
        guard let wl = winLoss, hoursPlayed > 0 else { return nil }
        return Double(wl) / hoursPlayed
    }
    /// Initial buy-in amount for the session (first buy-in event), if available.
    var initialBuyIn: Int? {
        buyInEvents.first?.amount
    }
    var tierPointsEarned: Int? {
        guard let e = endingTierPoints else { return nil }
        return e - startingTierPoints
    }
    var tiersPerHour: Double? {
        guard let e = tierPointsEarned, hoursPlayed > 0 else { return nil }
        return Double(e) / hoursPlayed
    }
    var tiersPerHundredRatedBetHour: Double? {
        guard let r = avgBetRated, r >= 100,
              let e = tierPointsEarned, hoursPlayed > 0 else { return nil }
        return (Double(e) / (Double(r) * hoursPlayed)) * 100.0
    }

    static func durationString(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600, m = (Int(t) % 3600) / 60, s = Int(t) % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
