import SwiftUI
#if os(watchOS)
import WatchKit
#endif

enum WatchLivePane: Hashable {
    case timer
    case grid
    case options
}

private struct WatchCloseoutSheetRef: Identifiable, Hashable {
    let id: UUID
    let totalBuyIn: Int
    let initialCashOut: Int
}

/// Fast close-out, regular close-out (cash-out on watch), or cancel (discard) live session — complements pause/unpause on the timer tab.
private struct WatchEndSessionOptionsView: View {
    @EnvironmentObject var store: SessionStore
    @State private var showConfirmFastClose = false
    @State private var showConfirmRegularClose = false
    @State private var showConfirmDiscard = false
    @State private var statusLine: String?
    @State private var statusColor: Color = .green
    @State private var closeoutSheetRef: WatchCloseoutSheetRef?

    private var hasLive: Bool { store.liveSession != nil }

    var body: some View {
        List {
            if let statusLine {
                Text(statusLine)
                    .font(.caption2.bold())
                    .foregroundStyle(statusColor)
            }
            if !hasLive {
                Text("No live session on iPhone. Start one from the phone or use Fast Start on the timer tab.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Pause and unpause the timer from the first Live Remote tab.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Section("Close-out") {
                    Button {
                        showConfirmFastClose = true
                    } label: {
                        Label("Fast close-out", systemImage: "bolt.fill")
                    }
                    Button {
                        showConfirmRegularClose = true
                    } label: {
                        Label("Regular close-out", systemImage: "list.clipboard.fill")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showConfirmDiscard = true
                    } label: {
                        Label("Cancel session", systemImage: "trash.fill")
                    }
                } header: {
                    Text("Discard")
                }
            }
        }
        .navigationTitle("End session")
        .alert("Fast close-out?", isPresented: $showConfirmFastClose) {
            Button("No", role: .cancel) {}
            Button("Yes") {
                let immediate = SessionSyncManager.shared.isReachable
                store.fastCloseSessionWithDefaultsUnverified()
                statusLine = immediate ? "Fast close-out sent" : "Fast close-out queued"
                statusColor = immediate ? .green : .orange
                playWatchEndFlowHaptic(success: immediate)
            }
        } message: {
            Text("Stops the timer and closes the session on iPhone with default cash-out and ending tier. No extra questions here.")
        }
        .alert("Regular close-out?", isPresented: $showConfirmRegularClose) {
            Button("No", role: .cancel) {}
            Button("Yes") {
                store.watchStopLiveSessionForCloseout { sessionId, err in
                    if let err {
                        statusLine = err
                        statusColor = .orange
                        playWatchEndFlowHaptic(success: false)
                    } else if let sessionId {
                        let session = store.sessions.first(where: { $0.id == sessionId })
                        let buyIn = session?.totalBuyIn ?? 0
                        let initialCashOut = session?.liveTrackedStackAmount ?? buyIn
                        closeoutSheetRef = WatchCloseoutSheetRef(
                            id: sessionId,
                            totalBuyIn: buyIn,
                            initialCashOut: initialCashOut
                        )
                        statusLine = "Enter cash-out on the next screen."
                        statusColor = .green
                        playWatchEndFlowHaptic(success: SessionSyncManager.shared.isReachable)
                    } else {
                        statusLine = "Stop did not complete. Try again."
                        statusColor = .orange
                        playWatchEndFlowHaptic(success: false)
                    }
                }
            }
        } message: {
            Text("Stops the timer and ends the live session on iPhone, then asks for cash-out on the watch. You can add avg bet, ending tier, and other details later on the phone if needed.")
        }
        .alert("Cancel session?", isPresented: $showConfirmDiscard) {
            Button("No", role: .cancel) {}
            Button("Delete", role: .destructive) {
                let immediate = SessionSyncManager.shared.isReachable
                store.discardLiveSession()
                statusLine = immediate ? "Cancel sent" : "Cancel queued"
                statusColor = immediate ? .green : .orange
                playWatchEndFlowHaptic(success: immediate)
            }
        } message: {
            Text("Permanently deletes this live session on iPhone. It will not appear in history.")
        }
        .sheet(item: $closeoutSheetRef) { ref in
            WatchCloseoutCashSheet(ref: ref) { err in
                if let err {
                    statusLine = err
                    statusColor = .orange
                    playWatchEndFlowHaptic(success: false)
                } else {
                    statusLine = "Close-out complete"
                    statusColor = .green
                    playWatchEndFlowHaptic(success: true)
                }
            }
            .environmentObject(store)
        }
    }

    private func playWatchEndFlowHaptic(success: Bool) {
        #if os(watchOS)
        WKInterfaceDevice.current().play(success ? .success : .click)
        #endif
    }
}

