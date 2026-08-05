import Foundation

/// Gamification level (1–1000) derived from sessions logged, tier-point success, and rated/actual bet quality.
/// Each level requires 50 more raw score than the previous. Session count is on a scale of 10,000 with milestone batches.
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

    static let maxLevel = 1000

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

    /// Level 1–1000 in bands of 100 for emoji variety.
    private static let emojiBands: [(range: ClosedRange<Int>, emojis: [String])] = [
        (1...100,    ["🎰", "🃏", "🎲", "💰", "🪙", "♠️", "♥️", "♦️", "♣️", "🎯"]),
        (101...200,  ["⭐", "🌟", "✨", "💫", "🔥", "🏆", "🥇", "🎖️", "👑", "💎"]),
        (201...300,  ["🚀", "🌙", "☀️", "⚡", "🌊", "🎪", "🎭", "🎬", "🎤", "🎵"]),
        (301...400,  ["🦁", "🐲", "🦅", "🐺", "🦊", "🐯", "🐻", "🦈", "🐉", "🦅"]),
        (401...500,  ["🏅", "🎗️", "🎫", "🧿", "🔮", "⭐", "🌟", "💠", "🔷", "🔶"]),
        (501...600,  ["👾", "🤖", "🛸", "⚙️", "🔧", "🧲", "💡", "🔦", "📡", "🛡️"]),
        (601...700,  ["🌍", "🗺️", "🏔️", "🌋", "🏜️", "🌅", "🌈", "🌀", "❄️", "🌸"]),
        (701...800,  ["🎺", "🎷", "🥁", "🎸", "🎹", "🎻", "🪗", "🪕", "🎼", "🎵"]),
        (801...900,   ["👑", "🏰", "⚔️", "🛡️", "🗡️", "🏹", "🪓", "🔱", "⚜️", "👑"]),
        (901...1000, ["💎", "🌟", "✨", "🔥", "👑", "🏆", "💫", "🎯", "⚡", "🎰"])
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
        case 1...100:    return "Starter"
        case 101...200:  return "Rookie"
        case 201...300:  return "Regular"
        case 301...400:  return "Consistent"
        case 401...500:  return "Sharp"
        case 501...600:  return "Pro"
        case 601...700:  return "Veteran"
        case 701...800:  return "Expert"
        case 801...900:  return "Elite"
        default:         return "Legend"
        }
    }

    /// Level bands for the levels explainer sheet: range, title, short description. Scale 1–1000, 50 raw score per level.
    static let levelBandsForExplainer: [(range: ClosedRange<Int>, title: String, description: String)] = [
        (1...100,    "Starter",   "Your first sessions. Log games and close out with tier points and avg bet (actual & rated) to earn score. Each level needs 50 more raw score."),
        (101...200,  "Rookie",    "Building a habit. Each completed session and each session where you gain tier points or log bet sizes adds to your level."),
        (201...300,  "Regular",   "You’re logging consistently. Level grows from sessions logged, tier-point gains, and sessions with rated/actual bet in line."),
        (301...400,  "Consistent", "Steady tracking pays off. More sessions and more tier-success sessions push you into higher levels."),
        (401...500,  "Sharp",     "Strong engagement. Keep closing sessions with ending tier and bet data to climb into Pro."),
        (501...600,  "Pro",       "You’re a pro at tracking. Level is driven by session count, tier gains, and rated/actual bet alignment."),
        (601...700,  "Veteran",   "Lots of history. Every session and every tier gain still counts toward the next level."),
        (701...800,  "Expert",   "Expert-level tracking. Nearing the top tiers; keep logging and closing out fully."),
        (801...900,  "Elite",     "Elite status. Only a fraction of users reach here. Tier gains and full closeouts matter most."),
        (901...1000, "Legend",   "Legend. Max level. You've hit Tap Level 1000 through sessions logged, tier success, and solid rated/actual bet tracking.")
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

    /// Level 1–1000 from raw score. Each level requires 50 more raw score than the previous (linear).
    static func level(fromRawScore score: Int) -> Int {
        guard score > 0 else { return 1 }
        let level = 1 + score / 50
        return min(level, maxLevel)
    }

    /// Required raw score at the start of a level (so we can compute progress). Level N starts at (N-1)*50.
    static func rawScoreRequired(forLevel level: Int) -> Double {
        guard level > 1 else { return 0 }
        return Double((level - 1) * 50)
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
