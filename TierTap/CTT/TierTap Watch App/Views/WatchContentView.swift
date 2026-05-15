import SwiftUI
#if os(watchOS)
import WatchKit
#endif

/// Watch app is strictly a remote control for the live session on iPhone.
struct WatchContentView: View {
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject private var themeStore: TierTapThemeStore
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

                WatchTierTapLogo(style: .header)
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 2, trailing: 0))
                    .listRowBackground(Color.clear)

                NavigationLink {
                    WatchLiveView()
                } label: {
                    Label("Live Remote", systemImage: "dot.radiowaves.left.and.right")
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
            .scrollContentBackground(.hidden)
        }
        .watchThemedScreen()
        .tint(themeStore.primaryColor)
        .onAppear {
            themeStore.reload()
            refreshWatchStateFromPhone()
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                themeStore.reload()
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
    @EnvironmentObject private var themeStore: TierTapThemeStore
    private let groupDefaults = UserDefaults(suiteName: "group.com.app.tiertap")
    @State private var showPrimaryColorPicker = false
    @State private var showSecondaryColorPicker = false
    @State private var watchHapticsEnabled = true
    @State private var watchSessionPulseEnabled = true
    @State private var watchSessionPulseMinutes = 20
    @State private var watchWristRaiseSummaryEnabled = true
    @State private var watchHapticProfile = "classic"
    @State private var watchBuyInCashDefaults = "20 100 200 500"
    @State private var watchCompCashDefaults = "20 50 100 500"
    @State private var watchCompContextOptions = "Cocktail, Beer, Food, Cash"
    @State private var watchAnimationsEnabled = true

    var body: some View {
        Form {
            Section("Theme & colors") {
                Text("Presets")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(themeStore.themePresets) { preset in
                    Button {
                        themeStore.applyThemePreset(preset)
                    } label: {
                        HStack(spacing: 8) {
                            let colors = TierTapThemeSettings.colors(for: preset)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    LinearGradient(
                                        colors: [colors.0, colors.1],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 28, height: 14)
                            Text(preset.name)
                                .font(.caption)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            if themeStore.isPresetSelected(preset) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                Button("Save current as preset") {
                    themeStore.saveCurrentThemeAsPreset()
                }
                .font(.caption)

                Button {
                    showPrimaryColorPicker = true
                } label: {
                    HStack {
                        Text("Primary color")
                        Spacer()
                        Circle()
                            .fill(themeStore.primaryColor)
                            .frame(width: 18, height: 18)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    showSecondaryColorPicker = true
                } label: {
                    HStack {
                        Text("Secondary color")
                        Spacer()
                        Circle()
                            .fill(themeStore.secondaryColor)
                            .frame(width: 18, height: 18)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                RoundedRectangle(cornerRadius: 8)
                    .fill(themeStore.primaryGradient)
                    .frame(height: 28)
                    .overlay {
                        Text("Preview")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.9))
                    }
            }

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
            Text("Buy-in quick picks")
                .font(.caption2)
                .foregroundStyle(.secondary)
            WatchNumericDigitPad(text: $watchBuyInCashDefaults, allowSpace: true, maxLength: 48)
            Text("Comp quick picks")
                .font(.caption2)
                .foregroundStyle(.secondary)
            WatchNumericDigitPad(text: $watchCompCashDefaults, allowSpace: true, maxLength: 48)
            TextField("Comp type options", text: $watchCompContextOptions)
        }
        .scrollContentBackground(.hidden)
        .watchThemedScreen()
        .tint(themeStore.primaryColor)
        .localizedNavigationTitle("Watch Settings")
        .onAppear {
            themeStore.reload()
            load()
        }
        .sheet(isPresented: $showPrimaryColorPicker) {
            WatchThemeColorPickerSheet(
                title: "Primary color",
                selectedName: themeStore.primaryColorName
            ) { color in
                themeStore.setPrimaryColor(color)
            }
        }
        .sheet(isPresented: $showSecondaryColorPicker) {
            WatchThemeColorPickerSheet(
                title: "Secondary color",
                selectedName: themeStore.secondaryColorName
            ) { color in
                themeStore.setSecondaryColor(color)
            }
        }
        .onChange(of: watchHapticsEnabled) { _ in save() }
        .onChange(of: watchAnimationsEnabled) { _ in save() }
        .onChange(of: watchSessionPulseEnabled) { _ in save() }
        .onChange(of: watchSessionPulseMinutes) { _ in save() }
        .onChange(of: watchWristRaiseSummaryEnabled) { _ in save() }
        .onChange(of: watchHapticProfile) { _ in save() }
        .onChange(of: watchBuyInCashDefaults) { _ in save() }
        .onChange(of: watchCompCashDefaults) { _ in save() }
        .onChange(of: watchCompContextOptions) { _ in save() }
    }

    private func load() {
        watchAnimationsEnabled = TierTapWatchAnimationsSettings.isEnabled(userDefaults: groupDefaults)
        watchHapticsEnabled = groupDefaults?.object(forKey: "ctt_watch_haptics_enabled") as? Bool ?? true
        watchSessionPulseEnabled = groupDefaults?.object(forKey: "ctt_watch_session_pulse_enabled") as? Bool ?? true
        let pulse = groupDefaults?.integer(forKey: "ctt_watch_session_pulse_minutes") ?? 20
        watchSessionPulseMinutes = max(1, pulse)
        watchWristRaiseSummaryEnabled = groupDefaults?.object(forKey: "ctt_watch_wrist_raise_summary_enabled") as? Bool ?? true
        watchHapticProfile = groupDefaults?.string(forKey: "ctt_watch_haptic_profile") ?? "classic"
        watchBuyInCashDefaults = groupDefaults?.string(forKey: "ctt_watch_buyin_cash_defaults") ?? "20 100 200 500"
        watchCompCashDefaults = groupDefaults?.string(forKey: "ctt_watch_comp_cash_defaults") ?? "20 50 100 500"
        watchCompContextOptions = groupDefaults?.string(forKey: "ctt_watch_comp_context_options") ?? "Cocktail, Beer, Food, Cash"
    }

    private func save() {
        groupDefaults?.set(watchAnimationsEnabled, forKey: TierTapWatchAnimationsSettings.userDefaultsKey)
        groupDefaults?.set(watchHapticsEnabled, forKey: "ctt_watch_haptics_enabled")
        groupDefaults?.set(watchSessionPulseEnabled, forKey: "ctt_watch_session_pulse_enabled")
        groupDefaults?.set(max(1, watchSessionPulseMinutes), forKey: "ctt_watch_session_pulse_minutes")
        groupDefaults?.set(watchWristRaiseSummaryEnabled, forKey: "ctt_watch_wrist_raise_summary_enabled")
        groupDefaults?.set(watchHapticProfile, forKey: "ctt_watch_haptic_profile")
        let normalizedBuyInDefaults = normalizeNumbersDelimiter(watchBuyInCashDefaults)
        let normalizedCashDefaults = watchCompCashDefaults
            .replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        groupDefaults?.set(normalizedBuyInDefaults, forKey: "ctt_watch_buyin_cash_defaults")
        groupDefaults?.set(normalizedCashDefaults, forKey: "ctt_watch_comp_cash_defaults")
        groupDefaults?.set(watchCompContextOptions, forKey: "ctt_watch_comp_context_options")
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
    @EnvironmentObject private var themeStore: TierTapThemeStore
    @Environment(\.watchTheme) private var theme
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
        .scrollContentBackground(.hidden)
        .watchThemedScreen()
        .tint(theme.primary)
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
            themeStore.reload()
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
        .alert("Publish to Community?", isPresented: $confirmCommunityPublish) {
            Button("Cancel", role: .cancel) {}
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
    @EnvironmentObject private var themeStore: TierTapThemeStore
    @Environment(\.watchTheme) private var theme
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
                                .foregroundColor(entry.delivery == .sent ? theme.primary : theme.secondary)
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
        .scrollContentBackground(.hidden)
        .watchThemedScreen()
        .tint(theme.primary)
        .localizedNavigationTitle("Remotes")
        .onAppear { themeStore.reload() }
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
