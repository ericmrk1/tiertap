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
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, minHeight: 72)
                    .background(Color.green)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }

                LazyVGrid(columns: metricColumns, spacing: 8) {
                    NavigationLink {
                        WatchAddBuyInSheet()
                            .environmentObject(store)
                    } label: {
                        metricButton(
                            title: "Buy-In",
                            value: "$\((s?.totalBuyIn ?? 0).formatted(.number.grouping(.automatic)))",
                            icon: "plus.circle.fill",
                            accent: .blue
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        WatchAddCompSheet()
                            .environmentObject(store)
                    } label: {
                        metricButton(
                            title: "Comps",
                            value: "$\((s?.totalComp ?? 0).formatted(.number.grouping(.automatic)))",
                            icon: "gift.fill",
                            accent: .cyan
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        WatchUpdateTierSheet()
                            .environmentObject(store)
                    } label: {
                        metricButton(
                            title: "Tier",
                            value: (s?.startingTierPoints ?? 0).formatted(.number.grouping(.automatic)),
                            icon: "chart.bar.fill",
                            accent: .purple
                        )
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
                metricButton(title: "TierTap", value: "Add Comp", icon: "gift.fill", accent: .cyan)
            }
        case "updateTier":
            NavigationLink {
                WatchUpdateTierSheet().environmentObject(store)
            } label: {
                metricButton(title: "TierTap", value: "Update Tier", icon: "chart.bar.fill", accent: .purple)
            }
        case "stopSession":
            Button {
                showConfirmFastCloseOut = true
            } label: {
                metricButton(title: "TierTap", value: "Stop", icon: "stop.circle.fill", accent: .red)
            }
        default:
            NavigationLink {
                WatchAddBuyInSheet().environmentObject(store)
            } label: {
                metricButton(title: "Quick", value: "Add Buy-In", icon: "plus.circle.fill", accent: .blue)
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

    private func metricButton(title: String, value: String, icon: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label {
                Text(title)
                    .font(.caption2)
                    .lineLimit(1)
            } icon: {
                Image(systemName: icon)
                    .font(.caption2)
            }
            .foregroundColor(.secondary)
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
                Button {
                    requestFastStartConfirmation(.poker)
                } label: {
                    Label(fastStartLabel(for: .poker, template: pokerTemplate), systemImage: iconName(for: .poker))
                }
            }
            if let tableTemplate {
                Button {
                    requestFastStartConfirmation(.table)
                } label: {
                    Label(fastStartLabel(for: .table, template: tableTemplate), systemImage: iconName(for: .table))
                }
            }
            if let slotsTemplate {
                Button {
                    requestFastStartConfirmation(.slots)
                } label: {
                    Label(fastStartLabel(for: .slots, template: slotsTemplate), systemImage: iconName(for: .slots))
                }
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
    @State private var amount: Double = 100
    @State private var customAmountText: String = "100"
    @State private var statusMessage: String?
    @State private var statusColor: Color = .green
    @State private var pendingExpectedTotal: Int?
    @State private var showConfirmAdd = false
    private let groupDefaults = UserDefaults(suiteName: "group.com.app.tiertap")

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
            Text("Amount: $\(selectedAmount)")
                .font(.headline.monospacedDigit())
            Text("Proposed total: $\(proposedTotal)")
                .font(.caption2)
                .foregroundColor(.green)
            quickAmountRows(amountPresetValues)
            TextField("Custom amount", text: $customAmountText)
                .onChange(of: customAmountText) { new in
                    let digits = new.filter { $0.isNumber }
                    if digits != new { customAmountText = digits }
                }
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

private struct WatchAddCompSheet: View {
    @EnvironmentObject var store: SessionStore
    @State private var amount: Double = 20
    @State private var customAmountText: String = "20"
    @State private var details = ""
    @State private var selectedCompEntryMode: WatchCompEntryMode?
    @State private var selectedContextIndex: Int = 0
    @State private var statusMessage: String?
    @State private var statusColor: Color = .green
    @State private var pendingExpectedCompTotal: Int?
    @State private var showConfirmAdd = false
    private let groupDefaults = UserDefaults(suiteName: "group.com.app.tiertap")
    private let contextGridColumns: [GridItem] = [GridItem(.flexible()), GridItem(.flexible())]

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
        Form {
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption2.bold())
                    .foregroundColor(statusColor)
            }
            Text("Current comps: $\(currentCompTotal)")
                .font(.caption2)
                .foregroundColor(.secondary)
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
                Text("Proposed comps: $\(proposedCompTotal)")
                    .font(.caption2)
                    .foregroundColor(.green)
                quickAmountRows(amountPresetValues)
                TextField("Custom comp", text: $customAmountText)
                    .onChange(of: customAmountText) { new in
                        let digits = new.filter { $0.isNumber }
                        if digits != new { customAmountText = digits }
                    }
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
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .foregroundColor(selectedContextIndex == index ? .black : .white)
                        .background(selectedContextIndex == index ? Color.green : Color.gray.opacity(0.22))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                Text("Estimated value: $\(selectedAmount)")
                    .font(.headline.monospacedDigit())
                Text("Proposed comps: $\(proposedCompTotal)")
                    .font(.caption2)
                    .foregroundColor(.green)
                quickAmountRows(amountPresetValues)
                TextField("Custom value", text: $customAmountText)
                    .onChange(of: customAmountText) { new in
                        let digits = new.filter { $0.isNumber }
                        if digits != new { customAmountText = digits }
                    }
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
                .frame(maxWidth: .infinity, alignment: .center)
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
