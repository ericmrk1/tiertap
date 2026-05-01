import SwiftUI
#if os(watchOS)
import WatchKit
#endif

struct WatchVisualsView: View {
    @EnvironmentObject var store: SessionStore
    @ObservedObject private var syncManager = SessionSyncManager.shared
    @State private var chipAmount: Double = 100
    @State private var selectedCard: VisualCard = .chipStack
    @State private var pendingMessage: String?
    @State private var lastAutoScrollAt: Date = .distantPast
    private let autoScrollTicker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let groupDefaults = UserDefaults(suiteName: "group.com.app.tiertap")

    private var live: Session? { store.liveSession }
    private var hasLiveSession: Bool { live != nil }
    private var isSessionPaused: Bool { live?.endTime != nil }

    private var selectedChipAmount: Int {
        max(5, Int(chipAmount))
    }

    private var netPosition: Int {
        live?.winLoss ?? 0
    }

    private var pulseColor: Color {
        let value = netPosition
        if value > 0 { return .green }
        if value < 0 { return .red }
        return .yellow
    }

    private var buyIns: Int { live?.totalBuyIn ?? 0 }
    private var rebuys: Int { max(0, buyIns - (live?.initialBuyIn ?? buyIns)) }
    private var comps: Int { live?.totalComp ?? 0 }

    var body: some View {
        TabView(selection: $selectedCard) {
            chipStackCard
                .tag(VisualCard.chipStack)

            circularTimerCard
                .tag(VisualCard.timer)

            pulseDashboardCard
                .tag(VisualCard.pulse)

            swipeableActionsCard
                .tag(VisualCard.actions)
        }
        .tabViewStyle(.page)
        .indexViewStyle(.page(backgroundDisplayMode: .automatic))
        .localizedNavigationTitle("Visuals")
        .onAppear {
            lastAutoScrollAt = Date()
            SessionSyncManager.shared.requestContext { sessions, liveSession in
                DispatchQueue.main.async {
                    store.applySyncedState(sessions: sessions, liveSession: liveSession)
                }
            }
        }
        .onReceive(autoScrollTicker) { now in
            guard visualsAutoScrollEnabled else { return }
            guard now.timeIntervalSince(lastAutoScrollAt) >= Double(visualsAutoScrollSeconds) else { return }
            lastAutoScrollAt = now
            selectedCard = selectedCard.next
        }
    }

    private var chipStackCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Buy-In")
                .font(.caption2)
                .foregroundColor(.green)

            Text("$\(buyIns.formatted(.number.grouping(.automatic)))")
                .font(.title3.monospacedDigit().bold())

            ZStack {
                ForEach(0..<4, id: \.self) { idx in
                    casinoChip(
                        diameter: 42 + CGFloat(idx * 8),
                        color: chipColor(for: idx),
                        denomination: chipDenomination(for: idx),
                        useDarkLabel: idx == 3
                    )
                        .offset(y: CGFloat((3 - idx) * 4))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 74)

            Text("Chip: $\(selectedChipAmount)")
                .font(.caption2)
                .foregroundColor(.secondary)

            Button("Add Chips") {
                guard hasLiveSession else {
                    pendingMessage = "Start a live session on iPhone first"
                    playConfiguredHaptic(style: .queue)
                    return
                }
                let immediate = syncManager.isReachable
                store.addBuyIn(selectedChipAmount)
                pendingMessage = immediate ? "Buy-in sent" : "Buy-in queued"
                playConfiguredHaptic(style: immediate ? .success : .queue)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)

            if let pendingMessage {
                Text(pendingMessage)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .focusable(true)
        .digitalCrownRotation(
            $chipAmount,
            from: 5,
            through: 2000,
            by: 5,
            sensitivity: .low,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
    }

    private var circularTimerCard: some View {
        TimelineView(.animation(minimumInterval: 1.0, paused: !hasLiveSession || isSessionPaused)) { context in
            let elapsed = liveElapsedSeconds(at: context.date)
            let progress = timerProgress(elapsed: elapsed)

            VStack(spacing: 8) {
                Text("Session")
                    .font(.caption2)
                    .foregroundColor(.green)

                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.25), lineWidth: 9)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            AngularGradient(colors: [.green, .yellow, .orange, .red], center: .center),
                            style: StrokeStyle(lineWidth: 9, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 2) {
                        Text(Session.durationString(elapsed))
                            .font(.headline.monospacedDigit().bold())
                        Text("ELAPSED")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 128, height: 128)

                Text("Scrub timeline by swiping cards")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(10)
        }
    }

    private var pulseDashboardCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Live")
                    .font(.caption2)
                    .foregroundColor(.green)
                Spacer()
                Circle()
                    .fill(pulseColor)
                    .frame(width: 10, height: 10)
            }

