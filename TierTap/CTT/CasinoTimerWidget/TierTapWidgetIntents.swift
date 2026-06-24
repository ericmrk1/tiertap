import AppIntents
import Foundation

/// Interactive widget actions (iOS 17+). Each intent opens the app to the matching screen.
@available(iOS 17.0, *)
struct TierTapOpenCheckInIntent: AppIntent {
    static var title: LocalizedStringResource = "Check In"
    static var description = IntentDescription("Start a new TierTap session.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        TierTapWidgetIntentRouter.destination = .checkIn
        return .result()
    }
}

@available(iOS 17.0, *)
struct TierTapOpenLiveIntent: AppIntent {
    static var title: LocalizedStringResource = "Live Session"
    static var description = IntentDescription("Open your live TierTap session.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        TierTapWidgetIntentRouter.destination = .live
        return .result()
    }
}

@available(iOS 17.0, *)
struct TierTapOpenAnalyticsIntent: AppIntent {
    static var title: LocalizedStringResource = "Analytics"
    static var description = IntentDescription("Open TierTap analytics and charts.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        TierTapWidgetIntentRouter.destination = .analytics
        return .result()
    }
}

@available(iOS 17.0, *)
struct TierTapOpenHistoryIntent: AppIntent {
    static var title: LocalizedStringResource = "History"
    static var description = IntentDescription("Open TierTap session history.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        TierTapWidgetIntentRouter.destination = .history
        return .result()
    }
}

@available(iOS 17.0, *)
struct TierTapWidgetShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TierTapOpenCheckInIntent(),
            phrases: [
                "Check in with \(.applicationName)",
                "Start a session in \(.applicationName)"
            ],
            shortTitle: "Check In",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: TierTapOpenAnalyticsIntent(),
            phrases: [
                "Show \(.applicationName) analytics",
                "Open analytics in \(.applicationName)"
            ],
            shortTitle: "Analytics",
            systemImageName: "chart.pie.fill"
        )
    }
}
