import Foundation

enum SessionStatus: String, Codable, CaseIterable {
    case complete
    case requiringMoreInfo
}

/// Whether tier point figures for the session are treated as confirmed (`verified`) or still provisional (`unverified`).
/// `nil` on decoded sessions means data from before this feature existed; use `effectiveTierPointsVerification` (treat as verified).
enum SessionTierPointsVerification: String, Codable, CaseIterable {
    case verified
    case unverified
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

enum SessionGameCategory: String, Codable, CaseIterable {
    case table
    case slots
    case poker

    /// Short label for the game-type selector (table / slots / poker).
    var pickerTitle: String {
        switch self {
        case .table: return "Table games"
        case .slots: return "Slots"
        case .poker: return "Poker"
        }
    }
}

enum SessionPokerGameKind: String, Codable {
    case cash
    case tournament
}

/// High-level reel / layout style for slots (optional on each session).
enum SessionSlotFormat: String, Codable, CaseIterable {
    case classicStepper
    case video
    case waysAllWays
    case clusterGrid
    case dynamicWays
    case notSure
    case other

    var label: String {
        switch self {
        case .classicStepper: return "Classic / 3-reel"
        case .video: return "Video"
        case .waysAllWays: return "Ways / all-ways"
        case .clusterGrid: return "Cluster / grid"
        case .dynamicWays: return "Dynamic ways (e.g. Megaways-style)"
        case .notSure: return "Not sure"
        case .other: return "Other"
        }
    }
}

/// Dominant feature family for slots (optional on each session).
enum SessionSlotFeature: String, Codable, CaseIterable {
    case freeSpinsBonus
    case holdSpin
    case progressive
    case multiplier
    case standard
    case notSure
    case other

    var label: String {
        switch self {
        case .freeSpinsBonus: return "Free spins / bonus"
        case .holdSpin: return "Hold & spin"
        case .progressive: return "Progressive / jackpot"
        case .multiplier: return "Multiplier-focused"
        case .standard: return "Standard / no standout feature"
        case .notSure: return "Not sure"
        case .other: return "Other"
        }
    }
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
    /// When the player picked a TierTap wallet card at check-in, the card id used to sync ending tier back to the wallet.
    var linkedRewardWalletCardId: UUID?
    /// Confirmed vs provisional tier point totals. New sessions default to `.unverified`; `nil` is only for older persisted data.
    var tierPointsVerification: SessionTierPointsVerification?
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
    /// Optional slot machine format (reel/layout style).
    var slotFormat: SessionSlotFormat?
    /// Custom text when `slotFormat` is `.other`.
    var slotFormatOther: String?
    /// Optional dominant slot feature.
    var slotFeature: SessionSlotFeature?
    /// Custom text when `slotFeature` is `.other`.
    var slotFeatureOther: String?
    /// Freeform notes (denom, room, etc.).
    var slotNotes: String?

    var isComplete: Bool { status == .complete }
    var requiresMoreInfo: Bool { status == .requiringMoreInfo }

    /// For filtering and display: legacy sessions without `tierPointsVerification` count as verified.
    var effectiveTierPointsVerification: SessionTierPointsVerification {
        tierPointsVerification ?? .verified
    }

    enum CodingKeys: String, CodingKey {
        case id, game, casino, casinoLatitude, casinoLongitude, startTime, endTime, startingTierPoints, endingTierPoints
        case buyInEvents, compEvents, cashOut, avgBetActual, avgBetRated, isLive, status, sessionMood, privateNotes, rewardsProgramName, linkedRewardWalletCardId, tierPointsVerification
        case chipEstimatorImageFilename
        case gameCategory, pokerGameKind, pokerAllowsRebuy, pokerAllowsAddOn, pokerHasFreeOut, pokerVariant
        case pokerSmallBlind, pokerBigBlind, pokerAnte, pokerLevelMinutes, pokerStartingStack
        case slotFormat, slotFormatOther, slotFeature, slotFeatureOther, slotNotes
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
        linkedRewardWalletCardId = try c.decodeIfPresent(UUID.self, forKey: .linkedRewardWalletCardId)
        tierPointsVerification = try c.decodeIfPresent(SessionTierPointsVerification.self, forKey: .tierPointsVerification)
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
        slotFormat = try c.decodeIfPresent(SessionSlotFormat.self, forKey: .slotFormat)
        slotFormatOther = try c.decodeIfPresent(String.self, forKey: .slotFormatOther)
        slotFeature = try c.decodeIfPresent(SessionSlotFeature.self, forKey: .slotFeature)
        slotFeatureOther = try c.decodeIfPresent(String.self, forKey: .slotFeatureOther)
        slotNotes = try c.decodeIfPresent(String.self, forKey: .slotNotes)
    }

