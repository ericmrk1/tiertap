import Foundation
import WatchConnectivity

struct RemoteCommandLogEntry: Identifiable, Codable {
    enum Delivery: String, Codable {
        case sent
        case queued
    }

    let id: UUID
    let action: String
    let paramsSummary: String
    let delivery: Delivery
    let timestamp: Date
}

/// Syncs session state between iPhone (source of truth) and Watch via WatchConnectivity.
/// Add this file to both TierTap and TierTap Watch App targets.
final class SessionSyncManager: NSObject, ObservableObject {
    static let shared = SessionSyncManager()

    private let session: WCSession? = WCSession.isSupported() ? .default : nil
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var cachedSessions: [Session] = []
    private var cachedLiveSession: Session?
    private var pendingApplicationContext: [String: Any]?
    private var lastQueuedStateRequestAt: Date?
    @Published private(set) var syncStatusMessage: String = "Not synced yet"
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var cachedSessionCount: Int = 0
    @Published private(set) var liveSessionID: UUID?
    @Published private(set) var remoteCommandLog: [RemoteCommandLogEntry] = []
    /// Keep WatchConnectivity payloads below practical transport limits.
    private let maxSyncPayloadBytes = 28_000
    private let maxHistorySessionsForSync = 250
    private let minHistorySessionsForSync = 0
    private let reminderEnabledKey = "ctt_session_reminders_enabled"
    private let reminderFrequencyMinutesKey = "ctt_session_reminder_frequency_minutes"
    private let liveSummaryKey = "liveSummary"
    private let appGroupSuiteName = "group.com.app.tiertap"
    private let wcSessionsSnapshotKey = "ctt_wc_sessions_snapshot"
    private let wcLiveSnapshotKey = "ctt_wc_live_snapshot"
    private let wcSnapshotRevisionKey = "ctt_wc_snapshot_revision"
    private let wcSnapshotUpdatedAtKey = "ctt_wc_snapshot_updated_at"
    private let mirrorFolderName = "TierTapWatchMirror"
    private let mirrorSessionsFileName = "sessions.json"
    private let mirrorLiveFileName = "live.json"
    private let mirrorRevisionFileName = "revision.txt"
    private let mirrorUpdatedAtFileName = "updated_at.txt"
    private let remoteCommandLogDefaultsKey = "ctt_watch_remote_command_log"
    private let maxRemoteCommandLogEntries = 200

    private var lastSimulatorMirrorRevisionRead: Int = 0

    /// Called on Watch when iPhone pushes new state. Arguments: (sessions, liveSession).
    var onContextReceived: (([Session], Session?) -> Void)?

    /// Called on iPhone when Watch sends an action. Params vary by action. Return (sessions, liveSession) to reply to Watch.
    var onActionReceived: ((String, [String: Any]) -> (sessions: [Session], liveSession: Session?)?)?

    /// iPhone: authoritative snapshot for state requests (main-thread `SessionStore`).
    var stateSnapshotProvider: (() -> (sessions: [Session], liveSession: Session?))?

    var isReachable: Bool { session?.isReachable ?? false }
    var activationState: WCSessionActivationState { session?.activationState ?? .inactive }
    #if os(iOS)
    var isPaired: Bool { session?.isPaired ?? false }
    #else
    var isPaired: Bool { true }
    #endif
    #if os(watchOS)
    var isCompanionAppInstalled: Bool { session?.isCompanionAppInstalled ?? false }
    #endif

    override private init() {
        super.init()
        loadRemoteCommandLog()
        session?.delegate = self
        session?.activate()
    }

    // MARK: - iPhone: push state to Watch