struct WatchLiveView: View {
    @EnvironmentObject var store: SessionStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.tierTapWatchAnimationsEnabled) private var tierTapWatchAnimationsEnabled
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @ObservedObject private var syncManager = SessionSyncManager.shared
    @State private var feedbackMessage: String?
    @State private var feedbackColor: Color = .green
    @State private var showFastStartSheet = false
    @State private var showWristSummary = false
    @State private var selectedPane: WatchLivePane
    @State private var lastPulseMinuteMark: Int = -1
    private let syncTicker = Timer.publish(every: 8, on: .main, in: .common).autoconnect()
    @State private var lastAppGroupSnapshotRevision: Int = 0
    @State private var lastObservedBuyIn: Int?
    @State private var lastObservedComp: Int?
    @State private var lastObservedTier: Int?
    @State private var buyInSuccessPulse = 0
    @State private var compSuccessPulse = 0
    @State private var tierSuccessPulse = 0
    @State private var stackSuccessPulse = 0
    @State private var lastObservedStack: Int?

    private var s: Session? { store.liveSession }
    private var hasLiveSession: Bool { store.liveSession != nil }
    private var isSessionPaused: Bool { s?.endTime != nil }
    private let metricColumns: [GridItem] = [GridItem(.flexible()), GridItem(.flexible())]
    private let groupDefaults = UserDefaults(suiteName: "group.com.app.tiertap")

    private var watchAnimationsAllowMotion: Bool {
        tierTapWatchAnimationsEnabled && !accessibilityReduceMotion
    }

    /// Elapsed play time for the current live session (frozen while paused via `endTime`).
    private func liveElapsedSeconds(at date: Date) -> TimeInterval {
        guard let live = store.liveSession else { return 0 }
        let end = live.endTime ?? date
        return max(0, end.timeIntervalSince(live.startTime))
    }

    init(initialPane: WatchLivePane = .timer) {
        _selectedPane = State(initialValue: initialPane)
    }

    var body: some View {
        TabView(selection: $selectedPane) {
            timerPane
                .tag(WatchLivePane.timer)
            quickGridPane
                .tag(WatchLivePane.grid)
            optionsPane
                .tag(WatchLivePane.options)
        }
        .tabViewStyle(.page)
        .indexViewStyle(.page(backgroundDisplayMode: .automatic))
        .localizedNavigationTitle("TierTap Remote")
        .onReceive(syncTicker) { _ in
            requestLatestContext()
            runSessionPulseIfNeeded()
        }
        .onAppear {
            requestLatestContext()
            presentWristSummaryIfNeeded()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                presentWristSummaryIfNeeded()
            }
        }
        .sheet(isPresented: $showFastStartSheet) {
            WatchFastStartSheet()
                .environmentObject(store)
        }
        .onChange(of: s?.totalBuyIn) { _, newTotal in
            if watchAnimationsAllowMotion, let prev = lastObservedBuyIn, let n = newTotal, n > prev {
                buyInSuccessPulse += 1
            }
            lastObservedBuyIn = newTotal
        }
        .onChange(of: s?.totalComp) { _, newTotal in
            if watchAnimationsAllowMotion, let prev = lastObservedComp, let n = newTotal, n > prev {
                compSuccessPulse += 1
            }
            lastObservedComp = newTotal
        }
        .onChange(of: s?.startingTierPoints) { _, newPoints in
            if watchAnimationsAllowMotion, let prev = lastObservedTier, let n = newPoints, n > prev {
                tierSuccessPulse += 1
            }
            lastObservedTier = newPoints
        }
        .onChange(of: s?.liveTrackedStackAmount) { _, newStack in
            if watchAnimationsAllowMotion, newStack != lastObservedStack, newStack != nil {
                stackSuccessPulse += 1
            }
            lastObservedStack = newStack
        }
    }

    private var timerPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image("TierTap_C_PokerChip")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                        .modifier(WatchChipNudgeModifier(trigger: buyInSuccessPulse, enabled: watchAnimationsAllowMotion))
                    Circle().fill(Color.red).frame(width: 6, height: 6)
                    L10nText("LIVE").font(.caption2.bold()).foregroundColor(.red)
                }

                if let live = s {
                    Text(live.casino)
                        .font(.caption.bold())
                        .lineLimit(1)
                    Text(live.game)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    L10nText("No live session")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if showWristSummary, wristRaiseSummaryEnabled {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Live Summary")
                            .font(.caption2.bold())
                            .foregroundColor(.secondary)
                        Text("Buy-In: $\((s?.totalBuyIn ?? 0).formatted(.number.grouping(.automatic)))")
                            .font(.caption2)
                        Text("Comp: $\((s?.totalComp ?? 0).formatted(.number.grouping(.automatic)))")
                            .font(.caption2)
                        Text("Tier: \((s?.startingTierPoints ?? 0).formatted(.number.grouping(.automatic)))")
                            .font(.caption2)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                TimelineView(.animation(minimumInterval: 1.0, paused: !hasLiveSession || isSessionPaused)) { context in
                    Button {
                        handlePrimaryTimerAction()
                    } label: {
                        VStack(spacing: 4) {
                            Text(Session.durationString(liveElapsedSeconds(at: context.date)))
                                .font(.system(.title2, design: .monospaced).weight(.semibold))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                            Text(primaryTimerButtonTitle)
                                .font(.caption2.bold())
                                .foregroundColor(.black)
                        }
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(WatchPrimaryTimerPressStyle(animationsEnabled: watchAnimationsAllowMotion))
                    .frame(maxWidth: .infinity, minHeight: 72)
                    .background(primaryTimerFill)
                    .animation(watchAnimationsAllowMotion ? .easeInOut(duration: 0.34) : nil, value: isSessionPaused)
                    .animation(watchAnimationsAllowMotion ? .easeInOut(duration: 0.28) : nil, value: hasLiveSession)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }

                Text("Swipe for quick grid and options")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if let feedbackMessage {
                    Text(feedbackMessage)
                        .font(.caption2)
                        .foregroundColor(feedbackColor)
                        .lineLimit(2)
                }
            }
            .padding()
        }
    }

    private var quickGridPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Quick Actions")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)

                LazyVGrid(columns: metricColumns, spacing: 8) {
                    NavigationLink {
                        WatchAddBuyInSheet()
                            .environmentObject(store)
                    } label: {
                        metricButton(
                            title: "Buy-In",
                            value: "$\((s?.totalBuyIn ?? 0).formatted(.number.grouping(.automatic)))",
                            icon: "plus.circle.fill",
                            accent: .blue,
                            successPulse: buyInSuccessPulse
                        )
                    }
                    .buttonStyle(WatchQuickTilePressStyle(enabled: watchAnimationsAllowMotion))

                    NavigationLink {
                        WatchAddCompSheet()
                            .environmentObject(store)
                    } label: {
                        metricButton(
                            title: "Comps",
                            value: "$\((s?.totalComp ?? 0).formatted(.number.grouping(.automatic)))",
                            icon: "gift.fill",
                            accent: .cyan,
                            successPulse: compSuccessPulse
                        )
                    }
                    .buttonStyle(WatchQuickTilePressStyle(enabled: watchAnimationsAllowMotion))

                    NavigationLink {
                        WatchUpdateTierSheet()
                            .environmentObject(store)
                    } label: {
                        metricButton(
                            title: "Tier",
                            value: (s?.startingTierPoints ?? 0).formatted(.number.grouping(.automatic)),
                            icon: "chart.bar.fill",
                            accent: .purple,
                            successPulse: tierSuccessPulse
                        )
                    }
                    .buttonStyle(WatchQuickTilePressStyle(enabled: watchAnimationsAllowMotion))

                    quickActionTile
                        .buttonStyle(WatchQuickTilePressStyle(enabled: watchAnimationsAllowMotion))
                }
            }
            .padding()
        }
    }

    private var optionsPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let prog = s?.rewardsProgramName?.trimmingCharacters(in: .whitespacesAndNewlines), !prog.isEmpty {
                    Text(prog)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }

                Button {
                    triggerWatchAction(name: "Pause session") {
                        store.stopLiveSessionTimer()
                    }
                } label: {
                    buttonLabel("Pause session", icon: "pause.circle.fill")
                }
                .buttonStyle(.bordered)
                .disabled(!hasLiveSession || isSessionPaused)

                Button {
                    triggerWatchAction(name: "Unpause session") {
                        store.resumeLiveSessionTimer()
                    }
                } label: {
                    buttonLabel("Unpause session", icon: "play.circle.fill")
                }
                .buttonStyle(.bordered)
                .disabled(!hasLiveSession || !isSessionPaused)

                NavigationLink {
                    WatchEndSessionOptionsView()
                        .environmentObject(store)
                } label: {
                    buttonLabel("End session…", icon: "flag.checkered")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(!hasLiveSession)

                NavigationLink {
                    WatchRemotesView()
                } label: {
                    buttonLabel("Event Log", icon: "list.bullet.rectangle")
                }
                .buttonStyle(.bordered)

                NavigationLink {
                    WatchHistoryView()
                        .environmentObject(store)
                } label: {
                    buttonLabel("Session History", icon: "clock.arrow.circlepath")
                }
                .buttonStyle(.bordered)

                Text(syncManager.syncStatusMessage)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                if let lastSyncAt = syncManager.lastSyncAt {
                    Text("Last sync \(lastSyncAt, style: .time)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
    }

    private var primaryTimerButtonTitle: String {
        if !hasLiveSession { return "Start Session" }
        return isSessionPaused ? "Unpause session" : "Pause session"
    }

    private var primaryTimerFill: Color {
        if !hasLiveSession { return .green }
        return isSessionPaused ? .orange : .green
    }

    private var timerStatusColor: Color {
        if let msg = feedbackMessage, msg.localizedCaseInsensitiveContains("close out") {
            return .red
        }
        if !hasLiveSession { return .black }
        return isSessionPaused ? .orange : .green
    }

    private var wristRaiseSummaryEnabled: Bool {
        groupDefaults?.object(forKey: "ctt_watch_wrist_raise_summary_enabled") as? Bool ?? true
    }

    private var sessionPulseEnabled: Bool {
        groupDefaults?.object(forKey: "ctt_watch_session_pulse_enabled") as? Bool ?? true
    }

    private var sessionPulseMinutes: Int {
        max(1, groupDefaults?.integer(forKey: "ctt_watch_session_pulse_minutes") ?? 20)
    }

    private var currencySymbol: String {
        let code = groupDefaults?.string(forKey: "ctt_currency_code") ?? "USD"
        switch code.uppercased() {
        case "EUR": return "€"
        case "GBP": return "£"
        case "JPY", "CNY": return "¥"
        case "KRW": return "₩"
        case "INR": return "₹"
        default: return "$"
        }
    }

    private var quickStackTileValue: String {
        let stack = s?.liveTrackedStackAmount ?? s?.totalBuyIn ?? 0
        return "\(currencySymbol)\(stack.formatted(.number.grouping(.automatic)))"
    }

    private var quickActionTile: some View {
        NavigationLink {
            WatchUpdateStackSheet().environmentObject(store)
        } label: {
            metricButton(
                title: "Stack",
                value: quickStackTileValue,
                icon: TierTapLabelIcon.chipStackSentinel,
                accent: .green,
                successPulse: stackSuccessPulse
            )
        }
    }

    private func handlePrimaryTimerAction() {
        if !hasLiveSession {
            showFastStartSheet = true
            return
        }
        if isSessionPaused {
            triggerWatchAction(name: "Unpause session") {
                store.resumeLiveSessionTimer()
            }
        } else {
            triggerWatchAction(name: "Pause session") {
                store.stopLiveSessionTimer()
            }
        }
    }

    private func metricButton(title: String, value: String, icon: String, accent: Color, successPulse: Int) -> some View {
        WatchQuickMetricLabel(
            title: title,
            value: value,
            icon: icon,
            accent: accent,
            motionEnabled: watchAnimationsAllowMotion,
            successPulse: successPulse
        )
    }

    private func buttonLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.footnote.bold())
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func triggerWatchAction(name: String, action: () -> Void) {
        let immediate = SessionSyncManager.shared.isReachable
        action()
        if immediate {
            feedbackMessage = "\(name) sent"
            feedbackColor = .green
            playConfiguredHaptic(style: .success)
        } else {
            feedbackMessage = "\(name) queued"
            feedbackColor = .orange
            playConfiguredHaptic(style: .queue)
        }
    }

    private func runSessionPulseIfNeeded() {
        guard sessionPulseEnabled, hasLiveSession else { return }
        let elapsedMinutes = Int(liveElapsedSeconds(at: Date()) / 60.0)
        guard elapsedMinutes > 0 else { return }
        guard elapsedMinutes % sessionPulseMinutes == 0 else { return }
        guard elapsedMinutes != lastPulseMinuteMark else { return }
        lastPulseMinuteMark = elapsedMinutes
        feedbackMessage = "Pulse: \(elapsedMinutes)m"
        feedbackColor = .orange
        playConfiguredHaptic(style: .pulse)
    }

    private func presentWristSummaryIfNeeded() {
        guard wristRaiseSummaryEnabled else { return }
        showWristSummary = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            showWristSummary = false
        }
    }

    private func requestLatestContext() {
        SessionSyncManager.shared.requestContext { sessions, liveSession in
            DispatchQueue.main.async {
                store.applySyncedState(sessions: sessions, liveSession: liveSession)
            }
        }
        #if os(watchOS)
        if let snap = SessionSyncManager.shared.readAppGroupSnapshotIfAvailable(),
           snap.revision != lastAppGroupSnapshotRevision {
            lastAppGroupSnapshotRevision = snap.revision
            DispatchQueue.main.async {
                store.applySyncedState(sessions: snap.sessions, liveSession: snap.liveSession)
                SessionSyncManager.shared.noteAppGroupSnapshotApplied(
                    sessionCount: snap.sessions.count,
                    liveSessionID: snap.liveSession?.id
                )
            }
        }
        #endif
    }

    private enum WatchHapticStyle {
        case success
        case queue
        case pulse
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
        case (.pulse, "subtle"): haptic = .start
        case (.pulse, "assertive"): haptic = .notification
        case (.pulse, _): haptic = .directionUp
        }
        WKInterfaceDevice.current().play(haptic)
        #endif
    }

    private func playSuccessHaptic() {
        #if os(watchOS)
        playConfiguredHaptic(style: .success)
        #endif
    }

    private func playClickHaptic() {
        #if os(watchOS)
        playConfiguredHaptic(style: .queue)
        #endif
    }
}

