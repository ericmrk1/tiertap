import Foundation

// MARK: - Risk of Ruin math
// References:
// - RoR (binary): ((1-edge)/(1+edge))^(bankroll/unit) for edge = expected return per unit
// - Session-based: (q/p)^(bankroll/unit) where p=P(win), q=P(loss) from session history

struct RiskOfRuinResult {
    /// Probability of losing entire bankroll (0...1)
    let riskOfRuin: Double
    /// Average win/loss per session from history ($)
    let actualAveragePerSession: Double?
    /// Target average per session from settings ($)
    let targetAveragePerSession: Double?
    /// Proportion of winning sessions (0...1)
    let winRate: Double?
    /// Number of closed sessions with valid win/loss
    let sessionCount: Int
    /// Whether current bet (e.g. buy-in or avg bet) exceeds recommended unit size
    let betExceedsTarget: Bool
    /// Recommended unit size from settings
    let recommendedUnitSize: Int
}

enum RiskOfRuinMath {

    /// Session-based Risk of Ruin: RoR = (q/p)^(bankroll/unit)
    /// where p = proportion of winning sessions, q = proportion of losing sessions.
    /// Assumes each "session" is one trial; bankroll and unit in same currency.
    static func sessionBasedRiskOfRuin(
        bankroll: Int,
        unitSize: Int,
        winningSessions: Int,
        losingSessions: Int,
        totalSessions: Int
    ) -> Double {
        guard unitSize > 0, bankroll > 0, totalSessions > 0 else { return 1.0 }
        let p = Double(winningSessions) / Double(totalSessions)
        let q = Double(losingSessions) / Double(totalSessions)
        if p <= 0 || p <= q { return 1.0 }
        let units = Double(bankroll) / Double(unitSize)
        let ror = pow(q / p, units)
        return min(1.0, max(0.0, ror))
    }

    /// Edge-based Risk of Ruin: RoR = ((1-edge)/(1+edge))^(bankroll/unit)
    /// edge = expected profit per unit per session (decimal). Negative edge → ruin certain.
    static func edgeBasedRiskOfRuin(
        bankroll: Int,
        unitSize: Int,
        edgePerUnitPerSession: Double
    ) -> Double {
        guard unitSize > 0, bankroll > 0 else { return 1.0 }
        if edgePerUnitPerSession <= 0 { return 1.0 }
        if edgePerUnitPerSession >= 1 { return 0.0 }
        let ratio = (1.0 - edgePerUnitPerSession) / (1.0 + edgePerUnitPerSession)
        let units = Double(bankroll) / Double(unitSize)
        let ror = pow(ratio, units)
        return min(1.0, max(0.0, ror))
    }

    /// Compute all RoR stats from session history and settings.
    static func compute(
        sessions: [Session],
        bankroll: Int,
        unitSize: Int,
        targetAveragePerSession: Double?,
        currentBetAmount: Int? = nil
    ) -> RiskOfRuinResult {
        // Exclude poker sessions (only use table games for RoR).
        let closed = sessions.filter { $0.winLoss != nil && $0.gameCategory != .poker }
        let wins = closed.filter { ($0.winLoss ?? 0) > 0 }.count
        let losses = closed.filter { ($0.winLoss ?? 0) < 0 }.count
        let total = closed.count

        let actualAvg: Double? = total > 0
            ? Double(closed.compactMap { $0.winLoss }.reduce(0, +)) / Double(total)
            : nil

        let sessionBasedRoR = sessionBasedRiskOfRuin(
            bankroll: bankroll,
            unitSize: unitSize > 0 ? unitSize : 1,
            winningSessions: wins,
            losingSessions: losses,
            totalSessions: total
        )

        var edgeBasedRoR = 1.0
        if let avg = actualAvg, unitSize > 0 {
            let edgePerUnit = avg / Double(unitSize)
            edgeBasedRoR = edgeBasedRiskOfRuin(
                bankroll: bankroll,
                unitSize: unitSize,
                edgePerUnitPerSession: edgePerUnit
            )
        }

        let winRate = total > 0 ? Double(wins) / Double(total) : nil
        let betExceeds = (currentBetAmount ?? 0) > 0 && unitSize > 0 && (currentBetAmount ?? 0) > unitSize
        let recommendedUnit = unitSize
        let finalRoR: Double
        if total >= 3 {
            finalRoR = sessionBasedRoR
        } else if total > 0, let _ = actualAvg, unitSize > 0 {
            finalRoR = edgeBasedRoR
        } else {
            finalRoR = 1.0
        }

        return RiskOfRuinResult(
            riskOfRuin: finalRoR,
            actualAveragePerSession: actualAvg,
            targetAveragePerSession: targetAveragePerSession,
            winRate: winRate,
            sessionCount: total,
            betExceedsTarget: betExceeds,
            recommendedUnitSize: recommendedUnit
        )
    }
}