    func pushContext(sessions: [Session], liveSession: Session?) {
        let syncedSessions = sessionsForTransport(from: sessions)
        cachedSessions = syncedSessions
        cachedLiveSession = liveSession
        setDebugSnapshot(sessionCount: syncedSessions.count, liveSessionID: liveSession?.id)
        guard let payload = makePayload(sessions: syncedSessions, liveSession: liveSession) else { return }
        #if os(iOS)
        persistAppGroupWCDefaults(sessionsData: payload.sessionsData, liveData: payload.liveData)
        writeSimulatorMirrorToSharedContainer(syncedSessions: syncedSessions, liveSession: liveSession)
        #endif
        var ctx: [String: Any] = ["sessions": payload.sessionsData]
        if let d = payload.liveData { ctx["liveSession"] = d }
        else { ctx["liveSession"] = Data() }
        if let summary = payload.liveSummary {
            ctx[liveSummaryKey] = summary
        }
        ctx["sessionRemindersEnabled"] = UserDefaults.standard.bool(forKey: reminderEnabledKey)
        let minutes = UserDefaults.standard.integer(forKey: reminderFrequencyMinutesKey)
        ctx["sessionReminderFrequencyMinutes"] = max(1, minutes > 0 ? minutes : 30)
        pendingApplicationContext = ctx
        flushPendingApplicationContextIfPossible()
    }

    // MARK: - Watch: request current state (in case we missed a context push)

    func requestContext(completion: @escaping ([Session], Session?) -> Void) {
        var deliveredLocalSnapshot = false
        if let local = decodeContextPayload(from: session?.receivedApplicationContext ?? [:]) {
            cachedSessions = local.sessions
            cachedLiveSession = local.liveSession
            setDebugSnapshot(sessionCount: local.sessions.count, liveSessionID: local.liveSession?.id)
            markSynced(status: "Synced from application context")
            completion(local.sessions, local.liveSession)
            deliveredLocalSnapshot = true
        }
        // Always queue a background state request as backup; in Simulator, direct reply paths can be flaky.
        // Do this even when we decoded local application context so each sync cycle can still fetch fresh state.
        queueStateRequestIfNeeded()
        guard let session = session, session.isReachable else {
            updateStatus("Phone unreachable. Waiting for background sync.")
            // Do not call completion here if we already returned local snapshot; App Group poll handles unreachable.
            if !deliveredLocalSnapshot {
                completion(cachedSessions, cachedLiveSession)
            }
            return
        }
        updateStatus("Requesting live state from iPhone...")
        let fallback = DispatchWorkItem { [weak self] in
            self?.queueStateRequestIfNeeded()
            self?.updateStatus("No direct reply yet. Background sync queued.")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: fallback)
        session.sendMessage(["request": "state"], replyHandler: { [weak self] reply in
            fallback.cancel()
            self?.decodeReply(reply, completion: completion)
        }, errorHandler: { [weak self] _ in
            fallback.cancel()
            if let self {
                self.updateStatus("Direct request failed. Waiting for background sync.")
                if !deliveredLocalSnapshot {
                    completion(self.cachedSessions, self.cachedLiveSession)
                }
            } else {
                if !deliveredLocalSnapshot {
                    completion([], nil)
                }
            }
        })
    }

    // MARK: - Watch: send action to iPhone

    func sendAction(_ action: String, params: [String: Any], completion: @escaping ([Session], Session?) -> Void) {
        guard let session = session else {
            completion(cachedSessions, cachedLiveSession)
            return
        }
        var msg = params
        msg["action"] = action
        let paramsSummary = summarizedParams(params)
        if session.isReachable {
            session.sendMessage(msg, replyHandler: { [weak self] reply in
                self?.appendRemoteCommandLog(action: action, paramsSummary: paramsSummary, delivery: .sent)
                self?.decodeReply(reply, completion: completion)
            }, errorHandler: { [weak self] _ in
                guard let self else { return }
                session.transferUserInfo(msg)
                self.appendRemoteCommandLog(action: action, paramsSummary: paramsSummary, delivery: .queued)
                completion(self.cachedSessions, self.cachedLiveSession)
            })
            return
        }
        // Fallback path for simulator/background iPhone app: queue action for delivery.
        session.transferUserInfo(msg)
        appendRemoteCommandLog(action: action, paramsSummary: paramsSummary, delivery: .queued)
        completion(cachedSessions, cachedLiveSession)
    }

    func clearRemoteCommandLog() {
        DispatchQueue.main.async {
            self.remoteCommandLog = []
            self.persistRemoteCommandLog()
        }
    }

