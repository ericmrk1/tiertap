import Foundation

/// Gamification level (1–100) derived from sessions logged, tier-point success, and rated/actual bet quality.
/// Session count is on a scale of 10,000 with milestone batches, each with a distinct emoji.
struct TapLevel {
    let level: Int
    let emoji: String
    let title: String
    let rawScore: Int
    let progressToNext: Double // 0...1, or 1.0 when at max level

    /// Completed (non-live) session count; used for session-scale gamification up to 10,000.
    let sessionCount: Int
    /// Emoji for the highest session milestone the user has achieved (batch on scale of 10,000).
    let sessionMilestoneEmoji: String
    /// Label for that milestone, e.g. "50 sessions".
    let sessionMilestoneLabel: String

    static let maxLevel = 100

    /// Session milestones on a scale of 10,000; each batch has a unique emoji.
    static let sessionMilestones: [(sessions: Int, emoji: String, label: String)] = [
        (1, "🎰", "1 session"),
        (5, "🃏", "5 sessions"),
        (10, "🎲", "10 sessions"),
        (25, "💰", "25 sessions"),
        (50, "🪙", "50 sessions"),
        (100, "♠️", "100 sessions"),
        (250, "♥️", "250 sessions"),
        (500, "♦️", "500 sessions"),
        (1_000, "♣️", "1,000 sessions"),
        (2_500, "🎯", "2,500 sessions"),
        (5_000, "⭐", "5,000 sessions"),
        (10_000, "🏆", "10,000 sessions")
    ]

    static let sessionScaleMax = 10_000

    /// Level 1–10: getting started; 11–20: building; 21–30: consistent; 31–50: strong; 51–75: expert; 76–100: elite
    private static let emojiBands: [(range: ClosedRange<Int>, emojis: [String])] = [
        (1...10,   ["🎰", "🃏", "🎲", "💰", "🪙", "♠️", "♥️", "♦️", "♣️", "🎯"]),
        (11...20,  ["⭐", "🌟", "✨", "💫", "🔥", "🏆", "🥇", "🎖️", "👑", "💎"]),
        (21...30,  ["🚀", "🌙", "☀️", "⚡", "🌊", "🎪", "🎭", "🎬", "🎤", "🎵"]),
        (31...40,  ["🦁", "🐲", "🦅", "🐺", "🦊", "🐯", "🐻", "🦈", "🐉", "🦅"]),
        (41...50,  ["🏅", "🎗️", "🎫", "🧿", "🔮", "⭐", "🌟", "💠", "🔷", "🔶"]),
        (51...60,  ["👾", "🤖", "🛸", "⚙️", "🔧", "🧲", "💡", "🔦", "📡", "🛡️"]),
        (61...70,  ["🌍", "🗺️", "🏔️", "🌋", "🏜️", "🌅", "🌈", "🌀", "❄️", "🌸"]),
        (71...80,  ["🎺", "🎷", "🥁", "🎸", "🎹", "🎻", "🪗", "🪕", "🎼", "🎵"]),
        (81...90,  ["👑", "🏰", "⚔️", "🛡️", "🗡️", "🏹", "🪓", "🔱", "⚜️", "👑"]),
        (91...100, ["💎", "🌟", "✨", "🔥", "👑", "🏆", "💫", "🎯", "⚡", "🎰"])
    ]

    static func emoji(for level: Int) -> String {
        let clamped = min(max(1, level), maxLevel)
        for band in emojiBands {
            if band.range.contains(clamped) {
                let index = clamped - band.range.lowerBound
                return band.emojis[index % band.emojis.count]
            }
        }
        return "🎰"
    }

    static func title(for level: Int) -> String {
        let l = min(max(1, level), maxLevel)
        switch l {
        case 1...5:   return "Starter"
        case 6...10:  return "Rookie"
        case 11...20: return "Regular"
        case 21...30: return "Consistent"
        case 31...40: return "Sharp"
        case 41...50: return "Pro"
        case 51...60: return "Veteran"
        case 61...70: return "Expert"
        case 71...80: return "Elite"
        case 81...90: return "Master"
        default:      return "Legend"
        }
    }

