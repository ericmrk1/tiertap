import SwiftUI
#if os(watchOS)
import WatchKit
#endif

/// Queues and presents full-screen wallet tier-goal celebrations on Watch.
final class WatchTierGoalCelebrationController: ObservableObject {
    static let shared = WatchTierGoalCelebrationController()

    @Published private(set) var activeEvent: WatchTierGoalCompletionEvent?

    private var queue: [WatchTierGoalCompletionEvent] = []
    private var celebratedIDs: Set<String>
    private var lastKnownGoals: [String: WatchSyncedTierGoal] = [:]
    private var hasSeededBaseline = false
    private let defaults = UserDefaults(suiteName: WatchTierGoalSyncKeys.appGroupSuiteName)
        ?? .standard

    private init() {
        let stored = defaults.stringArray(forKey: WatchTierGoalSyncKeys.celebratedGoalIDsKey) ?? []
        celebratedIDs = Set(stored)
    }

    func installHandlers() {
        SessionSyncManager.shared.onTierGoalCompleted = { [weak self] event in
            self?.enqueue(event)
        }
        SessionSyncManager.shared.onTierGoalsReceived = { [weak self] goals in
            self?.handleGoalsUpdate(goals)
        }
        if let snap = WatchTierGoalSyncCodec.loadGoalsFromAppGroup() {
            handleGoalsUpdate(snap.goals)
        }
    }

    func enqueue(_ event: WatchTierGoalCompletionEvent) {
        // Deduplicate by goal id so a goal only buzzes once per completion era.
        guard !celebratedIDs.contains(event.goal.id) else { return }
        if activeEvent?.goal.id == event.goal.id { return }
        if queue.contains(where: { $0.goal.id == event.goal.id }) { return }

        markCelebrated(event.goal.id)
        lastKnownGoals[event.goal.id] = event.goal
        if activeEvent == nil {
            activeEvent = event
        } else {
            queue.append(event)
        }
    }

    func dismissActive() {
        activeEvent = nil
        if let next = queue.first {
            queue.removeFirst()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.activeEvent = next
            }
        }
    }

    private func handleGoalsUpdate(_ goals: [WatchSyncedTierGoal]) {
        let previous = lastKnownGoals
        lastKnownGoals = Dictionary(uniqueKeysWithValues: goals.map { ($0.id, $0) })

        // Allow a future re-celebration if the user raises the goal and climbs again.
        var celebratedChanged = false
        for goal in goals where !goal.isComplete {
            if celebratedIDs.remove(goal.id) != nil {
                celebratedChanged = true
            }
        }
        if celebratedChanged {
            persistCelebratedIDs()
        }

        if !hasSeededBaseline {
            hasSeededBaseline = true
            // Fresh watch install: treat already-complete goals as previously celebrated.
            if celebratedIDs.isEmpty {
                for goal in goals where goal.isComplete {
                    celebratedIDs.insert(goal.id)
                }
                persistCelebratedIDs()
            }
            return
        }

        // Fallback if the dedicated completion message was missed.
        for goal in goals where goal.isComplete {
            guard let prior = previous[goal.id], !prior.isComplete else { continue }
            enqueue(
                WatchTierGoalCompletionEvent(
                    goal: goal,
                    previousProgress: min(prior.progress, 0.98),
                    completedAt: Date().timeIntervalSince1970
                )
            )
        }
    }

    private func markCelebrated(_ goalID: String) {
        guard celebratedIDs.insert(goalID).inserted else { return }
        persistCelebratedIDs()
    }

    private func persistCelebratedIDs() {
        defaults.set(Array(celebratedIDs), forKey: WatchTierGoalSyncKeys.celebratedGoalIDsKey)
    }
}

/// Full-screen Watch overlay: ring animates from prior progress to 100% with a buzzing haptic.
struct WatchTierGoalCelebrationOverlay: View {
    let event: WatchTierGoalCompletionEvent
    var onDismiss: () -> Void

    @Environment(\.tierTapWatchAnimationsEnabled) private var animationsEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.watchTheme) private var theme

    @State private var animatedProgress: Double = 0
    @State private var showReachedLabel = false
    @State private var ringPulse = false

    private var motionOK: Bool { animationsEnabled && !reduceMotion }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.green.opacity(0.55),
                    theme.celebrationGradientLead,
                    Color.black.opacity(0.94)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 10) {
                Text(event.goal.programName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.18), lineWidth: 8)
                        .frame(width: 96, height: 96)

                    Circle()
                        .trim(from: 0, to: animatedProgress)
                        .stroke(
                            Color.green,
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 96, height: 96)
                        .scaleEffect(ringPulse ? 1.06 : 1.0)

                    Text("\(Int((animatedProgress * 100).rounded()))%")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }

                if showReachedLabel {
                    VStack(spacing: 4) {
                        Text("Goal reached")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                        Text(event.goal.celebrationTitle)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.cyan.opacity(0.95))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                        Text("\(event.goal.currentPoints) / \(event.goal.goalPoints) pts")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: onDismiss)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(event.goal.programName) goal reached. \(event.goal.celebrationTitle). 100 percent."
        )
        .onAppear(perform: runCelebration)
    }

    private func runCelebration() {
        let start = min(max(event.previousProgress, 0), 0.98)
        animatedProgress = motionOK ? start : 1
        showReachedLabel = !motionOK
        playBuzzHaptic(style: .notification)

        guard motionOK else {
            playBuzzHaptic(style: .success)
            scheduleAutoDismiss()
            return
        }

        // Tick haptics while the ring climbs, then a success buzz at 100%.
        let tickCount = 4
        for i in 1...tickCount {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.22) {
                playBuzzHaptic(style: .click)
            }
        }

        withAnimation(.easeOut(duration: 1.15)) {
            animatedProgress = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15) {
            playBuzzHaptic(style: .success)
            withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                showReachedLabel = true
                ringPulse = true
            }
            playBuzzHaptic(style: .notification)
            scheduleAutoDismiss()
        }
    }

    private func scheduleAutoDismiss() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.4) {
            onDismiss()
        }
    }

    private func playBuzzHaptic(style: BuzzStyle) {
        #if os(watchOS)
        let enabled = UserDefaults(suiteName: WatchTierGoalSyncKeys.appGroupSuiteName)?
            .object(forKey: "ctt_watch_haptics_enabled") as? Bool ?? true
        guard enabled else { return }
        let haptic: WKHapticType
        switch style {
        case .notification: haptic = .notification
        case .success: haptic = .success
        case .click: haptic = .click
        }
        WKInterfaceDevice.current().play(haptic)
        #endif
    }

    private enum BuzzStyle {
        case notification
        case success
        case click
    }
}
