import Foundation
import WatchConnectivity

/// Syncs session state between iPhone (source of truth) and Watch via WatchConnectivity.
/// Add this file to both TierTap and TierTap Watch App targets.
final class SessionSyncManager: NSObject, ObservableObject {
    static let shared = SessionSyncManager()

    private let session: WCSession? = WCSession.isSupported() ? .default : nil
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Called on Watch when iPhone pushes new state. Arguments: (sessions, liveSession).
    var onContextReceived: (([Session], Session?) -> Void)?

    /// Called on iPhone when Watch sends an action. Params vary by action. Return (sessions, liveSession) to reply to Watch.
    var onActionReceived: ((String, [String: Any]) -> (sessions: [Session], liveSession: Session?)?)?

    var isReachable: Bool { session?.isReachable ?? false }
    var activationState: WCSessionActivationState { session?.activationState ?? .inactive }

    override private init() {
        super.init()
        session?.delegate = self
        session?.activate()
    }

    // MARK: - iPhone: push state to Watch

    func pushContext(sessions: [Session], liveSession: Session?) {
        guard let session = session, session.activationState == .activated else { return }
        guard let sessionsData = try? encoder.encode(sessions) else { return }
        let liveData = liveSession.flatMap { try? encoder.encode($0) }
        var ctx: [String: Any] = ["sessions": sessionsData]
        if let d = liveData { ctx["liveSession"] = d }
        else { ctx["liveSession"] = Data() }
        try? session.updateApplicationContext(ctx)
    }

    // MARK: - Watch: request current state (in case we missed a context push)

    func requestContext(completion: @escaping ([Session], Session?) -> Void) {
        guard let session = session, session.isReachable else {
            completion([], nil)
            return
        }
        session.sendMessage(["request": "state"], replyHandler: { [weak self] reply in
            self?.decodeReply(reply, completion: completion)
        }, errorHandler: { _ in
            completion([], nil)
        })
    }

    // MARK: - Watch: send action to iPhone

    func sendAction(_ action: String, params: [String: Any], completion: @escaping ([Session], Session?) -> Void) {
        guard let session = session else {
            completion([], nil)
            return
        }
        var msg = params
        msg["action"] = action
        session.sendMessage(msg, replyHandler: { [weak self] reply in
            self?.decodeReply(reply, completion: completion)
        }, errorHandler: { _ in
            completion([], nil)
        })
    }

    private func decodeReply(_ reply: [String: Any], completion: ([Session], Session?) -> Void) {
        guard let sessionsData = reply["sessions"] as? Data,
              let sessions = try? decoder.decode([Session].self, from: sessionsData) else {
            completion([], nil)
            return
        }
        let live: Session? = (reply["liveSession"] as? Data).flatMap { try? decoder.decode(Session.self, from: $0) }
        completion(sessions, live)
    }
}

// MARK: - WCSessionDelegate

extension SessionSyncManager: WCSessionDelegate {

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        // No-op; state is read by pushContext / sendMessage
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {}
    #endif

    /// Watch receives context pushed by iPhone.
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let sessionsData = applicationContext["sessions"] as? Data,
              let sessions = try? decoder.decode([Session].self, from: sessionsData) else { return }
        let liveData = applicationContext["liveSession"] as? Data
        let live: Session? = liveData.flatMap { try? decoder.decode(Session.self, from: $0) }
        DispatchQueue.main.async { [weak self] in
            self?.onContextReceived?(sessions, live)
        }
    }

    /// iPhone receives message from Watch (action to perform).
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let action = message["action"] as? String ?? ""
        guard let result = onActionReceived?(action, message) else {
            replyHandler([:])
            return
        }
        guard let sessionsData = try? encoder.encode(result.sessions),
              let liveData = result.liveSession.flatMap({ try? encoder.encode($0) }) ?? Optional(Data()) else {
            replyHandler([:])
            return
        }
        var reply: [String: Any] = ["sessions": sessionsData]
        reply["liveSession"] = liveData
        replyHandler(reply)
    }
}