    private func decodeReply(_ reply: [String: Any], completion: ([Session], Session?) -> Void) {
        if let enabled = reply["sessionRemindersEnabled"] as? Bool {
            UserDefaults.standard.set(enabled, forKey: reminderEnabledKey)
        }
        if let minutes = reply["sessionReminderFrequencyMinutes"] as? Int {
            UserDefaults.standard.set(max(1, minutes), forKey: reminderFrequencyMinutesKey)
        }
        let sessions: [Session] = {
            guard let sessionsData = reply["sessions"] as? Data else { return cachedSessions }
            return (try? decoder.decode([Session].self, from: sessionsData)) ?? cachedSessions
        }()
        let liveFromData: Session? = {
            guard let bytes = reply["liveSession"] as? Data, !bytes.isEmpty else { return nil }
            return try? decoder.decode(Session.self, from: bytes)
        }()
        let live = liveFromData ?? decodeLiveSummary(reply[liveSummaryKey] as? [String: Any])
        if reply["sessions"] == nil && reply["liveSession"] == nil {
            updateStatus("Reply missing state payload.")
            queueStateRequestIfNeeded()
            completion(cachedSessions, cachedLiveSession)
            return
        }
        cachedSessions = sessions
        cachedLiveSession = live
        setDebugSnapshot(sessionCount: sessions.count, liveSessionID: live?.id)
        markSynced(status: "Synced from iPhone reply")
        completion(sessions, live)
    }

    private func decodeContextPayload(from payload: [String: Any]) -> (sessions: [Session], liveSession: Session?)? {
        if payload.isEmpty {
            updateStatus("Application context is empty.")
            return nil
        }
        let sessions: [Session] = {
            guard let sessionsData = payload["sessions"] as? Data else { return cachedSessions }
            return (try? decoder.decode([Session].self, from: sessionsData)) ?? cachedSessions
        }()
        let liveFromData: Session? = {
            guard let bytes = payload["liveSession"] as? Data, !bytes.isEmpty else { return nil }
            return try? decoder.decode(Session.self, from: bytes)
        }()
        let live = liveFromData ?? decodeLiveSummary(payload[liveSummaryKey] as? [String: Any])
        if payload["sessions"] == nil && payload["liveSession"] == nil {
            updateStatus("Application context missing state payload.")
            return nil
        }
        return (sessions, live)
    }

    private func flushPendingApplicationContextIfPossible() {
        guard let session = session,
              session.activationState == .activated,
              let ctx = pendingApplicationContext else { return }
        do {
            try session.updateApplicationContext(ctx)
        } catch {
            return
        }
        pendingApplicationContext = nil
    }

    /// When Watch cannot reach iPhone directly, queue a background "state" request.
    /// iPhone receives it in `didReceiveUserInfo` and pushes a fresh application context back.
    private func queueStateRequestIfNeeded() {
        guard let session = session else { return }
        let now = Date()
        if let last = lastQueuedStateRequestAt, now.timeIntervalSince(last) < 2.0 {
            return
        }
        lastQueuedStateRequestAt = now
        session.transferUserInfo(["request": "state"])
        updateStatus("Queued background state request.")
    }

    private func markSynced(status: String) {
        DispatchQueue.main.async {
            self.lastSyncAt = Date()
            self.syncStatusMessage = status
        }
    }

    private func updateStatus(_ text: String) {
        DispatchQueue.main.async {
            self.syncStatusMessage = text
        }
    }

    private func appendRemoteCommandLog(action: String, paramsSummary: String, delivery: RemoteCommandLogEntry.Delivery) {
        DispatchQueue.main.async {
            let entry = RemoteCommandLogEntry(
                id: UUID(),
                action: action,
                paramsSummary: paramsSummary,
                delivery: delivery,
                timestamp: Date()
            )
            self.remoteCommandLog.insert(entry, at: 0)
            if self.remoteCommandLog.count > self.maxRemoteCommandLogEntries {
                self.remoteCommandLog = Array(self.remoteCommandLog.prefix(self.maxRemoteCommandLogEntries))
            }
            self.persistRemoteCommandLog()
        }
    }

    private func summarizedParams(_ params: [String: Any]) -> String {
        guard !params.isEmpty else { return "-" }
        let items = params.keys.sorted().map { key in
            "\(key)=\(String(describing: params[key] ?? ""))"
        }
        return items.joined(separator: ", ")
    }

    private func loadRemoteCommandLog() {
        guard let data = UserDefaults.standard.data(forKey: remoteCommandLogDefaultsKey) else { return }
        guard let decoded = try? decoder.decode([RemoteCommandLogEntry].self, from: data) else { return }
        remoteCommandLog = decoded
    }