// MARK: - Cash-out sheet (session already stopped on iPhone)

private struct WatchCloseoutCashSheet: View {
    @EnvironmentObject var store: SessionStore
    @Environment(\.dismiss) private var dismiss

    let ref: WatchCloseoutSheetRef
    /// Called with `nil` on success, or an error message from the phone.
    let onFinished: (String?) -> Void

    @State private var winLossDelta: Double = 0

    private var buyIn: Int { max(0, ref.totalBuyIn) }
    private var initialCashOut: Int { max(0, ref.initialCashOut) }

    private var estimatedCashOut: Int {
        max(0, buyIn + Int(winLossDelta.rounded(.toNearestOrAwayFromZero)))
    }

    private var estimatedWinLoss: Int { estimatedCashOut - buyIn }

    private var crownLower: Double { -Double(buyIn) }
    private var crownUpper: Double { max(Double(buyIn) * 10, 25_000) }
    private var crownStep: Double { buyIn >= 500 ? 25 : 5 }

    private func formattedDollars(_ n: Int) -> String {
        "$\(n.formatted(.number.grouping(.automatic)))"
    }

    private var winLossSummary: String {
        let wl = estimatedWinLoss
        let body = "$\(abs(wl).formatted(.number.grouping(.automatic)))"
        if wl > 0 { return "+\(body)" }
        if wl < 0 { return "-\(body)" }
        return body
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Buy-in: \(formattedDollars(buyIn))")
                    Text("Cash-out: \(formattedDollars(estimatedCashOut))")
                    Text("Win/loss: \(winLossSummary)")
                        .foregroundColor(estimatedWinLoss >= 0 ? .green : .red)
                }
                if buyIn > 0 {
                    Text("Turn the Digital Crown to adjust cash-out vs buy-in, then tap Done to save to this session on iPhone.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No buy-in was logged. Done saves $0 cash-out on iPhone; you can fix totals there.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .modifier(WatchCloseoutCrownModifier(
                enabled: buyIn > 0,
                winLossDelta: $winLossDelta,
                from: crownLower,
                through: crownUpper,
                by: crownStep
            ))
            .navigationTitle("Cash-out")
            #if os(watchOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { confirmAndSave() }
                }
            }
        }
        .onAppear {
            winLossDelta = Double(initialCashOut - buyIn)
        }
    }

    private func confirmAndSave() {
        let cashOut = estimatedCashOut
        store.watchApplyCloseoutCashOut(sessionId: ref.id, cashOut: cashOut) { err in
            onFinished(err)
            dismiss()
        }
    }
}

private struct WatchCloseoutCrownModifier: ViewModifier {
    var enabled: Bool
    @Binding var winLossDelta: Double
    var from: Double
    var through: Double
    var by: Double

    func body(content: Content) -> some View {
        if enabled {
            content
                .focusable(true)
                .digitalCrownRotation(
                    $winLossDelta,
                    from: from,
                    through: through,
                    by: by,
                    sensitivity: .low,
                    isContinuous: false,
                    isHapticFeedbackEnabled: true
                )
        } else {
            content
        }
    }
}

// MARK: - Quick metric tiles & press feedback

