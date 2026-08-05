import SwiftUI

#if os(iOS)

private let kTapLevelLastKey = "ctt_tap_level_last"
private let kIPhoneCelebratedTierGoalIDsKey = "ctt_iphone_celebrated_tier_goal_ids"

private func tapLevelSaveLast(_ level: Int) {
    (UserDefaults(suiteName: WatchTierGoalSyncKeys.appGroupSuiteName) ?? .standard)
        .set(level, forKey: kTapLevelLastKey)
}

enum TierTapCelebration: Identifiable {
    case tapLevelUp(TapLevel)
    case tierGoal(WatchTierGoalCompletionEvent)

    var id: String {
        switch self {
        case .tapLevelUp(let tap):
            return "tap-level-\(tap.level)"
        case .tierGoal(let event):
            return event.id
        }
    }
}

/// Presents Tap Level and wallet tier-goal celebrations above every tab and sheet.
@MainActor
final class TierTapCelebrationController: ObservableObject {
    static let shared = TierTapCelebrationController()

    @Published private(set) var activeCelebration: TierTapCelebration?

    private var queue: [TierTapCelebration] = []
    private var lastComputedLevel: Int?
    private var celebratedTierGoalIDs: Set<String>
    private let defaults = UserDefaults(suiteName: WatchTierGoalSyncKeys.appGroupSuiteName) ?? .standard

    private init() {
        let stored = defaults.stringArray(forKey: kIPhoneCelebratedTierGoalIDsKey) ?? []
        celebratedTierGoalIDs = Set(stored)
    }

    func checkTapLevel(from sessions: [Session], liveSessionActive: Bool) {
        guard !liveSessionActive else { return }
        let tap = TapLevel.compute(from: sessions)
        if let prev = lastComputedLevel {
            if tap.level > prev {
                tapLevelSaveLast(tap.level)
                enqueue(.tapLevelUp(tap))
            }
            lastComputedLevel = tap.level
        } else {
            lastComputedLevel = tap.level
        }
    }

    func enqueueTierGoal(_ event: WatchTierGoalCompletionEvent) {
        guard !celebratedTierGoalIDs.contains(event.goal.id) else { return }
        markTierGoalCelebrated(event.goal.id)
        enqueue(.tierGoal(event))
    }

    /// Clears celebration memory for goals that are no longer complete (e.g. user raised the target).
    func noteTierGoalsSnapshot(_ goals: [WatchSyncedTierGoal]) {
        var changed = false
        for goal in goals where !goal.isComplete {
            if celebratedTierGoalIDs.remove(goal.id) != nil {
                changed = true
            }
        }
        guard changed else { return }
        defaults.set(Array(celebratedTierGoalIDs), forKey: kIPhoneCelebratedTierGoalIDsKey)
    }

    func dismissActive() {
        activeCelebration = nil
        if let next = queue.first {
            queue.removeFirst()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.activeCelebration = next
            }
        }
    }

    private func enqueue(_ celebration: TierTapCelebration) {
        if activeCelebration?.id == celebration.id { return }
        if queue.contains(where: { $0.id == celebration.id }) { return }

        if activeCelebration == nil {
            activeCelebration = celebration
        } else {
            queue.append(celebration)
        }
    }

    private func markTierGoalCelebrated(_ goalID: String) {
        guard celebratedTierGoalIDs.insert(goalID).inserted else { return }
        defaults.set(Array(celebratedTierGoalIDs), forKey: kIPhoneCelebratedTierGoalIDsKey)
    }
}

struct TierTapCelebrationScreen: View {
    let celebration: TierTapCelebration
    let onDismiss: () -> Void

    var body: some View {
        Group {
            switch celebration {
            case .tapLevelUp(let tapLevel):
                TapLevelLevelUpCelebrationView(tapLevel: tapLevel, onDismiss: onDismiss)
            case .tierGoal(let event):
                TierGoalCelebrationOverlay(event: event, onDismiss: onDismiss)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.001))
        .ignoresSafeArea()
    }
}

/// Full-screen level-up celebration: confetti, haptics, sound, and a pop-up card.
struct TapLevelLevelUpCelebrationView: View {
    let tapLevel: TapLevel
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
            ConfettiCelebrationView()
            VStack(spacing: 20) {
                Text(tapLevel.sessionMilestoneEmoji)
                    .font(.system(size: 56))
                Text(tapLevel.emoji)
                    .font(.system(size: 44))
                Text("Tap Level \(tapLevel.level)!")
                    .font(.title.bold())
                    .foregroundColor(.white)
                Text(tapLevel.title)
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.9))
                Button(action: onDismiss) {
                    L10nText("Awesome!")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.green)
                        .cornerRadius(14)
                }
                .padding(.horizontal, 40)
                .padding(.top, 8)
            }
            .padding(32)
            .background(Color(.systemGray6).opacity(0.95))
            .cornerRadius(24)
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.green.opacity(0.6), lineWidth: 2))
            .padding(40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .contentShape(Rectangle())
    }
}

/// Full-screen wallet tier-goal celebration on iPhone.
struct TierGoalCelebrationOverlay: View {
    let event: WatchTierGoalCompletionEvent
    let onDismiss: () -> Void

    @EnvironmentObject private var settingsStore: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var animatedProgress: Double = 0
    @State private var showReachedLabel = false
    @State private var ringPulse = false

    private var motionOK: Bool { !reduceMotion }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.green.opacity(0.55),
                    settingsStore.primaryColor.opacity(0.52),
                    Color.black.opacity(0.94)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ConfettiCelebrationView()

            VStack(spacing: 18) {
                Text(event.goal.programName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.18), lineWidth: 10)
                        .frame(width: 140, height: 140)

                    Circle()
                        .trim(from: 0, to: animatedProgress)
                        .stroke(
                            Color.green,
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 140, height: 140)
                        .scaleEffect(ringPulse ? 1.06 : 1.0)

                    Text("\(Int((animatedProgress * 100).rounded()))%")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }

                if showReachedLabel {
                    VStack(spacing: 8) {
                        Text("Goal reached")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                        Text(event.goal.celebrationTitle)
                            .font(.headline.weight(.medium))
                            .foregroundStyle(.cyan.opacity(0.95))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                        Text("\(event.goal.currentPoints) / \(event.goal.goalPoints) pts")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.78))
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }

                Button(action: onDismiss) {
                    L10nText("Awesome!")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.green)
                        .cornerRadius(14)
                }
                .padding(.horizontal, 48)
                .padding(.top, 8)
                .opacity(showReachedLabel ? 1 : 0)
            }
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
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

        guard motionOK else {
            scheduleAutoDismiss()
            return
        }

        withAnimation(.easeOut(duration: 1.15)) {
            animatedProgress = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15) {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                showReachedLabel = true
                ringPulse = true
            }
            scheduleAutoDismiss()
        }
    }

    private func scheduleAutoDismiss() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.4) {
            onDismiss()
        }
    }
}

#endif
