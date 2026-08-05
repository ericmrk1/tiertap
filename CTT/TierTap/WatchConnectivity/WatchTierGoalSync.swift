import Foundation

/// Compact wallet tier-goal snapshot shared between iPhone and Watch via WatchConnectivity / App Group.
struct WatchSyncedTierGoal: Codable, Equatable, Identifiable {
    let id: String
    let programName: String
    let goalLabel: String?
    let currentPoints: Int
    let goalPoints: Int

    var progress: Double {
        guard goalPoints > 0 else { return 0 }
        return min(1, max(0, Double(currentPoints) / Double(goalPoints)))
    }

    var pointsRemaining: Int {
        max(0, goalPoints - currentPoints)
    }

    var isComplete: Bool {
        pointsRemaining == 0 && goalPoints > 0
    }

    var celebrationTitle: String {
        if let goalLabel, !goalLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return goalLabel
        }
        return programName
    }
}

/// Fired when a wallet card's tier points cross its goal threshold.
struct WatchTierGoalCompletionEvent: Codable, Equatable, Identifiable {
    let goal: WatchSyncedTierGoal
    let previousProgress: Double
    let completedAt: TimeInterval

    var id: String { "\(goal.id)-\(Int(completedAt * 1000))" }
}

enum WatchTierGoalSyncKeys {
    static let appGroupSuiteName = "group.com.app.tiertap"
    static let goalsSnapshotKey = "ctt_wc_tier_goals_snapshot"
    static let goalsRevisionKey = "ctt_wc_tier_goals_revision"
    static let goalsUpdatedAtKey = "ctt_wc_tier_goals_updated_at"
    static let contextPayloadKey = "tierGoals"
    static let completionEventKey = "tierGoalCompleted"
    static let eventTypeKey = "event"
    static let eventPayloadKey = "payload"
    static let eventTypeTierGoalCompleted = "tierGoalCompleted"
    /// Watch-local: goal IDs already celebrated (avoid replaying on first sync).
    static let celebratedGoalIDsKey = "ctt_watch_celebrated_tier_goal_ids"
}

enum WatchTierGoalSyncCodec {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func encodeGoals(_ goals: [WatchSyncedTierGoal]) -> Data? {
        try? encoder.encode(goals)
    }

    static func decodeGoals(from data: Data?) -> [WatchSyncedTierGoal]? {
        guard let data, !data.isEmpty else { return nil }
        return try? decoder.decode([WatchSyncedTierGoal].self, from: data)
    }

    static func encodeCompletion(_ event: WatchTierGoalCompletionEvent) -> Data? {
        try? encoder.encode(event)
    }

    static func decodeCompletion(from data: Data?) -> WatchTierGoalCompletionEvent? {
        guard let data, !data.isEmpty else { return nil }
        return try? decoder.decode(WatchTierGoalCompletionEvent.self, from: data)
    }

    static func loadGoalsFromAppGroup(
        suiteName: String = WatchTierGoalSyncKeys.appGroupSuiteName
    ) -> (goals: [WatchSyncedTierGoal], revision: Int)? {
        guard let group = UserDefaults(suiteName: suiteName) else { return nil }
        let revision = group.integer(forKey: WatchTierGoalSyncKeys.goalsRevisionKey)
        guard revision > 0,
              let data = group.data(forKey: WatchTierGoalSyncKeys.goalsSnapshotKey),
              let goals = decodeGoals(from: data) else {
            return nil
        }
        return (goals, revision)
    }

    static func persistGoalsToAppGroup(
        _ goals: [WatchSyncedTierGoal],
        suiteName: String = WatchTierGoalSyncKeys.appGroupSuiteName
    ) {
        guard let group = UserDefaults(suiteName: suiteName),
              let data = encodeGoals(goals) else { return }
        group.set(data, forKey: WatchTierGoalSyncKeys.goalsSnapshotKey)
        let rev = group.integer(forKey: WatchTierGoalSyncKeys.goalsRevisionKey) + 1
        group.set(rev, forKey: WatchTierGoalSyncKeys.goalsRevisionKey)
        group.set(Date().timeIntervalSince1970, forKey: WatchTierGoalSyncKeys.goalsUpdatedAtKey)
    }
}