private struct WatchQuickTilePressStyle: ButtonStyle {
    var enabled: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(enabled && configuration.isPressed ? 0.96 : 1)
            .animation(enabled ? .spring(response: 0.2, dampingFraction: 0.76) : nil, value: configuration.isPressed)
    }
}

private struct WatchPrimaryTimerPressStyle: ButtonStyle {
    var animationsEnabled: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(animationsEnabled && configuration.isPressed ? 0.98 : 1)
            .animation(animationsEnabled ? .spring(response: 0.22, dampingFraction: 0.8) : nil, value: configuration.isPressed)
    }
}

private struct WatchQuickMetricLabel: View {
    let title: String
    let value: String
    let icon: String
    let accent: Color
    let motionEnabled: Bool
    let successPulse: Int
    @State private var rippleScale: CGFloat = 1
    @State private var rippleOpacity: Double = 0
    private let groupDefaults = UserDefaults(suiteName: "group.com.app.tiertap")

    private var currencySymbol: String {
        let code = groupDefaults?.string(forKey: "ctt_currency_code") ?? "USD"
        switch code.uppercased() {
        case "EUR": return "€"
        case "GBP": return "£"
        case "JPY", "CNY": return "¥"
        case "KRW": return "₩"
        case "INR": return "₹"
        default: return "$"
        }
    }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 3) {
                Label {
                    Text(title)
                        .font(.caption2)
                        .lineLimit(1)
                } icon: {
                    iconImage
                }
                .foregroundColor(.secondary)
                Text(value)
                    .font(.footnote.monospacedDigit().bold())
                    .foregroundColor(accent)
                    .contentTransition(.numericText())
                    .animation(motionEnabled ? .snappy : nil, value: value)
                    .lineLimit(1)
                Text("+")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .background(Color.gray.opacity(0.18))

            if motionEnabled {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(accent.opacity(0.78 * rippleOpacity), lineWidth: 2)
                    .scaleEffect(rippleScale)
                    .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onChange(of: successPulse) { _, newValue in
            guard motionEnabled, newValue > 0 else { return }
            rippleScale = 0.9
            rippleOpacity = 1
            withAnimation(.easeOut(duration: 0.34)) {
                rippleScale = 1.22
                rippleOpacity = 0
            }
        }
    }

    @ViewBuilder
    private var iconImage: some View {
        if icon == TierTapLabelIcon.chipStackSentinel {
            TierTapChipStackIcon(side: 15, currencySymbol: currencySymbol)
        } else if motionEnabled {
            Image(systemName: icon)
                .font(.caption2)
                .symbolEffect(.bounce, value: successPulse)
        } else {
            Image(systemName: icon)
                .font(.caption2)
        }
    }
}

private struct WatchChipNudgeModifier: ViewModifier {
    var trigger: Int
    var enabled: Bool
    @State private var nudge: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(Double(nudge) * 12))
            .offset(y: CGFloat(nudge) * -5)
            .onChange(of: trigger) { _, new in
                guard enabled, new > 0 else { return }
                nudge = 0
                withAnimation(.spring(response: 0.26, dampingFraction: 0.52)) {
                    nudge = 1
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                        nudge = 0
                    }
                }
            }
    }
}

private struct WatchFastStartSheet: View {
    @EnvironmentObject var store: SessionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.tierTapWatchAnimationsEnabled) private var tierTapWatchAnimationsEnabled
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var statusMessage: String?
    @State private var statusColor: Color = .green
    @State private var pendingFastStart = false
    @State private var baselineLiveSessionID: UUID?
    @State private var showConfirmFastStart = false
    @State private var pendingFastStartCategory: SessionGameCategory?

    private var pokerTemplate: Session? { store.mostRecentSession(forGameCategory: .poker) }
    private var tableTemplate: Session? { store.mostRecentSession(forGameCategory: .table) }
    private var slotsTemplate: Session? { store.mostRecentSession(forGameCategory: .slots) }
    private var hasAnyTemplate: Bool {
        pokerTemplate != nil || tableTemplate != nil || slotsTemplate != nil
    }

    private var fastStartMotionOK: Bool {
        tierTapWatchAnimationsEnabled && !accessibilityReduceMotion
    }

    var body: some View {
        List {
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption2.bold())
                    .foregroundColor(statusColor)
            }
            if let pokerTemplate {
                Button {
                    requestFastStartConfirmation(.poker)
                } label: {
                    Label(fastStartLabel(for: .poker, template: pokerTemplate), systemImage: iconName(for: .poker))
                }
                .buttonStyle(WatchQuickTilePressStyle(enabled: fastStartMotionOK))
            }
            if let tableTemplate {
                Button {
                    requestFastStartConfirmation(.table)
                } label: {
                    Label(fastStartLabel(for: .table, template: tableTemplate), systemImage: iconName(for: .table))
                }
                .buttonStyle(WatchQuickTilePressStyle(enabled: fastStartMotionOK))
            }
            if let slotsTemplate {
                Button {
                    requestFastStartConfirmation(.slots)
                } label: {
                    Label(fastStartLabel(for: .slots, template: slotsTemplate), systemImage: iconName(for: .slots))
                }
                .buttonStyle(WatchQuickTilePressStyle(enabled: fastStartMotionOK))
            }
            if !hasAnyTemplate {
                Text("No fast start templates available yet. Start a session on iPhone first.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .localizedNavigationTitle("Fast Start")
        .onAppear {
            baselineLiveSessionID = store.liveSession?.id
        }
        .onChange(of: store.liveSession?.id) { newID in
            guard pendingFastStart else { return }
            guard newID != nil, newID != baselineLiveSessionID else { return }
            pendingFastStart = false
            statusMessage = "Live session started on iPhone"
            statusColor = .green
            WKInterfaceDevice.current().play(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                dismiss()
            }
        }
        .alert("Start session?", isPresented: $showConfirmFastStart) {
            Button("No", role: .cancel) {}
            Button("Yes") {
                guard let category = pendingFastStartCategory else { return }
                triggerFastStart(category)
            }
        } message: {
            Text("Confirm fast start using your most recent template for this game category.")
        }
    }

    private func requestFastStartConfirmation(_ category: SessionGameCategory) {
        pendingFastStartCategory = category
        showConfirmFastStart = true
    }

    private func iconName(for category: SessionGameCategory) -> String {
        switch category {
        case .poker:
            return "suit.spade.fill"
        case .table:
            return "dice.fill"
        case .slots:
            return "7.circle.fill"
        }
    }

    private func triggerFastStart(_ category: SessionGameCategory) {
        guard store.liveSession == nil else {
            pendingFastStart = false
            statusMessage = "A session is already live"
            statusColor = .orange
            WKInterfaceDevice.current().play(.click)
            return
        }
        let immediate = SessionSyncManager.shared.isReachable
        pendingFastStart = true
        baselineLiveSessionID = store.liveSession?.id
        store.fastStartSession(category: category)
        statusMessage = immediate ? "Fast start sent" : "Fast start queued"
        statusColor = immediate ? .green : .orange
        WKInterfaceDevice.current().play(immediate ? .success : .click)
    }

    private func fastStartLabel(for category: SessionGameCategory, template: Session?) -> String {
        let prefix = "Fast Start"
        guard let template else {
            switch category {
            case .poker: return "\(prefix) Poker"
            case .table: return "\(prefix) Table"
            case .slots: return "\(prefix) Slots"
            }
        }

        let game = template.game.trimmingCharacters(in: .whitespacesAndNewlines)
        let casino = template.casino.trimmingCharacters(in: .whitespacesAndNewlines)
        if !casino.isEmpty && !game.isEmpty {
            return "\(prefix) \(casino) \(game)"
        }
        if !game.isEmpty {
            return "\(prefix) \(game)"
        }
        if !casino.isEmpty {
            return "\(prefix) \(casino)"
        }
        switch category {
        case .poker: return "\(prefix) Poker"
        case .table: return "\(prefix) Table"
        case .slots: return "\(prefix) Slots"
        }
    }
}