    /// Level bands for the levels explainer sheet: range, title, short description.
    static let levelBandsForExplainer: [(range: ClosedRange<Int>, title: String, description: String)] = [
        (1...5,   "Starter",   "Your first sessions. Log games and close out with tier points and avg bet (actual & rated) to earn score and level up."),
        (6...10,  "Rookie",    "Building a habit. Each completed session and each session where you gain tier points or log bet sizes adds to your level."),
        (11...20, "Regular",   "You’re logging consistently. Level grows from sessions logged, tier-point gains, and sessions with rated/actual bet in line."),
        (21...30, "Consistent", "Steady tracking pays off. More sessions and more tier-success sessions push you into higher levels."),
        (31...40, "Sharp",     "Strong engagement. Keep closing sessions with ending tier and bet data to climb into Pro."),
        (41...50, "Pro",       "You’re a pro at tracking. Level is driven by session count, tier gains, and rated/actual bet alignment."),
        (51...60, "Veteran",   "Lots of history. Every session and every tier gain still counts toward the next level."),
        (61...70, "Expert",   "Expert-level tracking. Nearing the top tiers; keep logging and closing out fully."),
        (71...80, "Elite",     "Elite status. Only a fraction of users reach here. Tier gains and full closeouts matter most."),
        (81...90, "Master",    "Master tier. You’ve logged and improved tier and bet stats across many sessions."),
        (91...100, "Legend",   "Legend. Max level. You’ve hit Tap Level 100 through sessions logged, tier success, and solid rated/actual bet tracking.")
    ]

    /// Raw score from completed sessions: sessions * 3 + tier-gain sessions * 5 + rated/actual aligned * 2
    static func rawScore(from sessions: [Session]) -> Int {
        let completed = sessions.filter { $0.isComplete && !$0.isLive }
        let sessionCount = completed.count
        let tierGainCount = completed.filter { ($0.tierPointsEarned ?? 0) > 0 }.count
        let ratedActualAligned = completed.filter { session in
            guard let rated = session.avgBetRated, let actual = session.avgBetActual, rated > 0 else { return false }
            return Double(actual) >= Double(rated) * 0.5
        }.count
        return sessionCount * 3 + tierGainCount * 5 + ratedActualAligned * 2
    }

    /// Level 1–100 from raw score using a curve (early levels faster).
    static func level(fromRawScore score: Int) -> Int {
        guard score > 0 else { return 1 }
        let level = 1 + Int(sqrt(Double(score)) * 4)
        return min(level, maxLevel)
    }

    /// Required raw score at the start of a level (so we can compute progress).
    static func rawScoreRequired(forLevel level: Int) -> Double {
        guard level > 1 else { return 0 }
        let t = Double(level - 1) / 4.0
        return t * t
    }

    /// Highest session milestone achieved for a given session count (emoji and label).
    static func sessionMilestone(forSessionCount count: Int) -> (emoji: String, label: String) {
        let achieved = sessionMilestones.last { count >= $0.sessions }
        if let m = achieved {
            return (m.emoji, m.label)
        }
        return (sessionMilestones[0].emoji, "0 sessions")
    }

    static func compute(from sessions: [Session]) -> TapLevel {
        let completed = sessions.filter { $0.isComplete && !$0.isLive }
        let sessionCount = completed.count
        let (milestoneEmoji, milestoneLabel) = sessionMilestone(forSessionCount: sessionCount)

        let score = rawScore(from: sessions)
        let lvl = level(fromRawScore: score)
        let currentThreshold = rawScoreRequired(forLevel: lvl)
        let nextThreshold = lvl >= maxLevel ? currentThreshold : rawScoreRequired(forLevel: lvl + 1)
        let progressToNext: Double
        if lvl >= maxLevel {
            progressToNext = 1.0
        } else {
            let span = nextThreshold - currentThreshold
            progressToNext = span > 0 ? min(1.0, max(0, (Double(score) - currentThreshold) / span)) : 0
        }
        return TapLevel(
            level: lvl,
            emoji: emoji(for: lvl),
            title: title(for: lvl),
            rawScore: score,
            progressToNext: progressToNext,
            sessionCount: sessionCount,
            sessionMilestoneEmoji: milestoneEmoji,
            sessionMilestoneLabel: milestoneLabel
        )
    }
}
