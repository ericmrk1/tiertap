import ActivityKit
import Foundation

class LiveActivityManager {
    static let shared = LiveActivityManager()
    private var currentActivity: Activity<TimerActivityAttributes>?
    private init() {}

    private func resolvedCurrencySymbol() -> String {
        let code = UserDefaults.standard.string(forKey: "ctt_currency_code") ?? "USD"
        return Currency.byCode(code).symbol
    }

    private func contentState(from session: Session) -> TimerActivityAttributes.ContentState {
        TimerActivityAttributes.ContentState(
            startTime: session.startTime,
            casino: session.casino,
            game: session.game,
            totalBuyIn: session.totalBuyIn,
            startingTierPoints: session.startingTierPoints,
            rewardsProgramName: session.rewardsProgramName,
            totalFreePlay: session.totalFreePlay,
            totalComp: session.totalComp,
            liveTrackedStackAmount: session.liveTrackedStackAmount,
            currencySymbol: resolvedCurrencySymbol(),
            isSlotsSession: session.isSlotsSession
        )
    }

    func start(session: Session) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attrs = TimerActivityAttributes(sessionID: session.id.uuidString)
        let state = contentState(from: session)
        do {
            currentActivity = try Activity.request(
                attributes: attrs,
                content: ActivityContent(state: state, staleDate: nil))
        } catch { print("LiveActivity error: \(error)") }
    }

    func update(for session: Session) {
        guard let a = currentActivity else { return }
        let state = contentState(from: session)
        Task { await a.update(ActivityContent(state: state, staleDate: nil)) }
    }

    func end() {
        Task { await currentActivity?.end(dismissalPolicy: .immediate); currentActivity = nil }
    }
}