    private func persistRemoteCommandLog() {
        guard let data = try? encoder.encode(remoteCommandLog) else { return }
        UserDefaults.standard.set(data, forKey: remoteCommandLogDefaultsKey)
    }

    /// Watch: update debug HUD after applying an App Group snapshot (Simulator fallback path).
    func noteAppGroupSnapshotApplied(sessionCount: Int, liveSessionID: UUID?) {
        setDebugSnapshot(sessionCount: sessionCount, liveSessionID: liveSessionID)
        markSynced(status: "Synced from App Group snapshot")
    }

    private func setDebugSnapshot(sessionCount: Int, liveSessionID: UUID?) {
        DispatchQueue.main.async {
            self.cachedSessionCount = sessionCount
            self.liveSessionID = liveSessionID
        }
    }

    private func encodeLiveSummary(_ session: Session?) -> [String: Any]? {
        guard let session else { return nil }
        var summary: [String: Any] = [
            "id": session.id.uuidString,
            "game": session.game,
            "casino": session.casino,
            "startTime": session.startTime.timeIntervalSince1970,
            "startingTierPoints": session.startingTierPoints,
            "totalBuyIn": session.totalBuyIn,
            "totalComp": session.totalComp,
            "isLive": session.isLive
        ]
        if let end = session.endTime {
            summary["endTime"] = end.timeIntervalSince1970
        }
        return summary
    }

    private func decodeLiveSummary(_ summary: [String: Any]?) -> Session? {
        guard let summary else { return nil }
        guard let idString = summary["id"] as? String,
              let id = UUID(uuidString: idString),
              let game = summary["game"] as? String,
              let casino = summary["casino"] as? String,
              let startTs = summary["startTime"] as? TimeInterval,
              let startingTier = summary["startingTierPoints"] as? Int else {
            return nil
        }
        let startTime = Date(timeIntervalSince1970: startTs)
        let endTime = (summary["endTime"] as? TimeInterval).map { Date(timeIntervalSince1970: $0) }
        let totalBuyIn = max(0, summary["totalBuyIn"] as? Int ?? 0)
        let totalComp = max(0, summary["totalComp"] as? Int ?? 0)
        let isLive = summary["isLive"] as? Bool ?? (endTime == nil)
        let buyIns: [BuyInEvent] = totalBuyIn > 0 ? [BuyInEvent(amount: totalBuyIn, timestamp: startTime)] : []
        let comps: [CompEvent] = totalComp > 0 ? [CompEvent(amount: totalComp, timestamp: startTime)] : []
        return Session(
            id: id,
            game: game,
            casino: casino,
            startTime: startTime,
            endTime: endTime,
            startingTierPoints: startingTier,
            buyInEvents: buyIns,
            compEvents: comps,
            isLive: isLive
        )
    }

    #if os(iOS)
    /// Call from `SessionStore` persistence so Simulator can hydrate watch even if WC is broken.
    func writeSimulatorMirrorFromDiskSessions(sessions: [Session], liveSession: Session?) {
        let synced = sessionsForTransport(from: sessions)
        guard let sessionsData = try? encoder.encode(synced) else { return }
        let liveData = liveSession.flatMap { try? encoder.encode($0) }
        persistAppGroupWCDefaults(sessionsData: sessionsData, liveData: liveData)
        writeSimulatorMirrorToSharedContainer(syncedSessions: synced, liveSession: liveSession)
    }

    private func persistAppGroupWCDefaults(sessionsData: Data, liveData: Data?) {
        guard let group = UserDefaults(suiteName: appGroupSuiteName) else { return }
        group.set(sessionsData, forKey: wcSessionsSnapshotKey)
        if let liveData {
            group.set(liveData, forKey: wcLiveSnapshotKey)
        } else {
            group.removeObject(forKey: wcLiveSnapshotKey)
        }
        let rev = group.integer(forKey: wcSnapshotRevisionKey) + 1
        group.set(rev, forKey: wcSnapshotRevisionKey)
        group.set(Date().timeIntervalSince1970, forKey: wcSnapshotUpdatedAtKey)
    }

    private func writeSimulatorMirrorToSharedContainer(syncedSessions: [Session], liveSession: Session?) {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupSuiteName) else {
            DispatchQueue.main.async { [weak self] in
                self?.updateStatus("App group container URL is nil (entitlements?).")
            }
            return
        }
        
