import SwiftUI
#if os(watchOS)
import WatchKit
#endif

struct WatchLiveView: View {
    @EnvironmentObject var store: SessionStore
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var syncManager = SessionSyncManager.shared
    @State private var feedbackMessage: String?
    @State private var feedbackColor: Color = .green
    @State private var showConfirmFastCloseOut = false
    @State private var showFastStartSheet = false
    @State private var showWristSummary = false
    @State private var lastPulseMinuteMark: Int = -1
    private let syncTicker = Timer.publish(every: 8, on: .main, in: .common).autoconnect()
    @State private var lastAppGroupSnapshotRevision: Int = 0

    private var s: Session? { store.liveSession }
    private var hasLiveSession: Bool { store.liveSession != nil }
    private var isSessionPaused: Bool { s?.endTime != nil }
    private let metricColumns: [GridItem] = [GridItem(.flexible()), GridItem(.flexible())]
    private let groupDefaults = UserDefaults(suiteName: "group.com.app.tiertap")

    /// Elapsed play time for the current live session (frozen while paused via `endTime`).
    private func liveElapsedSeconds(at date: Date) -> TimeInterval {
        guard let live = store.liveSession else { return 0 }
        let end = live.endTime ?? date
        return max(0, end.timeIntervalSince(live.startTime))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image("TierTap_C_PokerChip")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
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

                // TimelineView drives the clock reliably on watchOS (Timer.publish often does not tick here).
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
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }

                LazyVGrid(columns: metricColumns, spacing: 8) {
                    NavigationLink {
                        WatchAddBuyInSheet()
                            .environmentObject(store)
                    } label: {
                        metricButton(title: "Buy-In", value: "$\((s?.totalBuyIn ?? 0).formatted(.number.grouping(.automatic)))", accent: .blue)
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        WatchAddCompSheet()
                            .environmentObject(store)
                    } label: {
                        metricButton(title: "Comps", value: "$\((s?.totalComp ?? 0).formatted(.number.grouping(.automatic)))", accent: .cyan)
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        WatchUpdateTierSheet()
                            .environmentObject(store)
                    } label: {
                        metricButton(title: "Tier", value: (s?.startingTierPoints ?? 0).formatted(.number.grouping(.automatic)), accent: .purple)
                    }
                    .buttonStyle(.plain)

                    quickActionTile
                    .buttonStyle(.plain)
                }

                if let feedbackMessage {
                    Text(feedbackMessage)
                        .font(.caption2)
                        .foregroundColor(feedbackColor)
                        .lineLimit(2)
                }

                if let prog = s?.rewardsProgramName?.trimmingCharacters(in: .whitespacesAndNewlines), !prog.isEmpty {
                    Text(prog)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }

                Divider()
                    .padding(.vertical, 2)

                Button {
                    triggerWatchAction(name: "Pause Session") {
                        store.stopLiveSessionTimer()
                    }
                } label: {
                    buttonLabel("Pause Session", icon: "pause.circle.fill")
                }
                .buttonStyle(.bordered)
                .disabled(!hasLiveSession || isSessionPaused)

                Button {
                    triggerWatchAction(name: "Resume Session") {
                        store.resumeLiveSessionTimer()
                    }
                } label: {
                    buttonLabel("Continue Session", icon: "play.circle.fill")
                }
                .buttonStyle(.bordered)
                .disabled(!hasLiveSession || !isSessionPaused)

