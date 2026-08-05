import Foundation

/// Selectable metrics for home screen widget layouts.
enum TierTapWidgetMetricKind: String, Codable, CaseIterable, Identifiable {
    case session
    case bankroll
    case today
    case winRate
    case lastTier
    case runningPL
    case buyIn
    case tapLevel

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .session: return "Session"
        case .bankroll: return "Bankroll"
        case .today: return "Today"
        case .winRate: return "Win Rate"
        case .lastTier: return "Last Tier"
        case .runningPL: return "Running P/L"
        case .buyIn: return "Buy-In"
        case .tapLevel: return "Tap Level"
        }
    }

    /// Deep link / icon identifier (`timer` for session).
    var linkMetricId: String {
        switch self {
        case .session: return "timer"
        case .bankroll: return "bankroll"
        case .today: return "today"
        case .winRate: return "winRate"
        case .lastTier: return "tier"
        case .runningPL, .buyIn: return "runningPL"
        case .tapLevel: return "tapLevel"
        }
    }
}

struct TierTapWidgetLayoutConfig: Codable, Equatable {
    /// Two metrics shown on the small widget (stacked, full width).
    var smallMetrics: [TierTapWidgetMetricKind]
    /// Up to four metrics on medium and large widgets (after session row when session is included).
    var standardMetrics: [TierTapWidgetMetricKind]

    static let `default` = TierTapWidgetLayoutConfig(
        smallMetrics: [.bankroll, .winRate],
        standardMetrics: [.session, .bankroll, .today, .lastTier]
    )

    static let smallSlotCount = 2
    static let standardSlotCount = 4

    static func normalized(_ config: TierTapWidgetLayoutConfig) -> TierTapWidgetLayoutConfig {
        TierTapWidgetLayoutConfig(
            smallMetrics: padded(config.smallMetrics, count: smallSlotCount, default: .bankroll),
            standardMetrics: padded(config.standardMetrics, count: standardSlotCount, default: .session)
        )
    }

    private static func padded(
        _ values: [TierTapWidgetMetricKind],
        count: Int,
        default defaultKind: TierTapWidgetMetricKind
    ) -> [TierTapWidgetMetricKind] {
        var result = Array(values.prefix(count))
        while result.count < count {
            result.append(defaultKind)
        }
        return result
    }
}

/// Shared App Group payload for the TierTap home screen widget.
struct TierTapHomeWidgetSnapshot: Codable, Equatable {
    enum MetricTrend: String, Codable {
        case up
        case down
        case flat
    }

    struct Metric: Codable, Equatable {
        let title: String
        let value: String
        let metricId: String
        let trend: MetricTrend?
        let chartPoints: [Int]
        let subtitle: String?
    }

    let updatedAt: Date
    let currencySymbol: String
    let primaryColorHex: String?
    let secondaryColorHex: String?
    let layoutConfig: TierTapWidgetLayoutConfig
    let isLiveSession: Bool
    let liveSessionStartTime: Date?
    let liveCasino: String?
    let liveGame: String?
    let sessionMetricTitle: String
    let sessionMetricValue: String
    let sessionMetricSubtitle: String?
    let sessionMetricTrend: MetricTrend?
    let sessionChartPoints: [Int]
    /// All buildable metrics keyed by `TierTapWidgetMetricKind.rawValue`.
    let metricCatalog: [String: Metric]
    let tapLevel: Int
    let tapLevelEmoji: String
    let tapLevelTitle: String
    let tapLevelProgress: Double
    let lastPlayedLabel: String?
    let recentDayNets: [Int]
    let cumulativeOutcomes: [Int]
    /// Recent closed sessions for the sessions ticker widget (newest first).
    let recentSessions: [TierTapWidgetRecentSession]?
    /// Wallet cards with a tier goal — for the Rewards Goals widget.
    let tierGoals: [TierTapWidgetTierGoal]?

    func metric(for kind: TierTapWidgetMetricKind) -> Metric? {
        if kind == .session {
            return Metric(
                title: sessionMetricTitle,
                value: isLiveSession ? "Live" : sessionMetricValue,
                metricId: "timer",
                trend: sessionMetricTrend,
                chartPoints: sessionChartPoints,
                subtitle: sessionMetricSubtitle
            )
        }
        return metricCatalog[kind.rawValue]
    }

