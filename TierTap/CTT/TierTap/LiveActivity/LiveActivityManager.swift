import ActivityKit
import Foundation

final class LiveActivityManager {
    static let shared = LiveActivityManager()
    private var currentActivity: Activity<TimerActivityAttributes>?
    private init() {}

    private var systemActivities: [Activity<TimerActivityAttributes>] {
        Activity<TimerActivityAttributes>.activities
    }

    /// Align lock screen / Dynamic Island with persisted app state (call after loading `liveSession`).
    func reconcile(liveSession: Session?) {
        Task { @MainActor in
            await reconcileNow(liveSession: liveSession)
        }
    }

    @MainActor
    private func reconcileNow(liveSession: Session?) async {
        if let session = liveSession {
            if let matching = systemActivities.first(where: { $0.attributes.sessionID == session.id.uuidString }) {
                currentActivity = matching
                await updateNow(for: session)
            } else {
                await endAllActivities()
                requestActivity(session: session)
            }
        } else {
            await endAllActivities()
        }
    }

    func start(session: Session) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        Task { @MainActor in
            await endAllActivities()
            requestActivity(session: session)
        }
    }

    func update(for session: Session) {
        Task { @MainActor in
            await updateNow(for: session)
        }
    }

    @MainActor
    private func updateNow(for session: Session) async {
        if currentActivity == nil {
            currentActivity = systemActivities.first { $0.attributes.sessionID == session.id.uuidString }
        }
        guard let activity = currentActivity else {
            requestActivity(session: session)
            return
        }
        let state = contentState(from: session)
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }

    func end() {
        Task { @MainActor in
            await endAllActivities()
        }
    }

    @MainActor
    private func endAllActivities() async {
        let activities = systemActivities
        currentActivity = nil
        for activity in activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    @MainActor
    private func requestActivity(session: Session) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attrs = TimerActivityAttributes(sessionID: session.id.uuidString)
        let state = contentState(from: session)
        do {
            currentActivity = try Activity.request(
                attributes: attrs,
                content: ActivityContent(state: state, staleDate: nil))
        } catch { print("LiveActivity error: \(error)") }
    }

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
            isSlotsSession: session.isSlotsSession,
            timerPausedAt: session.endTime
        )
    }
}
