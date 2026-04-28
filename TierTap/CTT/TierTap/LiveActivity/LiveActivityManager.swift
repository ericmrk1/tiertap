import ActivityKit
import Foundation

class LiveActivityManager {
    static let shared = LiveActivityManager()
    private var currentActivity: Activity<TimerActivityAttributes>?
    private init() {}

    func start(session: Session) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attrs = TimerActivityAttributes(sessionID: session.id.uuidString)
        let state = TimerActivityAttributes.ContentState(
            startTime: session.startTime, casino: session.casino,
            game: session.game, totalBuyIn: session.totalBuyIn,
            startingTierPoints: session.startingTierPoints,
            rewardsProgramName: session.rewardsProgramName)
        do {
            currentActivity = try Activity.request(
                attributes: attrs,
                content: ActivityContent(state: state, staleDate: nil))
        } catch { print("LiveActivity error: \(error)") }
    }

    func update(totalBuyIn: Int) {
        guard let a = currentActivity else { return }
        let state = TimerActivityAttributes.ContentState(
            startTime: a.content.state.startTime,
            casino: a.content.state.casino,
            game: a.content.state.game,
            totalBuyIn: totalBuyIn,
            startingTierPoints: a.content.state.startingTierPoints,
            rewardsProgramName: a.content.state.rewardsProgramName)
        Task { await a.update(ActivityContent(state: state, staleDate: nil)) }
    }

    func update(for session: Session) {
        guard let a = currentActivity else { return }
        let state = TimerActivityAttributes.ContentState(
            startTime: session.startTime,
            casino: session.casino,
            game: session.game,
            totalBuyIn: session.totalBuyIn,
            startingTierPoints: session.startingTierPoints,
            rewardsProgramName: session.rewardsProgramName
        )
        Task { await a.update(ActivityContent(state: state, staleDate: nil)) }
    }

    func end() {
        Task { await currentActivity?.end(dismissalPolicy: .immediate); currentActivity = nil }
    }
}
