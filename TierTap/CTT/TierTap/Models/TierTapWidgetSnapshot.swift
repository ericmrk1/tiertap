import Foundation

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
    }

    let updatedAt: Date
    let currencySymbol: String
    let primaryColorHex: String?
    let isLiveSession: Bool
    let liveSessionStartTime: Date?
    /// Session timer when live, or formatted last-session duration when idle.
    let sessionMetricTitle: String
    let sessionMetricValue: String
    let sessionMetricTrend: MetricTrend?
    let metrics: [Metric]
}

enum TierTapWidgetIntentRouter {
    enum Destination: String {
        case checkIn
        case live
        case analytics
        case history
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

enum TierTapWidgetSnapshotStore {
    static let appGroupSuiteName = "group.com.app.tiertap"
    static let snapshotKey = "ctt_home_widget_snapshot"
    static let analyticsUseEVKey = "ctt_analytics_use_expected_value"
    static let currencyCodeKey = "ctt_currency_code"
    static let bankrollKey = "ctt_bankroll"

    static func load() -> TierTapHomeWidgetSnapshot? {
        guard let data = UserDefaults(suiteName: appGroupSuiteName)?.data(forKey: snapshotKey),
              !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(TierTapHomeWidgetSnapshot.self, from: data)
    }

    static func save(_ snapshot: TierTapHomeWidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults(suiteName: appGroupSuiteName)?.set(data, forKey: snapshotKey)
    }

    static func currencySymbol(from code: String) -> String {
        let locale = Locale(identifier: Locale.identifier(fromComponents: [NSLocale.Key.currencyCode.rawValue: code]))
        return locale.currencySymbol ?? "$"
    }
}
