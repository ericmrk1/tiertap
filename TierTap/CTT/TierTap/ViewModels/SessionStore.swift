import Foundation
import Combine

class SessionStore: ObservableObject {
    @Published var sessions: [Session] = []
    @Published var liveSession: Session?

    private let sessKey = "ctt_sessions_v1"
    private let liveKey = "ctt_live_v1"

    init() { load() }

    // MARK: Live
    func startSession(game: String, casino: String, startingTier: Int, initialBuyIn: Int) {
        let ev = BuyInEvent(amount: initialBuyIn, timestamp: Date())
        let s = Session(game: game, casino: casino, startTime: Date(),
                        startingTierPoints: startingTier, buyInEvents: [ev], isLive: true)
        liveSession = s
        saveLive()
        LiveActivityManager.shared.start(session: s)
    }

    func addBuyIn(_ amount: Int) {
        guard var s = liveSession else { return }
        s.buyInEvents.append(BuyInEvent(amount: amount, timestamp: Date()))
        liveSession = s; saveLive()
        LiveActivityManager.shared.update(totalBuyIn: s.totalBuyIn)
    }

    func closeSession(cashOut: Int, avgBetActual: Int, avgBetRated: Int, endingTier: Int) {
        guard var s = liveSession else { return }
        s.cashOut = cashOut; s.avgBetActual = avgBetActual
        s.avgBetRated = avgBetRated; s.endingTierPoints = endingTier
        s.endTime = Date(); s.isLive = false
        sessions.insert(s, at: 0)
        liveSession = nil
        saveSessions(); clearLive()
        LiveActivityManager.shared.end()
    }

    func discardLiveSession() {
        liveSession = nil; clearLive()
        LiveActivityManager.shared.end()
    }

    // MARK: Past
    func addPastSession(_ session: Session) {
        var s = session; s.isLive = false
        let idx = sessions.firstIndex(where: { $0.startTime < s.startTime }) ?? sessions.endIndex
        sessions.insert(s, at: idx)
        saveSessions()
    }

    func deleteSession(at offsets: IndexSet) {
        sessions.remove(atOffsets: offsets)
        saveSessions()
    }

    // MARK: Persistence
    private func load() {
        if let d = UserDefaults.standard.data(forKey: sessKey),
           let v = try? JSONDecoder().decode([Session].self, from: d) { sessions = v }
        if let d = UserDefaults.standard.data(forKey: liveKey),
           let v = try? JSONDecoder().decode(Session.self, from: d) { liveSession = v }
    }
    private func saveSessions() {
        if let d = try? JSONEncoder().encode(sessions) { UserDefaults.standard.set(d, forKey: sessKey) }
    }
    private func saveLive() {
        if let d = try? JSONEncoder().encode(liveSession) { UserDefaults.standard.set(d, forKey: liveKey) }
    }
    private func clearLive() { UserDefaults.standard.removeObject(forKey: liveKey) }
}