private struct WatchAddBuyInSheet: View {
    @EnvironmentObject var store: SessionStore
    @Environment(\.tierTapWatchAnimationsEnabled) private var tierTapWatchAnimationsEnabled
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var amount: Double = 100
    @State private var customAmountText: String = "100"
    @State private var statusMessage: String?
    @State private var statusColor: Color = .green
    @State private var pendingExpectedTotal: Int?
    @State private var showConfirmAdd = false
    @State private var addOnChipNudge = 0
    private let groupDefaults = UserDefaults(suiteName: "group.com.app.tiertap")

    private var buyInMotionOK: Bool {
        tierTapWatchAnimationsEnabled && !accessibilityReduceMotion
    }

    private var currentTotalBuyIn: Int {
        store.liveSession?.totalBuyIn ?? 0
    }

    private var selectedAmount: Int {
        let custom = Int(customAmountText.filter { $0.isNumber }) ?? 0
        if custom > 0 { return custom }
        return max(5, Int(amount))
    }

    private var proposedTotal: Int {
        currentTotalBuyIn + selectedAmount
    }

    private var amountPresetValues: [Int] {
        let defaults = [20, 100, 200, 500]
        guard let raw = groupDefaults?.string(forKey: "ctt_watch_buyin_cash_defaults") else {
            return defaults
        }
        let parsed = parseFlexibleSeparatedIntegers(raw)
        return parsed.isEmpty ? defaults : parsed
    }

    private var buyInConfirmationSummary: String {
        let typedDigits = customAmountText.filter { $0.isNumber }
        let entryMode = typedDigits.isEmpty ? "Digital Crown / preset" : "Typed amount"
        return "Amount: $\(selectedAmount)\nEntry: \(entryMode)\nCurrent total: $\(currentTotalBuyIn)\nNew total: $\(proposedTotal)"
    }

    var body: some View {
        Form {
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption2.bold())
                    .foregroundColor(statusColor)
            }
            Text("Current total: $\(currentTotalBuyIn)")
                .font(.caption2)
                .foregroundColor(.secondary)
                .contentTransition(.numericText())
                .animation(buyInMotionOK ? .snappy : nil, value: currentTotalBuyIn)
            HStack(alignment: .center, spacing: 8) {
                Text("Amount: $\(selectedAmount)")
                    .font(.headline.monospacedDigit())
                    .contentTransition(.numericText())
                    .animation(buyInMotionOK ? .snappy : nil, value: selectedAmount)
            }
            Text("Proposed total: $\(proposedTotal)")
                .font(.caption2)
                .foregroundColor(.green)
                .contentTransition(.numericText())
                .animation(buyInMotionOK ? .snappy : nil, value: proposedTotal)
            quickAmountRows(amountPresetValues)
            Text("Custom amount")
                .font(.caption2)
                .foregroundStyle(.secondary)
            WatchNumericDigitPad(text: $customAmountText, allowSpace: false, maxLength: 8)
            Button("Add Buy-In") {
                showConfirmAdd = true
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .center)
            .foregroundColor(.black)
            .padding(.vertical, 6)
            .background(Color.green)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .focusable(true)
        .digitalCrownRotation(
            $amount,
            from: 5,
            through: 20_000,
            by: 5,
            sensitivity: .low,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .localizedNavigationTitle("Add Buy-In")
        .alert("Add buy-in?", isPresented: $showConfirmAdd) {
            Button("No", role: .cancel) {}
            Button("Yes") {
                let selected = selectedAmount
                let immediate = SessionSyncManager.shared.isReachable
                pendingExpectedTotal = currentTotalBuyIn + selected
                store.addBuyIn(selected)
                statusMessage = immediate ? "Buy-in sent" : "Buy-in queued"
                statusColor = immediate ? .green : .orange
                if immediate { playSuccessHaptic() } else { playClickHaptic() }
            }
        } message: {
            Text("Add buy-in?\n\n\(buyInConfirmationSummary)")
        }
        .onChange(of: store.liveSession?.totalBuyIn) { newTotal in
            guard let expected = pendingExpectedTotal, let newTotal else { return }
            guard newTotal >= expected else { return }
            pendingExpectedTotal = nil
            statusMessage = "Buy-in updated on iPhone"
            statusColor = .green
            playSuccessHaptic()
            if buyInMotionOK {
                addOnChipNudge += 1
            }
        }
        .onAppear {
            customAmountText = "\(max(5, Int(amount)))"
        }
    }

    private func quickAmountButton(_ value: Int) -> some View {
        Button("$\(value)") {
            amount = Double(value)
            customAmountText = "\(value)"
        }
        .buttonStyle(WatchQuickTilePressStyle(enabled: buyInMotionOK))
        .frame(maxWidth: .infinity, alignment: .center)
        .foregroundColor(.black)
        .padding(.vertical, 4)
        .background(Color.green)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private func quickAmountRows(_ values: [Int]) -> some View {
        let chunkSize = 2
        let totalRows = Int(ceil(Double(values.count) / Double(chunkSize)))
        ForEach(0..<max(totalRows, 1), id: \.self) { row in
            HStack {
                let firstIndex = row * chunkSize
                if firstIndex < values.count {
                    quickAmountButton(values[firstIndex])
                }
                let secondIndex = firstIndex + 1
                if secondIndex < values.count {
                    quickAmountButton(values[secondIndex])
                }
            }
        }
    }

    private func parseFlexibleSeparatedIntegers(_ raw: String) -> [Int] {
        raw
            .replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { $0 > 0 }
    }

    private func playSuccessHaptic() {
        #if os(watchOS)
        WKInterfaceDevice.current().play(.success)
        #endif
    }

    private func playClickHaptic() {
        #if os(watchOS)
        WKInterfaceDevice.current().play(.click)
        #endif
    }
}

private struct WatchUpdateStackSheet: View {
    @EnvironmentObject var store: SessionStore
    @Environment(\.tierTapWatchAnimationsEnabled) private var tierTapWatchAnimationsEnabled
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var amount: Double = 100
    @State private var customAmountText: String = "100"
    @State private var statusMessage: String?
    @State private var statusColor: Color = .green
    @State private var pendingExpectedStack: Int?
    @State private var showConfirmUpdate = false
    @State private var stackChipNudge = 0
    @State private var stackWinConfettiBurst = 0
    private let groupDefaults = UserDefaults(suiteName: "group.com.app.tiertap")

    private var stackMotionOK: Bool {
        tierTapWatchAnimationsEnabled && !accessibilityReduceMotion
    }

    private var totalBuyIn: Int {
        store.liveSession?.totalBuyIn ?? 0
    }

    private var selectedStack: Int {
        let custom = Int(customAmountText.filter { $0.isNumber }) ?? 0
        if custom > 0 { return custom }
        return max(0, Int(amount))
    }

    private var sessionWinLossPreview: Int {
        selectedStack - totalBuyIn
    }

    private var amountPresetValues: [Int] {
        let defaults = [100, 200, 500, 1_000]
        guard let raw = groupDefaults?.string(forKey: "ctt_watch_buyin_cash_defaults") else {
            return defaults
        }
        let parsed = parseFlexibleSeparatedIntegers(raw)
        return parsed.isEmpty ? defaults : parsed
    }

