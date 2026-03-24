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

/// Category of complimentary value (for logging; does not affect win/loss math).
enum CompKind: String, Codable, CaseIterable {
    case dollarsCredits
    case foodBeverage

    var title: String {
        switch self {
        case .dollarsCredits: return "Dollars / credits"
        case .foodBeverage: return "Food & beverage"
        }
    }

    var subtitle: String {
        switch self {
        case .dollarsCredits: return "Free play, slot credit, match play…"
        case .foodBeverage: return "Meals, drinks, room dining…"
        }
    }

    var symbolName: String {
        switch self {
        case .dollarsCredits: return "dollarsign.circle.fill"
        case .foodBeverage: return "fork.knife"
        }
    }
}

/// Food & beverage comp subtype (only used when `CompKind` is `.foodBeverage`).
enum FoodBeverageKind: String, Codable, CaseIterable {
    case meal
    case drinks
    case coffeeSnack
    case roomService
    case other

    var label: String {
        switch self {
        case .meal: return "Meal"
        case .drinks: return "Drinks / bar"
        case .coffeeSnack: return "Coffee / snack"
        case .roomService: return "Room service"
        case .other: return "Other"
        }
    }
}

/// Complimentary value received during a session (meals, rooms, free play, etc.).
struct CompEvent: Identifiable, Codable, Hashable {
    var id = UUID()
    var amount: Int
    var timestamp: Date
    var kind: CompKind
    /// Optional note (what you received); stored locally.
    var details: String?
    /// Set for food & beverage comps only.
    var foodBeverageKind: FoodBeverageKind?
    /// Custom label when `foodBeverageKind` is `.other` (e.g. "buffet", "show tickets").
    var foodBeverageOtherDescription: String?

    init(id: UUID = UUID(), amount: Int, timestamp: Date, kind: CompKind = .dollarsCredits, details: String? = nil, foodBeverageKind: FoodBeverageKind? = nil, foodBeverageOtherDescription: String? = nil) {
        self.id = id
        self.amount = amount
        self.timestamp = timestamp
        self.kind = kind
        self.details = details
        self.foodBeverageKind = foodBeverageKind
        self.foodBeverageOtherDescription = foodBeverageOtherDescription
    }

    enum CodingKeys: String, CodingKey {
        case id, amount, timestamp, kind, details, foodBeverageKind, foodBeverageOtherDescription
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        amount = try c.decode(Int.self, forKey: .amount)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        kind = try c.decodeIfPresent(CompKind.self, forKey: .kind) ?? .dollarsCredits
        details = try c.decodeIfPresent(String.self, forKey: .details)
        foodBeverageKind = try c.decodeIfPresent(FoodBeverageKind.self, forKey: .foodBeverageKind)
        foodBeverageOtherDescription = try c.decodeIfPresent(String.self, forKey: .foodBeverageOtherDescription)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(amount, forKey: .amount)
        try c.encode(timestamp, forKey: .timestamp)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(details, forKey: .details)
        try c.encodeIfPresent(foodBeverageKind, forKey: .foodBeverageKind)
        try c.encodeIfPresent(foodBeverageOtherDescription, forKey: .foodBeverageOtherDescription)
    }
}