            if hasLiveSession {
                Text("$\(netPosition >= 0 ? "+" : "")\(netPosition.formatted(.number.grouping(.automatic)))")
                    .font(.title2.monospacedDigit().bold())
                    .foregroundColor(pulseColor)
                Text("Net position")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Text("--")
                    .font(.title2.monospacedDigit().bold())
                Text("No live session")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 6) {
                miniMetric(title: "Buy-Ins", value: "$\(buyIns)")
                miniMetric(title: "Re-Buys", value: "$\(rebuys)")
                miniMetric(title: "Comps", value: "$\(comps)")
            }
        }
        .padding(10)
    }

    private var swipeableActionsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Cards")
                .font(.caption2)
                .foregroundColor(.green)

            TabView {
                quickActionCard(title: "COMPS", value: "$\(comps)", tint: .cyan) {
                    store.addComp(amount: 20, kind: .dollarsCredits, details: "Visuals quick add")
                    pendingMessage = syncManager.isReachable ? "Comp sent" : "Comp queued"
                }
                quickActionCard(title: "BUY-IN", value: "$\(buyIns)", tint: .blue) {
                    store.addBuyIn(100)
                    pendingMessage = syncManager.isReachable ? "Buy-in sent" : "Buy-in queued"
                }
                quickActionCard(title: "TIER", value: "\(live?.startingTierPoints ?? 0)", tint: .purple) {
                    let updated = (live?.startingTierPoints ?? 0) + 100
                    store.updateLiveSessionStartingTier(updated)
                    pendingMessage = syncManager.isReachable ? "Tier sent" : "Tier queued"
                }
            }
            .tabViewStyle(.page)
            .frame(height: 86)

            if let pendingMessage {
                Text(pendingMessage)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(10)
    }

    private func quickActionCard(
        title: String,
        value: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.headline.monospacedDigit().bold())
                    .foregroundColor(tint)
                Text("Tap to send")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Color.gray.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!hasLiveSession)
    }

    private func miniMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.caption2.bold())
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(6)
        .background(Color.gray.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func chipColor(for index: Int) -> Color {
        switch index {
        case 0: return .red
        case 1: return .green
        case 2: return .purple
        default: return .white
        }
    }

    private func chipDenomination(for index: Int) -> Int {
        switch index {
        case 0: return 25
        case 1: return 100
        case 2: return 500
        default: return 1000
        }
    }

    private func casinoChip(
        diameter: CGFloat,
        color: Color,
        denomination: Int,
        useDarkLabel: Bool
    ) -> some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [color.opacity(0.95), color.opacity(0.75)],
                        center: .center,
                        startRadius: 2,
                        endRadius: diameter / 2
                    )
                )

            Circle()
                .stroke(Color.white.opacity(0.75), lineWidth: max(1, diameter * 0.045))

            Circle()
                .stroke(Color.black.opacity(0.35), lineWidth: max(1, diameter * 0.02))
                .padding(diameter * 0.08)

            // Edge ticks mimic real casino chip inlays.
            ForEach(0..<12, id: \.self) { tick in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white.opacity(0.9))
                    .frame(width: diameter * 0.08, height: diameter * 0.22)
                    .offset(y: -(diameter * 0.39))
                    .rotationEffect(.degrees(Double(tick) * 30))
            }

            Circle()
                .fill(Color.white.opacity(0.96))
                .frame(width: diameter * 0.42, height: diameter * 0.42)
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.2), lineWidth: 1)
                )

            VStack(spacing: 1) {
                Image("TierTap_C_PokerChip")
                    .resizable()
                    .scaledToFit()
                    .frame(width: diameter * 0.17, height: diameter * 0.17)
                Text("$\(denomination)")
                    .font(.system(size: max(6, diameter * 0.09), weight: .black, design: .rounded))
                    .foregroundColor(useDarkLabel ? .black : color)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: .black.opacity(0.28), radius: 2, x: 0, y: 2)
    }

    private func timerProgress(elapsed: TimeInterval) -> CGFloat {
        let segment = 2 * 60 * 60.0
        let mod = elapsed.truncatingRemainder(dividingBy: segment)
        let ratio = max(0, min(1, mod / segment))
        return CGFloat(ratio)
    }

    private func liveElapsedSeconds(at date: Date) -> TimeInterval {
        guard let live else { return 0 }
        let end = live.endTime ?? date
        return max(0, end.timeIntervalSince(live.startTime))
    }

    private var visualsAutoScrollEnabled: Bool {
        groupDefaults?.object(forKey: "ctt_watch_visuals_auto_scroll_enabled") as? Bool ?? false
    }

    private var visualsAutoScrollSeconds: Int {
        max(3, groupDefaults?.integer(forKey: "ctt_watch_visuals_auto_scroll_seconds") ?? 6)
    }

    private enum WatchHapticStyle {
        case success
        case queue
    }

    private func playConfiguredHaptic(style: WatchHapticStyle) {
        let enabled = groupDefaults?.object(forKey: "ctt_watch_haptics_enabled") as? Bool ?? true
        guard enabled else { return }
        let profile = groupDefaults?.string(forKey: "ctt_watch_haptic_profile") ?? "classic"
        #if os(watchOS)
        let haptic: WKHapticType
        switch (style, profile) {
        case (.success, "subtle"): haptic = .directionUp
        case (.success, "assertive"): haptic = .success
        case (.success, _): haptic = .success
        case (.queue, "subtle"): haptic = .click
        case (.queue, "assertive"): haptic = .failure
        case (.queue, _): haptic = .click
        }
        // watchOS haptics include an audible tap/tone, giving immediate feedback.
        WKInterfaceDevice.current().play(haptic)
        #endif
    }
}

private enum VisualCard: Hashable {
    case chipStack
    case timer
    case pulse
    case actions

    var next: VisualCard {
        switch self {
        case .chipStack: return .timer
        case .timer: return .pulse
        case .pulse: return .actions
        case .actions: return .chipStack
        }
    }
}
