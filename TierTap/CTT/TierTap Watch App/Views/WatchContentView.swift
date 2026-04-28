import SwiftUI

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
    @State private var watchQuickAction = "addBuyIn"

    var body: some View {
        Form {
            Toggle("Watch haptics", isOn: $watchHapticsEnabled)
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
                Text("Add Buy-In").tag("addBuyIn")
                Text("Add Comp").tag("addComp")
                Text("Update Tier").tag("updateTier")
                Text("Stop Session").tag("stopSession")
            }
        }
        .localizedNavigationTitle("Watch Settings")
        .onAppear(perform: load)
        .onChange(of: watchHapticsEnabled) { _ in save() }
        .onChange(of: watchSessionPulseEnabled) { _ in save() }
        .onChange(of: watchSessionPulseMinutes) { _ in save() }
        .onChange(of: watchWristRaiseSummaryEnabled) { _ in save() }
        .onChange(of: watchHapticProfile) { _ in save() }
        .onChange(of: watchQuickAction) { _ in save() }
    }

    private func load() {
        watchHapticsEnabled = groupDefaults?.object(forKey: "ctt_watch_haptics_enabled") as? Bool ?? true
        watchSessionPulseEnabled = groupDefaults?.object(forKey: "ctt_watch_session_pulse_enabled") as? Bool ?? true
        let pulse = groupDefaults?.integer(forKey: "ctt_watch_session_pulse_minutes") ?? 20
        watchSessionPulseMinutes = max(1, pulse)
        watchWristRaiseSummaryEnabled = groupDefaults?.object(forKey: "ctt_watch_wrist_raise_summary_enabled") as? Bool ?? true
        watchHapticProfile = groupDefaults?.string(forKey: "ctt_watch_haptic_profile") ?? "classic"
        watchQuickAction = groupDefaults?.string(forKey: "ctt_watch_quick_action") ?? "addBuyIn"
    }

    private func save() {
        groupDefaults?.set(watchHapticsEnabled, forKey: "ctt_watch_haptics_enabled")
        groupDefaults?.set(watchSessionPulseEnabled, forKey: "ctt_watch_session_pulse_enabled")
        groupDefaults?.set(max(1, watchSessionPulseMinutes), forKey: "ctt_watch_session_pulse_minutes")
        groupDefaults?.set(watchWristRaiseSummaryEnabled, forKey: "ctt_watch_wrist_raise_summary_enabled")
        groupDefaults?.set(watchHapticProfile, forKey: "ctt_watch_haptic_profile")
        groupDefaults?.set(watchQuickAction, forKey: "ctt_watch_quick_action")
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