                Button(role: .destructive) {
                    showConfirmFastCloseOut = true
                } label: {
                    buttonLabel("Stop Session", icon: "stop.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)

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
        .alert("Fast close out session?", isPresented: $showConfirmFastCloseOut) {
            Button("No", role: .cancel) {}
            Button("Yes", role: .destructive) {
                triggerWatchAction(name: "Fast Close Out") {
                    store.fastCloseSessionWithDefaultsUnverified()
                }
            }
        } message: {
            Text("This will end the live session immediately using default close-out values.")
        }
        .sheet(isPresented: $showFastStartSheet) {
            WatchFastStartSheet()
                .environmentObject(store)
        }
    }

    private var primaryTimerButtonTitle: String {
        if !hasLiveSession { return "Start Session" }
        return isSessionPaused ? "Continue Session" : "Pause Session"
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

    private var watchQuickAction: String {
        groupDefaults?.string(forKey: "ctt_watch_quick_action") ?? "addBuyIn"
    }

    @ViewBuilder
    private var quickActionTile: some View {
        switch watchQuickAction {
        case "addComp":
            NavigationLink {
                WatchAddCompSheet().environmentObject(store)
            } label: {
                metricButton(title: "Quick", value: "Add Comp", accent: .cyan)
            }
        case "updateTier":
            NavigationLink {
                WatchUpdateTierSheet().environmentObject(store)
            } label: {
                metricButton(title: "Quick", value: "Update Tier", accent: .purple)
            }
        case "stopSession":
            Button {
                showConfirmFastCloseOut = true
            } label: {
                metricButton(title: "Quick", value: "Stop", accent: .red)
            }
        default:
            NavigationLink {
                WatchAddBuyInSheet().environmentObject(store)
            } label: {
                metricButton(title: "Quick", value: "Add Buy-In", accent: .blue)
            }
        }
    }

    private func handlePrimaryTimerAction() {
        if !hasLiveSession {
            showFastStartSheet = true
            return
        }
        if isSessionPaused {
            triggerWatchAction(name: "Resume Session") {
                store.resumeLiveSessionTimer()
            }
        } else {
            triggerWatchAction(name: "Pause Session") {
                store.stopLiveSessionTimer()
            }
        }
    }

    private func metricButton(title: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.footnote.monospacedDigit().bold())
                .foregroundColor(accent)
                .lineLimit(1)
            Text("+")
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(Color.gray.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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

private struct WatchFastStartSheet: View {
    @EnvironmentObject var store: SessionStore
    @Environment(\.dismiss) private var dismiss
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

    var body: some View {
        List {
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption2.bold())
                    .foregroundColor(statusColor)
            }
            if let pokerTemplate {
                Button(fastStartLabel(for: .poker, template: pokerTemplate)) { requestFastStartConfirmation(.poker) }
            }
            if let tableTemplate {
                Button(fastStartLabel(for: .table, template: tableTemplate)) { requestFastStartConfirmation(.table) }
            }
            if let slotsTemplate {
                Button(fastStartLabel(for: .slots, template: slotsTemplate)) { requestFastStartConfirmation(.slots) }
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
    @State private var amount: Double = 100
    @State private var customAmountText: String = "100"
    @State private var statusMessage: String?
    @State private var statusColor: Color = .green
    @State private var pendingExpectedTotal: Int?
    @State private var showConfirmAdd = false

    private var currentTotalBuyIn: Int {
        store.liveSession?.totalBuyIn ?? 0
    }

    private var selectedAmount: Int {
        let custom = Int(customAmountText.filter { $0.isNumber }) ?? 0
        if custom > 0 { return custom }
        return max(20, Int(amount))
    }

    private var proposedTotal: Int {
        currentTotalBuyIn + selectedAmount
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
            Text("Amount: $\(selectedAmount)")
                .font(.headline.monospacedDigit())
            Text("Proposed total: $\(proposedTotal)")
                .font(.caption2)
                .foregroundColor(.green)
            HStack {
                quickAmountButton(20)
                quickAmountButton(100)
            }
            HStack {
                quickAmountButton(200)
                quickAmountButton(500)
            }
            TextField("Custom amount", text: $customAmountText)
                .onChange(of: customAmountText) { new in
                    let digits = new.filter { $0.isNumber }
                    if digits != new { customAmountText = digits }
                }
            Button("Add Buy-In") {
                showConfirmAdd = true
            }
        }
        .focusable(true)
        .digitalCrownRotation(
            $amount,
            from: 20,
            through: 20_000,
            by: 20,
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
            Text("Add $\(selectedAmount) buy-in? New total will be $\(proposedTotal).")
        }
        .onChange(of: store.liveSession?.totalBuyIn) { newTotal in
            guard let expected = pendingExpectedTotal, let newTotal else { return }
            guard newTotal >= expected else { return }
            pendingExpectedTotal = nil
            statusMessage = "Buy-in updated on iPhone"
            statusColor = .green
            playSuccessHaptic()
        }
        .onAppear {
            customAmountText = "\(max(20, Int(amount)))"
        }
    }

    private func quickAmountButton(_ value: Int) -> some View {
        Button("$\(value)") {
            amount = Double(value)
            customAmountText = "\(value)"
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

private struct WatchAddCompSheet: View {
    @EnvironmentObject var store: SessionStore
    @State private var amount: Double = 20
    @State private var customAmountText: String = "20"
    @State private var details = ""
    @State private var statusMessage: String?
    @State private var statusColor: Color = .green
    @State private var pendingExpectedCompTotal: Int?
    @State private var showConfirmAdd = false

    private var currentCompTotal: Int {
        store.liveSession?.totalComp ?? 0
    }

    private var selectedAmount: Int {
        let custom = Int(customAmountText.filter { $0.isNumber }) ?? 0
        if custom > 0 { return custom }
        return max(20, Int(amount))
    }

    private var proposedCompTotal: Int {
        currentCompTotal + selectedAmount
    }

    var body: some View {
        Form {
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption2.bold())
                    .foregroundColor(statusColor)
            }
            Text("Current comps: $\(currentCompTotal)")
                .font(.caption2)
                .foregroundColor(.secondary)
            Text("Comp: $\(selectedAmount)")
                .font(.headline.monospacedDigit())
            Text("Proposed comps: $\(proposedCompTotal)")
                .font(.caption2)
                .foregroundColor(.green)
            HStack {
                quickAmountButton(20)
                quickAmountButton(50)
            }
            HStack {
                quickAmountButton(100)
                quickAmountButton(200)
            }
            TextField("Custom comp", text: $customAmountText)
                .onChange(of: customAmountText) { new in
                    let digits = new.filter { $0.isNumber }
                    if digits != new { customAmountText = digits }
                }
            TextField("Details (optional)", text: $details)
            Button("Add Comp") {
                showConfirmAdd = true
            }
        }
        .focusable(true)
        .digitalCrownRotation(
            $amount,
            from: 20,
            through: 10_000,
            by: 20,
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
                store.addComp(amount: selected, details: trimmed.isEmpty ? nil : trimmed)
                statusMessage = immediate ? "Comp sent" : "Comp queued"
                statusColor = immediate ? .green : .orange
                if immediate { playSuccessHaptic() } else { playClickHaptic() }
                details = ""
            }
        } message: {
            Text("Add $\(selectedAmount) comp? New comp total will be $\(proposedCompTotal).")
        }
        .onChange(of: store.liveSession?.totalComp) { newTotal in
            guard let expected = pendingExpectedCompTotal, let newTotal else { return }
            guard newTotal >= expected else { return }
            pendingExpectedCompTotal = nil
            statusMessage = "Comp updated on iPhone"
            statusColor = .green
            playSuccessHaptic()
        }
        .onAppear {
            customAmountText = "\(max(20, Int(amount)))"
        }
    }

    private func quickAmountButton(_ value: Int) -> some View {
        Button("$\(value)") {
            amount = Double(value)
            customAmountText = "\(value)"
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

private struct WatchUpdateTierSheet: View {
    @EnvironmentObject var store: SessionStore
    @State private var pointsDelta: Double = 0
    @State private var customTierDeltaText: String = "0"
    @State private var statusMessage: String?
    @State private var statusColor: Color = .green
    @State private var pendingTierPoints: Int?
    @State private var showConfirmUpdateTier = false

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
            Text("Add points: \(selectedTierDelta)")
                .font(.headline.monospacedDigit())
            Text("Proposed tier: \(proposedTierPoints)")
                .font(.caption2)
                .foregroundColor(.green)
            HStack {
                tierPresetButton(0)
                tierPresetButton(100)
            }
            HStack {
                tierPresetButton(500)
                tierPresetButton(1000)
            }
            TextField("Custom points", text: $customTierDeltaText)
                .onChange(of: customTierDeltaText) { new in
                    let digits = new.filter { $0.isNumber }
                    if digits != new { customTierDeltaText = digits }
                }
            Button("Update Tier") {
                showConfirmUpdateTier = true
            }
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
