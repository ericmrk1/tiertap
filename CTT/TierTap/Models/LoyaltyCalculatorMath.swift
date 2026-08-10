import Foundation

/// Shared loyalty / theoretical-play math used by the Loyalty Calculator screens.
enum LoyaltyCalculatorMath {

    /// Classic host-style theo: average bet × decisions per hour × hours × house edge.
    /// Negative `houseEdgePercent` means player edge / advantage (+EV → negative theo / expected win).
    static func theo(
        averageBet: Double,
        decisionsPerHour: Double,
        hours: Double,
        houseEdgePercent: Double
    ) -> Double? {
        guard averageBet > 0, decisionsPerHour > 0, hours > 0, houseEdgePercent.isFinite else { return nil }
        return averageBet * decisionsPerHour * hours * (houseEdgePercent / 100.0)
    }

    /// Slots theo from total coin-in and hold percent. Negative hold = player edge (+EV).
    static func slotTheoFromCoinIn(coinIn: Double, holdPercent: Double) -> Double? {
        guard coinIn > 0, holdPercent.isFinite else { return nil }
        return coinIn * (holdPercent / 100.0)
    }

    /// Slots theo from bet size, spin rate, hours, and hold. Negative hold = player edge (+EV).
    static func slotTheoFromPace(
        averageBet: Double,
        spinsPerHour: Double,
        hours: Double,
        holdPercent: Double
    ) -> Double? {
        guard averageBet > 0, spinsPerHour > 0, hours > 0, holdPercent.isFinite else { return nil }
        let coinIn = averageBet * spinsPerHour * hours
        return coinIn * (holdPercent / 100.0)
    }

    /// Average Daily Theo: total theo ÷ days played. Allows negative trip theo (+EV days).
    static func averageDailyTheo(totalTheo: Double, days: Double) -> Double? {
        guard totalTheo.isFinite, days > 0 else { return nil }
        return totalTheo / days
    }

    /// Comp return estimate from theo and rematch percent (e.g. 20% of theo).
    /// Negative theo (+EV) yields no rematch estimate (hosts rate house-side theo).
    static func estimatedComps(theo: Double, rematchPercent: Double) -> Double? {
        guard theo.isFinite, rematchPercent >= 0 else { return nil }
        if theo < 0 { return 0 }
        return theo * (rematchPercent / 100.0)
    }

    /// Tier points from a rating basis (theo or coin-in) × points per dollar × promo multiplier.
    static func estimatedTierPoints(
        basisDollars: Double,
        pointsPerDollar: Double,
        multiplier: Double
    ) -> Double? {
        guard basisDollars >= 0, pointsPerDollar >= 0, multiplier > 0 else { return nil }
        return basisDollars * pointsPerDollar * multiplier
    }

    /// Dollars of basis still needed to earn remaining tier points.
    static func basisNeededForPoints(
        pointsNeeded: Double,
        pointsPerDollar: Double,
        multiplier: Double
    ) -> Double? {
        guard pointsNeeded >= 0, pointsPerDollar > 0, multiplier > 0 else { return nil }
        return pointsNeeded / (pointsPerDollar * multiplier)
    }
}

/// Whether entered edge magnitude favors the house or the player (advantage / +EV).
enum LoyaltyEdgeBeneficiary: String, CaseIterable, Identifiable {
    case house
    case playerAdvantage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .house: return "House edge"
        case .playerAdvantage: return "Player edge (+EV)"
        }
    }

    var shortTitle: String {
        switch self {
        case .house: return "House"
        case .playerAdvantage: return "Player (+EV)"
        }
    }

    /// Applies house (+) or player (−) sign to a non-negative magnitude percent.
    func signedPercent(magnitude: Double) -> Double {
        let mag = abs(magnitude)
        switch self {
        case .house: return mag
        case .playerAdvantage: return -mag
        }
    }
}

// MARK: - Presets

enum BlackjackEdgePreset: String, CaseIterable, Identifiable {
    case basicStrategy
    case typicalPlayer
    case loosePlayer
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .basicStrategy: return "Basic strategy (~0.5%)"
        case .typicalPlayer: return "Typical player (~1.5%)"
        case .loosePlayer: return "Loose play (~2.5%)"
        case .custom: return "Custom %"
        }
    }

    var edgePercent: Double? {
        switch self {
        case .basicStrategy: return 0.5
        case .typicalPlayer: return 1.5
        case .loosePlayer: return 2.5
        case .custom: return nil
        }
    }
}

enum BaccaratBetPreset: String, CaseIterable, Identifiable {
    case banker
    case player
    case tie
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .banker: return "Banker (~1.06%)"
        case .player: return "Player (~1.24%)"
        case .tie: return "Tie (~14.4%)"
        case .custom: return "Custom %"
        }
    }

    var edgePercent: Double? {
        switch self {
        case .banker: return 1.06
        case .player: return 1.24
        case .tie: return 14.4
        case .custom: return nil
        }
    }
}

enum RouletteWheelPreset: String, CaseIterable, Identifiable {
    case american
    case european
    case frenchLaPartage
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .american: return "American 0/00 (5.26%)"
        case .european: return "European 0 (2.70%)"
        case .frenchLaPartage: return "French + La Partage (~1.35%)"
        case .custom: return "Custom %"
        }
    }

    var edgePercent: Double? {
        switch self {
        case .american: return 5.26
        case .european: return 2.70
        case .frenchLaPartage: return 1.35
        case .custom: return nil
        }
    }
}

enum CrapsBetPreset: String, CaseIterable, Identifiable {
    case passPlusOdds
    case dontPassPlusOdds
    case passOnly
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .passPlusOdds: return "Pass + full Odds (~0.5%)"
        case .dontPassPlusOdds: return "Don't Pass + Odds (~0.46%)"
        case .passOnly: return "Pass line only (~1.41%)"
        case .custom: return "Custom %"
        }
    }

    var edgePercent: Double? {
        switch self {
        case .passPlusOdds: return 0.5
        case .dontPassPlusOdds: return 0.46
        case .passOnly: return 1.41
        case .custom: return nil
        }
    }
}