    func smallDisplayMetrics() -> [Metric] {
        layoutConfig.smallMetrics.compactMap { metric(for: $0) }
    }

    func standardDisplayMetrics() -> [Metric] {
        layoutConfig.standardMetrics.compactMap { metric(for: $0) }
    }
}

/// Compact session row for the recent-sessions home screen widget.
struct TierTapWidgetRecentSession: Codable, Equatable, Identifiable {
    let id: String
    let casino: String
    let game: String
    let timeLabel: String
    let winLossText: String?
    let tierPointsText: String?
    let isVerified: Bool
}

/// Wallet loyalty tier goal for home-screen widgets (circle progress).
struct TierTapWidgetTierGoal: Codable, Equatable, Identifiable {
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
}

enum TierTapWidgetIntentRouter {
    enum Destination: String {
        case checkIn
        case live
        case analytics
        case history
        case bankroll
        case wallet
        case home
    }

    private static let key = "ctt_widget_pending_destination"

    static var destination: Destination? {
        get {
            guard let raw = UserDefaults(suiteName: TierTapWidgetSnapshotStore.appGroupSuiteName)?.string(forKey: key) else { return nil }
            return Destination(rawValue: raw)
        }
        set {
            let defaults = UserDefaults(suiteName: TierTapWidgetSnapshotStore.appGroupSuiteName)
            if let newValue {
                defaults?.set(newValue.rawValue, forKey: key)
            } else {
                defaults?.removeObject(forKey: key)
            }
        }
    }

    static func consumePendingDestination() -> Destination? {
        guard let pending = destination else { return nil }
        destination = nil
        return pending
    }
}

enum TierTapWidgetSessionDetailRouter {
    private static let key = "ctt_widget_pending_session_detail"

    static var pendingSessionID: UUID? {
        get {
            guard let raw = UserDefaults(suiteName: TierTapWidgetSnapshotStore.appGroupSuiteName)?.string(forKey: key) else { return nil }
            return UUID(uuidString: raw)
        }
        set {
            let defaults = UserDefaults(suiteName: TierTapWidgetSnapshotStore.appGroupSuiteName)
            if let newValue {
                defaults?.set(newValue.uuidString, forKey: key)
            } else {
                defaults?.removeObject(forKey: key)
            }
        }
    }

    static func consumePendingSessionID() -> UUID? {
        guard let pending = pendingSessionID else { return nil }
        pendingSessionID = nil
        return pending
    }
}

enum TierTapWidgetSnapshotStore {
    static let appGroupSuiteName = "group.com.app.tiertap"
    static let snapshotKey = "ctt_home_widget_snapshot"
    static let analyticsUseEVKey = "ctt_analytics_use_expected_value"
    static let currencyCodeKey = "ctt_currency_code"
    static let bankrollKey = "ctt_bankroll"
    static let layoutConfigKey = "ctt_widget_layout_config"

    static func load() -> TierTapHomeWidgetSnapshot? {
        guard let data = UserDefaults(suiteName: appGroupSuiteName)?.data(forKey: snapshotKey),
              !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(TierTapHomeWidgetSnapshot.self, from: data)
    }

    static func save(_ snapshot: TierTapHomeWidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults(suiteName: appGroupSuiteName)?.set(data, forKey: snapshotKey)
    }

    static func loadLayoutConfig() -> TierTapWidgetLayoutConfig {
        guard let data = UserDefaults(suiteName: appGroupSuiteName)?.data(forKey: layoutConfigKey),
              let decoded = try? JSONDecoder().decode(TierTapWidgetLayoutConfig.self, from: data) else {
            return .default
        }
        return TierTapWidgetLayoutConfig.normalized(decoded)
    }

    static func saveLayoutConfig(_ config: TierTapWidgetLayoutConfig) {
        let normalized = TierTapWidgetLayoutConfig.normalized(config)
        guard let data = try? JSONEncoder().encode(normalized) else { return }
        UserDefaults(suiteName: appGroupSuiteName)?.set(data, forKey: layoutConfigKey)
    }

    static func currencySymbol(from code: String) -> String {
        let locale = Locale(identifier: Locale.identifier(fromComponents: [NSLocale.Key.currencyCode.rawValue: code]))
        return locale.currencySymbol ?? "$"
    }
}