extension CompEvent {
    /// Label for food & beverage subtype in lists (custom text when kind is `.other`).
    var foodBeverageKindDisplayLabel: String? {
        guard let fb = foodBeverageKind else { return nil }
        if fb == .other {
            let o = foodBeverageOtherDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return o.isEmpty ? fb.label : "Other · \(o)"
        }
        return fb.label
    }
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
    /// WGS84 latitude when the user picked a location from the map at check-in; optional.
    var casinoLatitude: Double?
    /// WGS84 longitude when the user picked a location from the map at check-in; optional.
    var casinoLongitude: Double?
    var startTime: Date
    var endTime: Date?
    var startingTierPoints: Int
    var endingTierPoints: Int?
    var buyInEvents: [BuyInEvent] = []
    var compEvents: [CompEvent] = []
    var cashOut: Int?
    var avgBetActual: Int?
    var avgBetRated: Int?
    var isLive: Bool = false
    var status: SessionStatus = .complete
    var sessionMood: SessionMood?
    /// Private notes; stored locally only, never shared to community/database.
    var privateNotes: String?
    /// Loyalty program name chosen at check-in (e.g. MGM Rewards), if any.
    var rewardsProgramName: String?
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
        case id, game, casino, casinoLatitude, casinoLongitude, startTime, endTime, startingTierPoints, endingTierPoints
        case buyInEvents, compEvents, cashOut, avgBetActual, avgBetRated, isLive, status, sessionMood, privateNotes, rewardsProgramName
        case chipEstimatorImageFilename
        case gameCategory, pokerGameKind, pokerAllowsRebuy, pokerAllowsAddOn, pokerHasFreeOut, pokerVariant
        case pokerSmallBlind, pokerBigBlind, pokerAnte, pokerLevelMinutes, pokerStartingStack
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        game = try c.decode(String.self, forKey: .game)
        casino = try c.decode(String.self, forKey: .casino)
        casinoLatitude = try c.decodeIfPresent(Double.self, forKey: .casinoLatitude)
        casinoLongitude = try c.decodeIfPresent(Double.self, forKey: .casinoLongitude)
        startTime = try c.decode(Date.self, forKey: .startTime)
        endTime = try c.decodeIfPresent(Date.self, forKey: .endTime)
        startingTierPoints = try c.decode(Int.self, forKey: .startingTierPoints)
        endingTierPoints = try c.decodeIfPresent(Int.self, forKey: .endingTierPoints)
        buyInEvents = try c.decodeIfPresent([BuyInEvent].self, forKey: .buyInEvents) ?? []
        compEvents = try c.decodeIfPresent([CompEvent].self, forKey: .compEvents) ?? []
        cashOut = try c.decodeIfPresent(Int.self, forKey: .cashOut)
        avgBetActual = try c.decodeIfPresent(Int.self, forKey: .avgBetActual)
        avgBetRated = try c.decodeIfPresent(Int.self, forKey: .avgBetRated)
        isLive = try c.decodeIfPresent(Bool.self, forKey: .isLive) ?? false
        status = try c.decodeIfPresent(SessionStatus.self, forKey: .status) ?? .complete
        sessionMood = try c.decodeIfPresent(SessionMood.self, forKey: .sessionMood)
        privateNotes = try c.decodeIfPresent(String.self, forKey: .privateNotes)
        rewardsProgramName = try c.decodeIfPresent(String.self, forKey: .rewardsProgramName)
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

    init(id: UUID = UUID(), game: String, casino: String, casinoLatitude: Double? = nil, casinoLongitude: Double? = nil,
         startTime: Date, endTime: Date? = nil,
         startingTierPoints: Int, endingTierPoints: Int? = nil, buyInEvents: [BuyInEvent] = [],
         compEvents: [CompEvent] = [],
         cashOut: Int? = nil, avgBetActual: Int? = nil, avgBetRated: Int? = nil, isLive: Bool = false,
         status: SessionStatus = .complete, sessionMood: SessionMood? = nil, privateNotes: String? = nil,
         rewardsProgramName: String? = nil,
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
        self.casinoLatitude = casinoLatitude
        self.casinoLongitude = casinoLongitude
        self.startTime = startTime
        self.endTime = endTime
        self.startingTierPoints = startingTierPoints
        self.endingTierPoints = endingTierPoints
        self.buyInEvents = buyInEvents
        self.compEvents = compEvents
        self.cashOut = cashOut
        self.avgBetActual = avgBetActual
        self.avgBetRated = avgBetRated
        self.isLive = isLive
        self.status = status
        self.sessionMood = sessionMood
        self.privateNotes = privateNotes
        self.rewardsProgramName = rewardsProgramName
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
        try c.encodeIfPresent(casinoLatitude, forKey: .casinoLatitude)
        try c.encodeIfPresent(casinoLongitude, forKey: .casinoLongitude)
        try c.encode(startTime, forKey: .startTime)
        try c.encodeIfPresent(endTime, forKey: .endTime)
        try c.encode(startingTierPoints, forKey: .startingTierPoints)
        try c.encodeIfPresent(endingTierPoints, forKey: .endingTierPoints)
        try c.encode(buyInEvents, forKey: .buyInEvents)
        try c.encode(compEvents, forKey: .compEvents)
        try c.encodeIfPresent(cashOut, forKey: .cashOut)
        try c.encodeIfPresent(avgBetActual, forKey: .avgBetActual)
        try c.encodeIfPresent(avgBetRated, forKey: .avgBetRated)
        try c.encode(isLive, forKey: .isLive)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(sessionMood, forKey: .sessionMood)
        try c.encodeIfPresent(privateNotes, forKey: .privateNotes)
        try c.encodeIfPresent(rewardsProgramName, forKey: .rewardsProgramName)
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

    var totalComp: Int { compEvents.reduce(0) { $0 + $1.amount } }

    /// Sum of comps logged as dollars / credits (excludes food & beverage).
    var totalCompDollarsCredits: Int {
        compEvents.filter { $0.kind == .dollarsCredits }.reduce(0) { $0 + $1.amount }
    }

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