        guard let base_check = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupSuiteName) else {
            print("[iPhone] App Group container URL: NIL")
            return
        }
        print("[iPhone] App Group container URL: \(base_check.path)")
        
        let dir = base.appendingPathComponent(mirrorFolderName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let sessionsURL = dir.appendingPathComponent(mirrorSessionsFileName)
            let liveURL = dir.appendingPathComponent(mirrorLiveFileName)
            let revURL = dir.appendingPathComponent(mirrorRevisionFileName)

            let sessionsPayload = try encoder.encode(syncedSessions)
            try sessionsPayload.write(to: sessionsURL, options: .atomic)

            if let liveSession, let livePayload = try? encoder.encode(liveSession) {
                try livePayload.write(to: liveURL, options: .atomic)
            } else {
                if FileManager.default.fileExists(atPath: liveURL.path) {
                    try FileManager.default.removeItem(at: liveURL)
                }
            }

            let previousRev: Int = {
                guard let raw = try? String(contentsOf: revURL) else { return 0 }
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                return Int(trimmed) ?? 0
            }()
            let nextRev = previousRev + 1
            try String(nextRev).write(to: revURL, atomically: true, encoding: .utf8)

            let updatedAt = Date().timeIntervalSince1970
            let updatedURL = dir.appendingPathComponent(mirrorUpdatedAtFileName)
            try String(updatedAt).write(to: updatedURL, atomically: true, encoding: .utf8)
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.updateStatus("Mirror write failed: \(error.localizedDescription)")
            }
        }
    }
    #endif

    #if os(watchOS)
    /// Simulator-friendly fallback when WC application context / message payloads do not arrive.
    func readAppGroupSnapshotIfAvailable() -> (sessions: [Session], liveSession: Session?, revision: Int)? {
        let defaultsSnap = readAppGroupDefaultsSnapshot()
        let mirrorSnap = loadMirrorSnapshotAdvancingCursorIfPossible()
        
            let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupSuiteName)
            print("[Watch] App Group container URL: \(containerURL?.path ?? "NIL — entitlement missing")")
            
            print("[Watch] App Group defaults snap: \(defaultsSnap == nil ? "nil" : "rev \(defaultsSnap!.revision)")")
            print("[Watch] App Group mirror snap: \(mirrorSnap == nil ? "nil" : "rev \(mirrorSnap!.revision)")")
         
        switch (defaultsSnap, mirrorSnap) {
        case let (d?, m?):
            if m.updatedAt > d.updatedAt {
                return (m.sessions, m.liveSession, m.revision)
            }
            if d.updatedAt > m.updatedAt {
                return (d.sessions, d.liveSession, d.revision)
            }
            if m.revision != d.revision {
                return m.revision >= d.revision
                    ? (m.sessions, m.liveSession, m.revision)
                    : (d.sessions, d.liveSession, d.revision)
            }
            return (d.sessions, d.liveSession, d.revision)
        case let (d?, nil):
            return (d.sessions, d.liveSession, d.revision)
        case let (nil, m?):
            return (m.sessions, m.liveSession, m.revision)
        case (nil, nil):
            return nil
        }
    }

    private func loadMirrorSnapshotAdvancingCursorIfPossible() -> (sessions: [Session], liveSession: Session?, revision: Int, updatedAt: TimeInterval)? {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupSuiteName) else {
            return nil
        }
        let dir = base.appendingPathComponent(mirrorFolderName, isDirectory: true)
        let revURL = dir.appendingPathComponent(mirrorRevisionFileName)
        guard let revText = try? String(contentsOf: revURL),
              let rev = Int(revText.trimmingCharacters(in: .whitespacesAndNewlines)),
              rev > 0 else {
            return nil
        }
        guard rev != lastSimulatorMirrorRevisionRead else { return nil }

        let sessionsURL = dir.appendingPathComponent(mirrorSessionsFileName)
        guard let sessionsData = try? Data(contentsOf: sessionsURL),
              let sessions = try? decoder.decode([Session].self, from: sessionsData) else {
            lastSimulatorMirrorRevisionRead = rev
            return nil
        }
        let liveURL = dir.appendingPathComponent(mirrorLiveFileName)
        let live: Session? = {
            guard FileManager.default.fileExists(atPath: liveURL.path),
                  let d = try? Data(contentsOf: liveURL),
                  !d.isEmpty else { return nil }
            return try? decoder.decode(Session.self, from: d)
        }()
        let updatedAtURL = dir.appendingPathComponent(mirrorUpdatedAtFileName)
        let updatedAt: TimeInterval = {
            if let raw = try? String(contentsOf: updatedAtURL) {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if let t = TimeInterval(trimmed), t > 0 { return t }
            }
            if let attrs = try? FileManager.default.attributesOfItem(atPath: sessionsURL.path),
               let d = attrs[.modificationDate] as? Date {
                return d.timeIntervalSince1970
            }
            return 0
        }()
        lastSimulatorMirrorRevisionRead = rev
        return (sessions, live, rev, updatedAt)
    }

    private func readAppGroupDefaultsSnapshot() -> (sessions: [Session], liveSession: Session?, revision: Int, updatedAt: TimeInterval)? {
        guard let group = UserDefaults(suiteName: appGroupSuiteName) else { return nil }
        let rev = group.integer(forKey: wcSnapshotRevisionKey)
        guard rev > 0 else { return nil }
        guard let sessionsData = group.data(forKey: wcSessionsSnapshotKey) else { return nil }
        guard let sessions = try? decoder.decode([Session].self, from: sessionsData) else { return nil }
        let live: Session? = {
            guard let d = group.data(forKey: wcLiveSnapshotKey), !d.isEmpty else { return nil }
            return try? decoder.decode(Session.self, from: d)
        }()
        let updatedAt = group.double(forKey: wcSnapshotUpdatedAtKey)
        return (sessions, live, rev, updatedAt)
    }

    #endif
}