    private var stackConfirmationSummary: String {
        let typedDigits = customAmountText.filter { $0.isNumber }
        let entryMode = typedDigits.isEmpty ? "Digital Crown / preset" : "Typed amount"
        let wl = sessionWinLossPreview
        let wlLine = wl >= 0 ? "Session win: $\(wl)" : "Session loss: $\(abs(wl))"
        return "Stack: $\(selectedStack)\nEntry: \(entryMode)\nTotal buy-in: $\(totalBuyIn)\n\(wlLine)"
    }

    var body: some View {
        ZStack {
            StackWinConfettiBurst(burstID: stackWinConfettiBurst, enabled: stackMotionOK)
                .allowsHitTesting(false)
            Form {
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption2.bold())
                    .foregroundColor(statusColor)
            }
            Text("Total buy-in: $\(totalBuyIn)")
                .font(.caption2)
                .foregroundColor(.secondary)
                .contentTransition(.numericText())
                .animation(stackMotionOK ? .snappy : nil, value: totalBuyIn)
            HStack(alignment: .center, spacing: 8) {
                Text("Stack: $\(selectedStack)")
                    .font(.headline.monospacedDigit())
                    .contentTransition(.numericText())
                    .animation(stackMotionOK ? .snappy : nil, value: selectedStack)
            }
            Text(sessionWinLossPreview >= 0 ? "Session win: $\(sessionWinLossPreview)" : "Session loss: $\(abs(sessionWinLossPreview))")
                .font(.caption2)
                .foregroundColor(sessionWinLossPreview >= 0 ? .green : .red)
                .contentTransition(.numericText())
                .animation(stackMotionOK ? .snappy : nil, value: sessionWinLossPreview)
            quickAmountRows(amountPresetValues)
            Text("Custom stack")
                .font(.caption2)
                .foregroundStyle(.secondary)
            WatchNumericDigitPad(text: $customAmountText, allowSpace: false, maxLength: 8)
            Button("Update Stack") {
                showConfirmUpdate = true
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .center)
            .foregroundColor(.black)
            .padding(.vertical, 6)
            .background(Color.teal)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .focusable(true)
        .digitalCrownRotation(
            $amount,
            from: 0,
            through: 20_000,
            by: 5,
            sensitivity: .low,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .localizedNavigationTitle("Update Stack")
        .alert("Update stack?", isPresented: $showConfirmUpdate) {
            Button("No", role: .cancel) {}
            Button("Yes") {
                let stack = selectedStack
                let immediate = SessionSyncManager.shared.isReachable
                pendingExpectedStack = stack
                store.updateLiveTrackedStack(stack)
                statusMessage = immediate ? "Stack sent" : "Stack queued"
                statusColor = immediate ? .green : .orange
                if immediate { playSuccessHaptic() } else { playClickHaptic() }
            }
        } message: {
            Text("Update stack?\n\n\(stackConfirmationSummary)")
        }
        .onChange(of: store.liveSession?.liveTrackedStackAmount) { _, newVal in
            guard let expected = pendingExpectedStack, let newVal else { return }
            guard newVal == expected else { return }
            pendingExpectedStack = nil
            let wl = newVal - (store.liveSession?.totalBuyIn ?? 0)
            statusMessage = wl >= 0 ? "Session win $\(wl)" : "Session loss $\(abs(wl))"
            statusColor = .green
            playSuccessHaptic()
            if stackMotionOK {
                stackChipNudge += 1
            }
            if wl > 0, stackMotionOK {
                stackWinConfettiBurst += 1
            }
        }
        .onAppear {
            let seed = store.liveSession?.liveTrackedStackAmount ?? store.liveSession?.totalBuyIn ?? 100
            let s = max(0, seed)
            amount = Double(s)
            customAmountText = s > 0 ? "\(s)" : "100"
        }
    }

    private func quickAmountButton(_ value: Int) -> some View {
        Button("$\(value)") {
            amount = Double(value)
            customAmountText = "\(value)"
        }
        .buttonStyle(WatchQuickTilePressStyle(enabled: stackMotionOK))
        .frame(maxWidth: .infinity, alignment: .center)
        .foregroundColor(.black)
        .padding(.vertical, 4)
        .background(Color.teal)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private func quickAmountRows(_ values: [Int]) -> some View {
        let chunkSize = 2
        let totalRows = Int(ceil(Double(values.count) / Double(chunkSize)))
        ForEach(0..<max(totalRows, 1), id: \.self) { row in
            HStack {
                let firstIndex = row * chunkSize
                if firstIndex < values.count {
                    quickAmountButton(values[firstIndex])
                }
                let secondIndex = firstIndex + 1
                if secondIndex < values.count {
                    quickAmountButton(values[secondIndex])
                }
            }
        }
    }

    private func parseFlexibleSeparatedIntegers(_ raw: String) -> [Int] {
        raw
            .replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { $0 > 0 }
    }

    private func playSuccessHaptic() {
        #if os(watchOS)
        WKInterfaceDevice.current().play(.success)
        #endif
    }

    private func playClickHaptic() {
        #if os(watchOS)
        WKInterfaceDevice.current().play(.click)
        #endif
    }
}

private struct WatchAddCompSheet: View {
    @EnvironmentObject var store: SessionStore
    @Environment(\.tierTapWatchAnimationsEnabled) private var tierTapWatchAnimationsEnabled
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var amount: Double = 20
    @State private var customAmountText: String = "20"
    @State private var details = ""
    @State private var selectedCompEntryMode: WatchCompEntryMode?
    @State private var selectedContextIndex: Int = 0
    @State private var statusMessage: String?
    @State private var statusColor: Color = .green
    @State private var pendingExpectedCompTotal: Int?
    @State private var showConfirmAdd = false
    @State private var compCelebrationToken = 0
    @State private var foodToastText: String?
    @State private var categoryWobbleDegrees: Double = 0
    private let groupDefaults = UserDefaults(suiteName: "group.com.app.tiertap")
    private let contextGridColumns: [GridItem] = [GridItem(.flexible()), GridItem(.flexible())]

    private var compMotionOK: Bool {
        tierTapWatchAnimationsEnabled && !accessibilityReduceMotion
    }

    private var currentCompTotal: Int {
        store.liveSession?.totalComp ?? 0
    }

    private var selectedAmount: Int {
        let custom = Int(customAmountText.filter { $0.isNumber }) ?? 0
        if custom > 0 { return custom }
        return max(5, Int(amount))
    }

    private var proposedCompTotal: Int {
        currentCompTotal + selectedAmount
    }

    private var compContextLabel: String {
        let mode = selectedCompEntryMode ?? .cashValue
        if mode == .foodBeverage {
            let options = contextOptions
            guard selectedContextIndex >= 0, selectedContextIndex < options.count else { return "Food/Beverage" }
            let selected = options[selectedContextIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            return selected.isEmpty ? "Food/Beverage" : selected
        }
        return "Cash Value"
    }

    private var compConfirmationSummary: String {
        let notes = details.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines = [
            "Type: \(compContextLabel)",
            "Amount: $\(selectedAmount)",
            "Current comps: $\(currentCompTotal)",
            "New comps total: $\(proposedCompTotal)"
        ]
        if !notes.isEmpty {
            lines.append("Notes: \(notes)")
        }
        return lines.joined(separator: "\n")
    }

    private var amountPresetValues: [Int] {
        let defaults = [20, 50, 100, 500]
        guard let raw = groupDefaults?.string(forKey: "ctt_watch_comp_cash_defaults") else {
            return defaults
        }
        let parsed = parseFlexibleSeparatedIntegers(raw)
        return parsed.isEmpty ? defaults : parsed
    }

    private var contextOptions: [String] {
        let defaults = ["Cocktail", "Beer", "Food", "Cash"]
        guard let raw = groupDefaults?.string(forKey: "ctt_watch_comp_context_options") else {
            return defaults
        }
        let parsed = raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parsed.isEmpty ? defaults : parsed
    }

    var body: some View {
        ZStack(alignment: .top) {
            Form {
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption2.bold())
                    .foregroundColor(statusColor)
            }
            HStack {
                Text("Current comps: $\(currentCompTotal)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .contentTransition(.numericText())
                    .animation(compMotionOK ? .snappy : nil, value: currentCompTotal)
                Spacer(minLength: 0)
                if compMotionOK {
                    Image(systemName: "gift.fill")
                        .font(.caption2)
                        .foregroundStyle(.cyan)
                        .symbolEffect(.bounce, value: compCelebrationToken)
                }
            }
            if selectedCompEntryMode == nil {
                Text("Add comp as:")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Button("Add Food/Beverage") {
                    selectedCompEntryMode = .foodBeverage
                    selectedContextIndex = min(selectedContextIndex, max(contextOptions.count - 1, 0))
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
                Button("Add Cash Value") {
                    selectedCompEntryMode = .cashValue
                }
                .buttonStyle(.bordered)
            } else if selectedCompEntryMode == .cashValue {
                Text("Comp: $\(selectedAmount)")
                    .font(.headline.monospacedDigit())
                    .contentTransition(.numericText())
                    .animation(compMotionOK ? .snappy : nil, value: selectedAmount)
                HStack(spacing: 6) {
                    Text("Proposed comps: $\(proposedCompTotal)")
                        .font(.caption2)
                        .foregroundColor(.green)
                        .contentTransition(.numericText())
                        .animation(compMotionOK ? .snappy : nil, value: proposedCompTotal)
                    if compMotionOK, selectedAmount > 0 {
                        Text("+\(selectedAmount)")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.green.opacity(0.9))
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .animation(compMotionOK ? .spring(response: 0.28, dampingFraction: 0.82) : nil, value: selectedAmount)
                quickAmountRows(amountPresetValues)
                Text("Custom comp")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                WatchNumericDigitPad(text: $customAmountText, allowSpace: false, maxLength: 8)
                TextField("Context (optional)", text: $details)
            } else {
                Text("Category")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                LazyVGrid(columns: contextGridColumns, spacing: 8) {
                    ForEach(Array(contextOptions.enumerated()), id: \.offset) { index, option in
                        Button {
                            selectedContextIndex = index
                        } label: {
                            HStack(spacing: 4) {
                                Text(option)
                                    .font(.caption2.bold())
                                    .lineLimit(1)
                                if selectedContextIndex == index {
                                    Image(systemName: "checkmark")
                                        .font(.caption2)
                                }
                            }
                            .rotationEffect(.degrees(selectedContextIndex == index ? categoryWobbleDegrees : 0))
                        }
                        .buttonStyle(WatchQuickTilePressStyle(enabled: compMotionOK))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .foregroundColor(selectedContextIndex == index ? .black : .white)
                        .background(selectedContextIndex == index ? Color.green : Color.gray.opacity(0.22))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                Text("Estimated value: $\(selectedAmount)")
                    .font(.headline.monospacedDigit())
                    .contentTransition(.numericText())
                    .animation(compMotionOK ? .snappy : nil, value: selectedAmount)
                Text("Proposed comps: $\(proposedCompTotal)")
                    .font(.caption2)
                    .foregroundColor(.green)
                    .underline(true, color: .cyan)
                    .contentTransition(.numericText())
                    .animation(compMotionOK ? .snappy : nil, value: proposedCompTotal)
                quickAmountRows(amountPresetValues)
                Text("Custom value")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                WatchNumericDigitPad(text: $customAmountText, allowSpace: false, maxLength: 8)
                TextField("Notes (optional)", text: $details)
            }
            if selectedCompEntryMode != nil {
                Button("Change Type") {
                    selectedCompEntryMode = nil
                }
                .buttonStyle(.bordered)
            }
            Button("Add Comp") {
                showConfirmAdd = true
            }
            .disabled(selectedCompEntryMode == nil || selectedAmount <= 0 || (selectedCompEntryMode == .foodBeverage && contextOptions.isEmpty))
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .center)
            .foregroundColor(.black)
            .padding(.vertical, 6)
            .background(Color.green)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            if compMotionOK, let toast = foodToastText {
                Text(toast)
                    .font(.caption2.bold())
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.cyan.opacity(0.92)))
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(compMotionOK ? .spring(response: 0.35, dampingFraction: 0.82) : nil, value: foodToastText)
        .focusable(true)
        .digitalCrownRotation(
            $amount,
            from: 5,
            through: 10_000,
            by: 5,
            sensitivity: .low,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .localizedNavigationTitle("Add Comp")
        .alert("Add comp?", isPresented: $showConfirmAdd) {
            Button("No", role: .cancel) {}
            Button("Yes") {
                let selected = selectedAmount
                let immediate = SessionSyncManager.shared.isReachable
                let trimmed = details.trimmingCharacters(in: .whitespacesAndNewlines)
                pendingExpectedCompTotal = currentCompTotal + selected
                let mode = selectedCompEntryMode ?? .cashValue
                if mode == .foodBeverage {
                    let context = compContextLabel
                    let detailsParts = [context, trimmed].filter { !$0.isEmpty }
                    let mergedDetails = detailsParts.joined(separator: " - ")
                    store.addComp(
                        amount: selected,
                        kind: .foodBeverage,
                        details: mergedDetails.isEmpty ? nil : mergedDetails,
                        foodBeverageKind: mappedFoodBeverageKind(for: context),
                        foodBeverageOtherDescription: mappedFoodBeverageKind(for: context) == .other ? context : nil
                    )
                } else {
                    let cashContext = "Cash Value"
                    let detailsParts = [cashContext, trimmed].filter { !$0.isEmpty }
                    let mergedDetails = detailsParts.joined(separator: " - ")
                    store.addComp(amount: selected, kind: .dollarsCredits, details: mergedDetails.isEmpty ? nil : mergedDetails)
                }
                statusMessage = immediate ? "Comp sent" : "Comp queued"
                statusColor = immediate ? .green : .orange
                if immediate { playSuccessHaptic() } else { playClickHaptic() }
                if compMotionOK, mode == .foodBeverage {
                    let label = compContextLabel
                    foodToastText = label
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.65) {
                        foodToastText = nil
                    }
                }
                details = ""
            }
        } message: {
            Text("Add comp?\n\n\(compConfirmationSummary)")
        }
        .onChange(of: store.liveSession?.totalComp) { newTotal in
            guard let expected = pendingExpectedCompTotal, let newTotal else { return }
            guard newTotal >= expected else { return }
            pendingExpectedCompTotal = nil
            statusMessage = "Comp updated on iPhone"
            statusColor = .green
            playSuccessHaptic()
            if compMotionOK {
                compCelebrationToken += 1
            }
        }
        .onChange(of: selectedContextIndex) { old, new in
            guard old != new, compMotionOK else { return }
            withAnimation(.spring(response: 0.22, dampingFraction: 0.48)) {
                categoryWobbleDegrees = 7
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                    categoryWobbleDegrees = 0
                }
            }
        }
        .onAppear {
            customAmountText = "\(max(5, Int(amount)))"
            selectedContextIndex = min(selectedContextIndex, max(contextOptions.count - 1, 0))
        }
    }

    @ViewBuilder
    private func quickAmountRows(_ values: [Int]) -> some View {
        let chunkSize = 2
        let totalRows = Int(ceil(Double(values.count) / Double(chunkSize)))
        ForEach(0..<max(totalRows, 1), id: \.self) { row in
            HStack {
                let firstIndex = row * chunkSize
                if firstIndex < values.count {
                    quickAmountButton(values[firstIndex])
                }
                let secondIndex = firstIndex + 1
                if secondIndex < values.count {
                    quickAmountButton(values[secondIndex])
                }
            }
        }
    }

    private func quickAmountButton(_ value: Int) -> some View {
        Button("$\(value)") {
            amount = Double(max(1, value))
            customAmountText = "\(max(1, value))"
        }
        .buttonStyle(WatchQuickTilePressStyle(enabled: compMotionOK))
        .frame(maxWidth: .infinity, alignment: .center)
        .foregroundColor(.black)
        .padding(.vertical, 4)
        .background(Color.green)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func parseFlexibleSeparatedIntegers(_ raw: String) -> [Int] {
        raw
            .replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { $0 > 0 }
    }

    private func mappedFoodBeverageKind(for context: String) -> FoodBeverageKind {
        let normalized = context.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.contains("beer") || normalized.contains("cocktail") || normalized.contains("drink") {
            return .drinks
        }
        if normalized.contains("food") || normalized.contains("meal") {
            return .meal
        }
        return .other
    }

    private func playSuccessHaptic() {
        #if os(watchOS)
        WKInterfaceDevice.current().play(.success)
        #endif
    }

    private func playClickHaptic() {
        #if os(watchOS)
        WKInterfaceDevice.current().play(.click)
        #endif
    }
}

private enum WatchCompEntryMode {
    case foodBeverage
    case cashValue
}

private struct WatchTierLadderBars: View {
    var motionEnabled: Bool
    var pulseSignal: Int
    @State private var heights: [CGFloat] = [5, 5, 5]

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.purple.opacity(0.88))
                    .frame(width: 7, height: heights[i])
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 22, alignment: .bottom)
        .onChange(of: pulseSignal) { _, new in
            guard motionEnabled, new > 0 else { return }
            heights = [5, 5, 5]
            withAnimation(.spring(response: 0.34, dampingFraction: 0.68)) {
                heights = [11, 18, 13]
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.52) {
                withAnimation(.easeOut(duration: 0.26)) {
                    heights = [6, 6, 6]
                }
            }
        }
    }
}

private struct WatchUpdateTierSheet: View {
    @EnvironmentObject var store: SessionStore
    @Environment(\.tierTapWatchAnimationsEnabled) private var tierTapWatchAnimationsEnabled
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var pointsDelta: Double = 0
    @State private var customTierDeltaText: String = "0"
    @State private var statusMessage: String?
    @State private var statusColor: Color = .green
    @State private var pendingTierPoints: Int?
    @State private var showConfirmUpdateTier = false
    @State private var tierLadderPulse = 0

    private var tierMotionOK: Bool {
        tierTapWatchAnimationsEnabled && !accessibilityReduceMotion
    }

    private var currentTierPoints: Int {
        store.liveSession?.startingTierPoints ?? 0
    }

    private var selectedTierDelta: Int {
        let custom = Int(customTierDeltaText.filter { $0.isNumber }) ?? 0
        if custom > 0 { return custom }
        return max(0, Int(pointsDelta))
    }

    private var proposedTierPoints: Int {
        currentTierPoints + selectedTierDelta
    }

    var body: some View {
        Form {
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption2.bold())
                    .foregroundColor(statusColor)
            }
            Text("Current tier: \(currentTierPoints)")
                .font(.caption2)
                .foregroundColor(.secondary)
                .contentTransition(.numericText())
                .animation(tierMotionOK ? .snappy : nil, value: currentTierPoints)
            ZStack {
                if tierMotionOK {
                    Circle()
                        .stroke(Color.purple.opacity(0.14), lineWidth: 3)
                        .frame(width: 54, height: 54)
                    Circle()
                        .trim(from: 0, to: CGFloat(min(pointsDelta / 12_000.0, 1.0)))
                        .stroke(Color.purple.opacity(0.78), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 54, height: 54)
                        .animation(tierMotionOK ? .easeOut(duration: 0.18) : nil, value: pointsDelta)
                }
                Text("Add points: \(selectedTierDelta)")
                    .font(.headline.monospacedDigit())
                    .contentTransition(.numericText())
                    .animation(tierMotionOK ? .snappy : nil, value: selectedTierDelta)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            Text("Proposed tier: \(proposedTierPoints)")
                .font(.caption2)
                .foregroundColor(.green)
                .contentTransition(.numericText())
                .animation(tierMotionOK ? .snappy : nil, value: proposedTierPoints)
            WatchTierLadderBars(motionEnabled: tierMotionOK, pulseSignal: tierLadderPulse)
            HStack {
                tierPresetButton(0)
                tierPresetButton(100)
            }
            HStack {
                tierPresetButton(500)
                tierPresetButton(1000)
            }
            Text("Custom points")
                .font(.caption2)
                .foregroundStyle(.secondary)
            WatchNumericDigitPad(text: $customTierDeltaText, allowSpace: false, maxLength: 8)
            Button("Update Tier") {
                showConfirmUpdateTier = true
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .center)
            .foregroundColor(.black)
            .padding(.vertical, 6)
            .background(Color.green)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .focusable(true)
        .digitalCrownRotation(
            $pointsDelta,
            from: 0,
            through: 500_000,
            by: 10,
            sensitivity: .low,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .localizedNavigationTitle("Update Tier")
        .alert("Update tier points?", isPresented: $showConfirmUpdateTier) {
            Button("No", role: .cancel) {}
            Button("Yes") {
                let selected = proposedTierPoints
                let immediate = SessionSyncManager.shared.isReachable
                pendingTierPoints = selected
                store.updateLiveSessionStartingTier(selected)
                statusMessage = immediate ? "Tier sent" : "Tier queued"
                statusColor = immediate ? .green : .orange
                if immediate { playSuccessHaptic() } else { playClickHaptic() }
            }
        } message: {
            Text("Set current tier points to \(proposedTierPoints)?")
        }
        .onAppear {
            pointsDelta = 0
            customTierDeltaText = "0"
        }
        .onChange(of: store.liveSession?.startingTierPoints) { newPoints in
            guard let expected = pendingTierPoints, let newPoints else { return }
            guard newPoints == expected else { return }
            pendingTierPoints = nil
            statusMessage = "Tier updated on iPhone"
            statusColor = .green
            playSuccessHaptic()
            if tierMotionOK {
                tierLadderPulse += 1
            }
            pointsDelta = 0
            customTierDeltaText = "0"
        }
    }

    private func tierPresetButton(_ value: Int) -> some View {
        Button("\(value)") {
            pointsDelta = Double(value)
            customTierDeltaText = "\(value)"
        }
        .buttonStyle(.bordered)
    }

    private func playSuccessHaptic() {
        #if os(watchOS)
        WKInterfaceDevice.current().play(.success)
        #endif
    }

    private func playClickHaptic() {
        #if os(watchOS)
        WKInterfaceDevice.current().play(.click)
        #endif
    }
}