    init(id: UUID = UUID(), game: String, casino: String, casinoLatitude: Double? = nil, casinoLongitude: Double? = nil,
         startTime: Date, endTime: Date? = nil,
         startingTierPoints: Int, endingTierPoints: Int? = nil, buyInEvents: [BuyInEvent] = [],
         compEvents: [CompEvent] = [],
         cashOut: Int? = nil, avgBetActual: Int? = nil, avgBetRated: Int? = nil, isLive: Bool = false,
         status: SessionStatus = .complete, sessionMood: SessionMood? = nil, privateNotes: String? = nil,
         rewardsProgramName: String? = nil,
         linkedRewardWalletCardId: UUID? = nil,
         tierPointsVerification: SessionTierPointsVerification? = .unverified,
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
         pokerStartingStack: Int? = nil,
         slotFormat: SessionSlotFormat? = nil,
         slotFormatOther: String? = nil,
         slotFeature: SessionSlotFeature? = nil,
         slotFeatureOther: String? = nil,
         slotNotes: String? = nil) {
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
        self.linkedRewardWalletCardId = linkedRewardWalletCardId
        self.tierPointsVerification = tierPointsVerification
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
        self.slotFormat = slotFormat
        self.slotFormatOther = slotFormatOther
        self.slotFeature = slotFeature
        self.slotFeatureOther = slotFeatureOther
        self.slotNotes = slotNotes
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
        try c.encodeIfPresent(linkedRewardWalletCardId, forKey: .linkedRewardWalletCardId)
        try c.encodeIfPresent(tierPointsVerification, forKey: .tierPointsVerification)
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
        try c.encodeIfPresent(slotFormat, forKey: .slotFormat)
        try c.encodeIfPresent(slotFormatOther, forKey: .slotFormatOther)
        try c.encodeIfPresent(slotFeature, forKey: .slotFeature)
        try c.encodeIfPresent(slotFeatureOther, forKey: .slotFeatureOther)
        try c.encodeIfPresent(slotNotes, forKey: .slotNotes)
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
    /// Expected value: table net (win/loss) plus total comps, in currency units. Nil when cash-out is unknown.
    var expectedValue: Int? {
        guard let wl = winLoss else { return nil }
        return wl + totalComp
    }
    /// EV per hour when win/loss and duration are known.
    var expectedValuePerHour: Double? {
        guard let ev = expectedValue, hoursPlayed > 0 else { return nil }
        return Double(ev) / hoursPlayed
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

    /// Result used for analytics win/loss and rates: cash **net** (default) or **EV** (net + logged comps).
    func analyticsOutcome(useExpectedValue: Bool) -> Int? {
        guard winLoss != nil else { return nil }
        return useExpectedValue ? expectedValue : winLoss
    }

    /// Display label for slot format including "Other" detail when present.
    var slotFormatDisplayLabel: String? {
        guard let f = slotFormat else { return nil }
        if f == .other {
            let o = slotFormatOther?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return o.isEmpty ? f.label : "Other · \(o)"
        }
        return f.label
    }

    /// Display label for slot feature including "Other" detail when present.
    var slotFeatureDisplayLabel: String? {
        guard let f = slotFeature else { return nil }
        if f == .other {
            let o = slotFeatureOther?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return o.isEmpty ? f.label : "Other · \(o)"
        }
        return f.label
    }

    /// True when any slot metadata is stored.
    var hasSlotMetadata: Bool {
        slotFormat != nil || slotFeature != nil
            || !(slotNotes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    /// Maps UI state to persisted slot fields; clears all when category is not slots.
    static func persistedSlotMetadata(
        gameCategory: SessionGameCategory?,
        format: SessionSlotFormat?,
        formatOther: String,
        feature: SessionSlotFeature?,
        featureOther: String,
        notes: String
    ) -> (format: SessionSlotFormat?, formatOther: String?, feature: SessionSlotFeature?, featureOther: String?, notes: String?) {
        guard gameCategory == .slots else {
            return (nil, nil, nil, nil, nil)
        }
        let fo = formatOther.trimmingCharacters(in: .whitespacesAndNewlines)
        let feo = featureOther.trimmingCharacters(in: .whitespacesAndNewlines)
        let n = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return (
            format,
            format == .other ? (fo.isEmpty ? nil : fo) : nil,
            feature,
            feature == .other ? (feo.isEmpty ? nil : feo) : nil,
            n.isEmpty ? nil : n
        )
    }
}