// MARK: - WCSessionDelegate

extension SessionSyncManager: WCSessionDelegate {

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            updateStatus("WC activation error: \(error.localizedDescription)")
        } else {
            updateStatus("WC activated (\(activationState.rawValue)).")
        }
        flushPendingApplicationContextIfPossible()
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif

    func sessionReachabilityDidChange(_ session: WCSession) {
        updateStatus(session.isReachable ? "Phone is reachable." : "Phone not reachable.")
        flushPendingApplicationContextIfPossible()
    }

    /// Watch receives context pushed by iPhone.
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if let enabled = applicationContext["sessionRemindersEnabled"] as? Bool {
            UserDefaults.standard.set(enabled, forKey: reminderEnabledKey)
        }
        if let minutes = applicationContext["sessionReminderFrequencyMinutes"] as? Int {
            UserDefaults.standard.set(max(1, minutes), forKey: reminderFrequencyMinutesKey)
        }
        guard let decoded = decodeContextPayload(from: applicationContext) else { return }
        let sessions = decoded.sessions
        let live = decoded.liveSession
        cachedSessions = sessions
        cachedLiveSession = live
        setDebugSnapshot(sessionCount: sessions.count, liveSessionID: live?.id)
        markSynced(status: "Synced from pushed iPhone context")
        DispatchQueue.main.async { [weak self] in
            self?.onContextReceived?(sessions, live)
        }
    }

    /// iPhone receives message from Watch (action to perform).
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                replyHandler([:])
                return
            }
            if (message["request"] as? String) == "state" {
                #if os(iOS)
                let reply = self.makeStateReplyFromSnapshot()
                replyHandler(reply)
                if let snap = self.stateSnapshotProvider?() {
                    self.pushContext(sessions: snap.sessions, liveSession: snap.liveSession)
                } else {
                    self.pushContext(sessions: self.cachedSessions, liveSession: self.cachedLiveSession)
                }
                #else
                replyHandler(self.makeStateReply(sessions: self.cachedSessions, liveSession: self.cachedLiveSession))
                #endif
                return
            }
            let action = message["action"] as? String ?? ""
            guard let result = self.onActionReceived?(action, message) else {
                replyHandler([:])
                return
            }
            let syncedSessions = self.sessionsForTransport(from: result.sessions)
            guard let payload = self.makePayload(sessions: syncedSessions, liveSession: result.liveSession) else {
                replyHandler([:])
                return
            }
            var reply: [String: Any] = ["sessions": payload.sessionsData]
            reply["liveSession"] = payload.liveData ?? Data()
            if let summary = payload.liveSummary {
                reply[self.liveSummaryKey] = summary
            }
            reply["sessionRemindersEnabled"] = UserDefaults.standard.bool(forKey: self.reminderEnabledKey)
            let minutes = UserDefaults.standard.integer(forKey: self.reminderFrequencyMinutesKey)
            reply["sessionReminderFrequencyMinutes"] = max(1, minutes > 0 ? minutes : 30)
            replyHandler(reply)
            #if os(iOS)
            // Keep watch's application context fresh even when it requested via direct message.
            self.pushContext(sessions: result.sessions, liveSession: result.liveSession)
            #endif
        }
    }

    /// iPhone receives queued action from watch when not reachable for `sendMessage`.
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        if (userInfo["request"] as? String) == "state" {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                #if os(iOS)
                if let snap = self.stateSnapshotProvider?() {
                    self.pushContext(sessions: snap.sessions, liveSession: snap.liveSession)
                } else {
                    self.pushContext(sessions: self.cachedSessions, liveSession: self.cachedLiveSession)
                }
                #endif
            }
            return
        }
        let action = userInfo["action"] as? String ?? ""
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let result = self.onActionReceived?(action, userInfo) else { return }
            #if os(iOS)
            self.pushContext(sessions: result.sessions, liveSession: result.liveSession)
            #endif
        }
    }

    private func makeStateReply(sessions: [Session], liveSession: Session?) -> [String: Any] {
        guard let payload = makePayload(sessions: sessions, liveSession: liveSession) else {
            return [:]
        }
        var reply: [String: Any] = ["sessions": payload.sessionsData]
        reply["liveSession"] = payload.liveData ?? Data()
        if let summary = payload.liveSummary {
            reply[liveSummaryKey] = summary
        }
        reply["sessionRemindersEnabled"] = UserDefaults.standard.bool(forKey: reminderEnabledKey)
        let minutes = UserDefaults.standard.integer(forKey: reminderFrequencyMinutesKey)
        reply["sessionReminderFrequencyMinutes"] = max(1, minutes > 0 ? minutes : 30)
        return reply
    }

    #if os(iOS)
    private func makeStateReplyFromSnapshot() -> [String: Any] {
        let snap = stateSnapshotProvider?()
            ?? (sessions: cachedSessions, liveSession: cachedLiveSession)
        return makeStateReply(sessions: snap.sessions, liveSession: snap.liveSession)
    }
    #endif

    /// Trims session history to recent items and shrinks until encoded payload fits WC transport.
    private func sessionsForTransport(from sessions: [Session]) -> [Session] {
        if sessions.isEmpty { return [] }
        let sorted = sessions.sorted { ($0.endTime ?? $0.startTime) > ($1.endTime ?? $1.startTime) }
        var count = min(sorted.count, maxHistorySessionsForSync)
        while count > minHistorySessionsForSync {
            let slice = Array(sorted.prefix(count))
            if let data = try? encoder.encode(slice), data.count <= maxSyncPayloadBytes {
                return slice
            }
            // Shrink quickly at first, then aggressively to guarantee fit.
            if count > 100 {
                count -= 25
            } else if count > 20 {
                count -= 10
            } else {
                count -= 1
            }
        }
        // Last resort: prioritize live-session/control sync over history payload size.
        return []
    }

    /// Builds a payload that stays within watch connectivity size targets.
    /// Falls back to summary-only live session when full live JSON is too large.
    private func makePayload(sessions: [Session], liveSession: Session?) -> (sessionsData: Data, liveData: Data?, liveSummary: [String: Any]?)? {
        guard let sessionsData = try? encoder.encode(sessions) else { return nil }
        let summary = encodeLiveSummary(liveSession)
        guard let liveSession else {
            return (sessionsData, nil, nil)
        }
        guard let encodedLive = try? encoder.encode(liveSession) else {
            return (sessionsData, nil, summary)
        }
        // Keep some headroom for keys/metadata in WC dictionaries.
        let estimatedBytes = sessionsData.count + encodedLive.count + 1024
        if estimatedBytes > maxSyncPayloadBytes {
            return (sessionsData, nil, summary)
        }
        return (sessionsData, encodedLive, summary)
    }
}
