import SwiftUI
#if os(watchOS)
import WatchKit
#endif

/// Watch app is strictly a remote control for the live session on iPhone.
struct WatchContentView: View {
    @EnvironmentObject var store: SessionStore
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var syncManager = SessionSyncManager.shared
    private let syncTicker = Timer.publish(every: 6, on: .main, in: .common).autoconnect()
    @State private var lastAppGroupSnapshotRevision: Int = 0

    var body: some View {
        NavigationStack {
            List {
                VStack(alignment: .leading, spacing: 2) {
                    Text(syncManager.syncStatusMessage)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if let lastSyncAt = syncManager.lastSyncAt {
                        Text("Last sync \(lastSyncAt, style: .time)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 2)
                #if targetEnvironment(simulator)
                WatchSyncDebugPanel()
                #endif

                NavigationLink {
                    WatchLiveView()
                } label: {
                    Label("Live Remote", systemImage: "dot.radiowaves.left.and.right")
                }

                NavigationLink {
                    WatchVisualsView()
                        .environmentObject(store)
                } label: {
                    Label("Visuals", systemImage: "swatchpalette")
                }

                NavigationLink {
                    WatchHistoryView()
                        .environmentObject(store)
                } label: {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }

                NavigationLink {
                    WatchRemotesView()
                } label: {
                    Label("Remotes", systemImage: "dot.radiowaves.up.forward")
                }

                NavigationLink {
                    WatchSettingsView()
                } label: {
                    Label("Watch Settings", systemImage: "gearshape")
                }
            }
            .localizedNavigationTitle("TierTap")
        }
        .onAppear {
            refreshWatchStateFromPhone()
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                refreshWatchStateFromPhone()
            }
        }
        .onReceive(syncTicker) { _ in
            refreshWatchStateFromPhone()
        }
    }

    private func refreshWatchStateFromPhone() {
        SessionSyncManager.shared.requestContext { sessions, liveSession in
            guard !sessions.isEmpty || liveSession != nil else { return }
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
}

private struct WatchSettingsView: View {
    private let groupDefaults = UserDefaults(suiteName: "group.com.app.tiertap")
    @State private var watchHapticsEnabled = true
    @State private var watchSessionPulseEnabled = true
    @State private var watchSessionPulseMinutes = 20
    @State private var watchWristRaiseSummaryEnabled = true
    @State private var watchHapticProfile = "classic"
    @State private var watchQuickAction = "updateStack"
    @State private var watchBuyInCashDefaults = "20 100 200 500"
    @State private var watchCompCashDefaults = "20 50 100 500"
    @State private var watchCompContextOptions = "Cocktail, Beer, Food, Cash"
    @State private var watchVisualsAutoScrollEnabled = false
    @State private var watchVisualsAutoScrollSeconds = 6
    @State private var watchAnimationsEnabled = true

    var body: some View {
        Form {
            Toggle("Watch haptics", isOn: $watchHapticsEnabled)
            Toggle("Animations", isOn: $watchAnimationsEnabled)
            Picker("Haptic profile", selection: $watchHapticProfile) {
                Text("Classic").tag("classic")
                Text("Subtle").tag("subtle")
                Text("Assertive").tag("assertive")
            }
            Toggle("Session pulse reminders", isOn: $watchSessionPulseEnabled)
            Picker("Pulse every", selection: $watchSessionPulseMinutes) {
                Text("10 min").tag(10)
                Text("15 min").tag(15)
                Text("20 min").tag(20)
                Text("30 min").tag(30)
                Text("45 min").tag(45)
                Text("60 min").tag(60)
            }
            Toggle("Wrist-raise summary", isOn: $watchWristRaiseSummaryEnabled)
            Picker("Quick action", selection: $watchQuickAction) {
                Text("Update Stack").tag("updateStack")
                Text("Add Buy-In").tag("addBuyIn")
                Text("Add Comp").tag("addComp")
                Text("Update Tier").tag("updateTier")
                Text("Stop Session").tag("stopSession")
            }
            TextField("Buy-in cash defaults", text: $watchBuyInCashDefaults)
            TextField("Comp cash defaults", text: $watchCompCashDefaults)
            TextField("Comp type options", text: $watchCompContextOptions)
            Toggle("Visuals auto-scroll", isOn: $watchVisualsAutoScrollEnabled)
            Picker("Visuals scroll every", selection: $watchVisualsAutoScrollSeconds) {
                Text("3 sec").tag(3)
                Text("4 sec").tag(4)
                Text("5 sec").tag(5)
                Text("6 sec").tag(6)
                Text("8 sec").tag(8)
                Text("10 sec").tag(10)
            }
        }
        .localizedNavigationTitle("Watch Settings")
        .onAppear(perform: load)
        .onChange(of: watchHapticsEnabled) { _ in save() }
        .onChange(of: watchAnimationsEnabled) { _ in save() }
        .onChange(of: watchSessionPulseEnabled) { _ in save() }
        .onChange(of: watchSessionPulseMinutes) { _ in save() }
        .onChange(of: watchWristRaiseSummaryEnabled) { _ in save() }
        .onChange(of: watchHapticProfile) { _ in save() }
        .onChange(of: watchQuickAction) { _ in save() }
        .onChange(of: watchBuyInCashDefaults) { _ in save() }
        .onChange(of: watchCompCashDefaults) { _ in save() }
        .onChange(of: watchCompContextOptions) { _ in save() }
        .onChange(of: watchVisualsAutoScrollEnabled) { _ in save() }
        .onChange(of: watchVisualsAutoScrollSeconds) { _ in save() }
    }

    private func load() {
        watchAnimationsEnabled = TierTapWatchAnimationsSettings.isEnabled(userDefaults: groupDefaults)
        watchHapticsEnabled = groupDefaults?.object(forKey: "ctt_watch_haptics_enabled") as? Bool ?? true
        watchSessionPulseEnabled = groupDefaults?.object(forKey: "ctt_watch_session_pulse_enabled") as? Bool ?? true
        let pulse = groupDefaults?.integer(forKey: "ctt_watch_session_pulse_minutes") ?? 20
        watchSessionPulseMinutes = max(1, pulse)
        watchWristRaiseSummaryEnabled = groupDefaults?.object(forKey: "ctt_watch_wrist_raise_summary_enabled") as? Bool ?? true
        watchHapticProfile = groupDefaults?.string(forKey: "ctt_watch_haptic_profile") ?? "classic"
        watchQuickAction = groupDefaults?.string(forKey: "ctt_watch_quick_action") ?? "updateStack"
        watchBuyInCashDefaults = groupDefaults?.string(forKey: "ctt_watch_buyin_cash_defaults") ?? "20 100 200 500"
        watchCompCashDefaults = groupDefaults?.string(forKey: "ctt_watch_comp_cash_defaults") ?? "20 50 100 500"
        watchCompContextOptions = groupDefaults?.string(forKey: "ctt_watch_comp_context_options") ?? "Cocktail, Beer, Food, Cash"
        watchVisualsAutoScrollEnabled = groupDefaults?.object(forKey: "ctt_watch_visuals_auto_scroll_enabled") as? Bool ?? false
        let visualsSeconds = groupDefaults?.integer(forKey: "ctt_watch_visuals_auto_scroll_seconds") ?? 6
        watchVisualsAutoScrollSeconds = max(3, visualsSeconds)
    }

    private func save() {
        groupDefaults?.set(watchAnimationsEnabled, forKey: TierTapWatchAnimationsSettings.userDefaultsKey)
        groupDefaults?.set(watchHapticsEnabled, forKey: "ctt_watch_haptics_enabled")
        groupDefaults?.set(watchSessionPulseEnabled, forKey: "ctt_watch_session_pulse_enabled")
        groupDefaults?.set(max(1, watchSessionPulseMinutes), forKey: "ctt_watch_session_pulse_minutes")
        groupDefaults?.set(watchWristRaiseSummaryEnabled, forKey: "ctt_watch_wrist_raise_summary_enabled")
        groupDefaults?.set(watchHapticProfile, forKey: "ctt_watch_haptic_profile")
        groupDefaults?.set(watchQuickAction, forKey: "ctt_watch_quick_action")
        let normalizedBuyInDefaults = normalizeNumbersDelimiter(watchBuyInCashDefaults)
        let normalizedCashDefaults = watchCompCashDefaults
            .replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        groupDefaults?.set(normalizedBuyInDefaults, forKey: "ctt_watch_buyin_cash_defaults")
        groupDefaults?.set(normalizedCashDefaults, forKey: "ctt_watch_comp_cash_defaults")
        groupDefaults?.set(watchCompContextOptions, forKey: "ctt_watch_comp_context_options")
        groupDefaults?.set(watchVisualsAutoScrollEnabled, forKey: "ctt_watch_visuals_auto_scroll_enabled")
        groupDefaults?.set(max(3, watchVisualsAutoScrollSeconds), forKey: "ctt_watch_visuals_auto_scroll_seconds")
    }

    private func normalizeNumbersDelimiter(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

#if targetEnvironment(simulator)
private struct WatchSyncDebugPanel: View {
    @ObservedObject private var syncManager = SessionSyncManager.shared

    private var liveSessionShortID: String {
        guard let id = syncManager.liveSessionID else { return "none" }
        return String(id.uuidString.prefix(8))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Sync Debug (Simulator)")
                .font(.caption2.bold())
                .foregroundColor(.orange)
            Text("Activation: \(syncManager.activationState.rawValue)")
                .font(.caption2)
                .foregroundColor(.secondary)
            Text("Reachable: \(syncManager.isReachable ? "yes" : "no")")
                .font(.caption2)
                .foregroundColor(.secondary)
            Text("Paired: \(syncManager.isPaired ? "yes" : "no")")
                .font(.caption2)
                .foregroundColor(.secondary)
            Text("Companion app: \(syncManager.isCompanionAppInstalled ? "installed" : "missing")")
                .font(.caption2)
                .foregroundColor(.secondary)
            Text("Cached sessions: \(syncManager.cachedSessionCount)")
                .font(.caption2)
                .foregroundColor(.secondary)
            Text("Live session id: \(liveSessionShortID)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}
#endif

struct WatchHistoryView: View {
    @EnvironmentObject var store: SessionStore
    @State private var isRefreshing = false

    private var sessions: [Session] {
        store.sessions.sorted { ($0.endTime ?? $0.startTime) > ($1.endTime ?? $1.startTime) }
    }

    var body: some View {
        List {
            if sessions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No session history yet")
                        .font(.caption)
                    Text("Your iPhone session summaries will appear here.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                ForEach(sessions.prefix(100)) { session in
                    NavigationLink {
                        WatchSessionDetailView(session: session)
                            .environmentObject(store)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.casino.isEmpty ? "Unknown casino" : session.casino)
                                .font(.caption.bold())
                                .lineLimit(1)
                            Text(session.game.isEmpty ? "Unknown game" : session.game)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                Text(Session.durationString(session.duration))
                                if let wl = session.winLoss {
                                    Text("•")
                                    Text("W/L \(wl >= 0 ? "+" : "")\(wl)")
                                }
                            }
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            Text(session.endTime ?? session.startTime, style: .date)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .localizedNavigationTitle("History")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    refreshFromPhone()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isRefreshing)
            }
        }
        .onAppear {
            refreshFromPhone()
        }
    }

    private func refreshFromPhone() {
        isRefreshing = true
        SessionSyncManager.shared.requestContext { sessions, liveSession in
            DispatchQueue.main.async {
                store.applySyncedState(sessions: sessions, liveSession: liveSession)
                isRefreshing = false
            }
        }
    }
}

private struct WatchSessionDetailView: View {
    let session: Session
    @EnvironmentObject private var store: SessionStore
    @ObservedObject private var syncManager = SessionSyncManager.shared
    @State private var statusMessage: String?
    @State private var confirmCommunityPublish = false
    private let groupDefaults = UserDefaults(suiteName: "group.com.app.tiertap")

    private var resolvedSession: Session {
        store.sessions.first(where: { $0.id == session.id }) ?? session
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

    private var shareText: String {
        let s = resolvedSession
        let dateText = s.startTime.formatted(date: .abbreviated, time: .shortened)
        let durationText = Session.durationString(s.duration)
        let buyInText = "\(currencySymbol)\(s.totalBuyIn)"
        let compsText = s.totalComp > 0 ? " • Comps \(currencySymbol)\(s.totalComp)" : ""
        let wlText: String
        if let wl = s.winLoss {
            wlText = " • W/L \(wl >= 0 ? "+" : "-")\(currencySymbol)\(abs(wl))"
        } else if let cashOut = s.cashOut {
            wlText = " • Cash out \(currencySymbol)\(cashOut)"
        } else {
            wlText = ""
        }
        return "\(dateText) at \(s.casino): \(s.game), \(durationText), buy-in \(buyInText)\(compsText)\(wlText)"
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(resolvedSession.casino.isEmpty ? "Unknown casino" : resolvedSession.casino)
                        .font(.caption.bold())
                    Text(resolvedSession.game.isEmpty ? "Unknown game" : resolvedSession.game)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(resolvedSession.endTime ?? resolvedSession.startTime, style: .date)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 2)
            }

            Section("Session") {
                LabeledContent("Duration", value: Session.durationString(resolvedSession.duration))
                LabeledContent("Buy-in", value: "\(currencySymbol)\(resolvedSession.totalBuyIn)")
                LabeledContent("Comps", value: "\(currencySymbol)\(resolvedSession.totalComp)")
                if let wl = resolvedSession.winLoss {
                    LabeledContent("W/L", value: "\(wl >= 0 ? "+" : "")\(currencySymbol)\(abs(wl))")
                }
            }

            Section("Share") {
                ShareLink(item: shareText) {
                    Label("Share Text", systemImage: "square.and.arrow.up")
                }

                Button {
                    confirmCommunityPublish = true
                } label: {
                    Label("Share to Community", systemImage: "paperplane.circle.fill")
                }
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .localizedNavigationTitle("Session")
        .confirmationDialog(
            "Publish to Community?",
            isPresented: $confirmCommunityPublish,
            titleVisibility: .visible
        ) {
            Button("Publish") {
                let immediate = syncManager.isReachable
                store.requestWatchCommunityPublishFromWatch(sessionId: resolvedSession.id) { ok, message in
                    statusMessage = message
                    if ok {
                        playHaptic(immediate: immediate)
                    } else {
                        WKInterfaceDevice.current().play(.failure)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Uses your Community screen name and tier/hour only (no wins, comps, or comment). TierTap on iPhone publishes in the background — no share sheet on the phone.")
        }
    }

    private func playHaptic(immediate: Bool) {
        #if os(watchOS)
        WKInterfaceDevice.current().play(immediate ? .success : .click)
        #endif
    }
}

struct WatchRemotesView: View {
    @ObservedObject private var syncManager = SessionSyncManager.shared

    var body: some View {
        List {
            if syncManager.remoteCommandLog.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No remote commands yet")
                        .font(.caption)
                    Text("Commands sent from this watch will appear here.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                ForEach(syncManager.remoteCommandLog) { entry in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(entry.action)
                                .font(.caption.bold())
                                .lineLimit(1)
                            Spacer()
                            Text(entry.delivery == .sent ? "sent" : "queued")
                                .font(.caption2.bold())
                                .foregroundColor(entry.delivery == .sent ? .green : .orange)
                        }
                        if entry.paramsSummary != "-" {
                            Text(entry.paramsSummary)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                        Text(entry.timestamp, style: .time)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .localizedNavigationTitle("Remotes")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    syncManager.clearRemoteCommandLog()
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(syncManager.remoteCommandLog.isEmpty)
            }
        }
    }
}
