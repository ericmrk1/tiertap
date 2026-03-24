import Foundation
import Combine

class SessionStore: ObservableObject {
    @Published var sessions: [Session] = []
    @Published var liveSession: Session?

    private let sessKey = "ctt_sessions_v2"
    private let liveKey = "ctt_live_v2"

    private var defaults: UserDefaults {
        UserDefaults(suiteName: "group.com.app.tiertap") ?? .standard
    }

    init() {
        load()
        setupSync()
    }

    /// Apply state received from iPhone (Watch only) or after a sent action. Updates UI and persists locally.
    func applySyncedState(sessions: [Session], liveSession: Session?) {
        self.sessions = sessions
        self.liveSession = liveSession
        saveSessions()
        if liveSession != nil { saveLive() }
        else { clearLive() }
    }

    private func setupSync() {
        #if os(iOS)
        SessionSyncManager.shared.onActionReceived = { [weak self] action, params in
            guard let self = self else { return nil }
            if action.isEmpty, params["request"] as? String == "state" {
                return (self.sessions, self.liveSession)
            }
            switch action {
            case "startSession":
                guard let game = params["game"] as? String, let casino = params["casino"] as? String,
                      let st = params["startingTier"] as? Int, let bi = params["initialBuyIn"] as? Int else { return nil }
                let program = params["rewardsProgramName"] as? String
                self.startSession(game: game, casino: casino, startingTier: st, initialBuyIn: bi, rewardsProgramName: program)
                return (self.sessions, self.liveSession)
            case "addBuyIn":
                guard let amount = params["amount"] as? Int else { return nil }
                self.addBuyIn(amount)
                return (self.sessions, self.liveSession)
            case "addComp":
                guard let amount = params["amount"] as? Int else { return nil }
                let kind = (params["kind"] as? String).flatMap { CompKind(rawValue: $0) } ?? .dollarsCredits
                let rawDetails = params["details"] as? String
                let trimmed = rawDetails?.trimmingCharacters(in: .whitespacesAndNewlines)
                let details = (trimmed?.isEmpty == false) ? trimmed : nil
                let fb = (params["foodBeverageKind"] as? String).flatMap { FoodBeverageKind(rawValue: $0) }
                let rawOther = params["foodBeverageOtherDescription"] as? String
                let trimmedOther = rawOther?.trimmingCharacters(in: .whitespacesAndNewlines)
                let otherDesc = (trimmedOther?.isEmpty == false) ? trimmedOther : nil
                self.addComp(amount: amount, kind: kind, details: details, foodBeverageKind: fb, foodBeverageOtherDescription: otherDesc)
                return (self.sessions, self.liveSession)
            case "closeSessionCashOutOnly":
                guard let cashOut = params["cashOut"] as? Int else { return nil }
                self.closeSessionCashOutOnly(cashOut: cashOut)
                return (self.sessions, self.liveSession)
            default:
                return nil
            }
        }
        pushContext()
        #elseif os(watchOS)
        SessionSyncManager.shared.onContextReceived = { [weak self] sessions, liveSession in
            DispatchQueue.main.async {
                self?.applySyncedState(sessions: sessions, liveSession: liveSession)
            }
        }
        // Request latest state when Watch app becomes active (in case we missed a push)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            SessionSyncManager.shared.requestContext { sessions, liveSession in
                DispatchQueue.main.async {
                    self?.applySyncedState(sessions: sessions, liveSession: liveSession)
                }
            }
        }
        #endif
    }

    private func pushContext() {
        #if os(iOS)
        SessionSyncManager.shared.pushContext(sessions: sessions, liveSession: liveSession)
        #endif
    }

    // MARK: Live
    func startSession(game: String, casino: String, startingTier: Int, initialBuyIn: Int, rewardsProgramName: String? = nil, casinoLatitude: Double? = nil, casinoLongitude: Double? = nil) {
        #if os(watchOS)
        var p: [String: Any] = [
            "game": game, "casino": casino, "startingTier": startingTier, "initialBuyIn": initialBuyIn
        ]
        if let name = rewardsProgramName { p["rewardsProgramName"] = name }
        SessionSyncManager.shared.sendAction("startSession", params: p) { [weak self] sessions, liveSession in
            DispatchQueue.main.async { self?.applySyncedState(sessions: sessions, liveSession: liveSession) }
        }
        return
        #endif
        let ev = BuyInEvent(amount: initialBuyIn, timestamp: Date())
        let s = Session(game: game, casino: casino, casinoLatitude: casinoLatitude, casinoLongitude: casinoLongitude, startTime: Date(),
                        startingTierPoints: startingTier, buyInEvents: [ev], isLive: true,
                        rewardsProgramName: rewardsProgramName)
        liveSession = s
        saveLive()
        #if os(iOS)
        LiveActivityManager.shared.start(session: s)
        pushContext()
        #endif
    }

    func addBuyIn(_ amount: Int) {
        #if os(watchOS)
        SessionSyncManager.shared.sendAction("addBuyIn", params: ["amount": amount]) { [weak self] sessions, liveSession in
            DispatchQueue.main.async { self?.applySyncedState(sessions: sessions, liveSession: liveSession) }
        }
        return
        #endif
        guard var s = liveSession else { return }
        s.buyInEvents.append(BuyInEvent(amount: amount, timestamp: Date()))
        liveSession = s; saveLive()
        #if os(iOS)
        LiveActivityManager.shared.update(totalBuyIn: s.totalBuyIn)
        pushContext()
        #endif
    }

    /// `photoJPEG` is optional JPEG bytes for a comp receipt; stored on disk only (not in session JSON).
    func addComp(amount: Int, kind: CompKind = .dollarsCredits, details: String? = nil, foodBeverageKind: FoodBeverageKind? = nil, foodBeverageOtherDescription: String? = nil, photoJPEG: Data? = nil) {
        let trimmed = details?.trimmingCharacters(in: .whitespacesAndNewlines)
        let storedDetails = (trimmed?.isEmpty == false) ? trimmed : nil
        let storedFB: FoodBeverageKind? = (kind == .foodBeverage) ? foodBeverageKind : nil
        let trimmedOther = foodBeverageOtherDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
        let storedOther: String? = (kind == .foodBeverage && storedFB == .other && trimmedOther?.isEmpty == false) ? trimmedOther : nil
        #if os(watchOS)
        var p: [String: Any] = ["amount": amount, "kind": kind.rawValue]
        if let storedDetails { p["details"] = storedDetails }
        if let storedFB { p["foodBeverageKind"] = storedFB.rawValue }
        if let storedOther { p["foodBeverageOtherDescription"] = storedOther }
        SessionSyncManager.shared.sendAction("addComp", params: p) { [weak self] sessions, liveSession in
            DispatchQueue.main.async { self?.applySyncedState(sessions: sessions, liveSession: liveSession) }
        }
        return
        #endif
        guard var s = liveSession else { return }
        let eventId = UUID()
        let ev = CompEvent(id: eventId, amount: amount, timestamp: Date(), kind: kind, details: storedDetails, foodBeverageKind: storedFB, foodBeverageOtherDescription: storedOther)
        s.compEvents.append(ev)
        liveSession = s
        #if os(iOS)
        if let jpeg = photoJPEG {
            CompPhotoStorage.saveJPEGData(jpeg, compEventID: eventId)
        }
        #endif
        saveLive()
        #if os(iOS)
        pushContext()
        #endif
    }

    func closeSession(cashOut: Int, endingTier: Int, privateNotes: String? = nil) {
        guard var s = liveSession else { return }
        s.cashOut = cashOut
        s.avgBetActual = nil
        s.avgBetRated = nil
        s.endingTierPoints = endingTier
        if privateNotes != nil { s.privateNotes = privateNotes }
        s.endTime = s.endTime ?? Date(); s.isLive = false; s.status = .complete
        sessions.insert(s, at: 0)
        liveSession = nil
        saveSessions(); clearLive()
        #if os(iOS)
        LiveActivityManager.shared.end()
        pushContext()
        #endif
    }

    /// Call from Watch (or quick cash-out): save session with only cash-out; status = requiringMoreInfo.
    func closeSessionCashOutOnly(cashOut: Int) {
        #if os(watchOS)
        SessionSyncManager.shared.sendAction("closeSessionCashOutOnly", params: ["cashOut": cashOut]) { [weak self] sessions, liveSession in
            DispatchQueue.main.async { self?.applySyncedState(sessions: sessions, liveSession: liveSession) }
        }
        return
        #endif
        guard var s = liveSession else { return }
        s.cashOut = cashOut
        s.endTime = Date()
        s.isLive = false
        s.status = .requiringMoreInfo
        sessions.insert(s, at: 0)
        liveSession = nil
        saveSessions(); clearLive()
        #if os(iOS)
        LiveActivityManager.shared.end()
        pushContext()
        #endif
    }

    /// Update structured game metadata for the current live session (e.g. Table vs Poker details).
    func updateLiveSessionGameMetadata(
        gameCategory: SessionGameCategory?,
        pokerGameKind: SessionPokerGameKind?,
        pokerAllowsRebuy: Bool?,
        pokerAllowsAddOn: Bool?,
        pokerHasFreeOut: Bool?,
        pokerVariant: String?,
        pokerSmallBlind: Int? = nil,
        pokerBigBlind: Int? = nil,
        pokerAnte: Int? = nil,
        pokerLevelMinutes: Int? = nil,
        pokerStartingStack: Int? = nil
    ) {
        guard var s = liveSession else { return }
        s.gameCategory = gameCategory
        s.pokerGameKind = pokerGameKind
        s.pokerAllowsRebuy = pokerAllowsRebuy
        s.pokerAllowsAddOn = pokerAllowsAddOn
        s.pokerHasFreeOut = pokerHasFreeOut
        s.pokerVariant = pokerVariant
        s.pokerSmallBlind = pokerSmallBlind
        s.pokerBigBlind = pokerBigBlind
        s.pokerAnte = pokerAnte
        s.pokerLevelMinutes = pokerLevelMinutes
        s.pokerStartingStack = pokerStartingStack
        liveSession = s
        saveLive()
        #if os(iOS)
        pushContext()
        #endif
    }

    /// Attach or replace the chip estimator image filename on the current live session.
    func setChipEstimatorImageFilename(_ fileName: String?) {
        guard var s = liveSession else { return }
        s.chipEstimatorImageFilename = fileName
        liveSession = s
        saveLive()
        #if os(iOS)
        pushContext()
        #endif
    }

    func discardLiveSession() {
        #if os(iOS)
        if let s = liveSession {
            CompPhotoStorage.deleteImages(for: s.compEvents)
        }
        #endif
        liveSession = nil; clearLive()
        #if os(iOS)
        LiveActivityManager.shared.end()
        pushContext()
        #endif
    }

    /// Freeze the live session end time so duration stops increasing (e.g. while user fills closeout form).
    func stopLiveSessionTimer() {
        guard var s = liveSession, s.endTime == nil else { return }
        s.endTime = Date()
        liveSession = s
        saveLive()
        #if os(iOS)
        LiveActivityManager.shared.end()
        pushContext()
        #endif
    }

    /// Un-freeze the live session timer so duration resumes increasing.
    func resumeLiveSessionTimer() {
        guard var s = liveSession, s.endTime != nil else { return }
        s.endTime = nil
        liveSession = s
        saveLive()
        #if os(iOS)
        pushContext()
        #endif
    }

    /// Update private notes on the current live session (saved locally only).
    func updateLiveSessionNotes(_ text: String?) {
        guard var s = liveSession else { return }
        s.privateNotes = text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true ? nil : text
        liveSession = s
        saveLive()
        #if os(iOS)
        pushContext()
        #endif
    }

    // MARK: Past
    func addPastSession(_ session: Session) {
        var s = session; s.isLive = false; s.status = .complete
        let idx = sessions.firstIndex(where: { $0.startTime < s.startTime }) ?? sessions.endIndex
        sessions.insert(s, at: idx)
        saveSessions()
        #if os(iOS)
        pushContext()
        #endif
    }

    func updateSession(_ session: Session) {
        guard let idx = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        var s = session; s.isLive = false
        sessions[idx] = s
        saveSessions()
        #if os(iOS)
        pushContext()
        #endif
    }

    func deleteSession(at offsets: IndexSet) {
        #if os(iOS)
        for idx in offsets {
            CompPhotoStorage.deleteImages(for: sessions[idx].compEvents)
        }
        #endif
        sessions.remove(atOffsets: offsets)
        saveSessions()
        #if os(iOS)
        pushContext()
        #endif
    }

    func deleteSession(_ session: Session) {
        #if os(iOS)
        CompPhotoStorage.deleteImages(for: session.compEvents)
        #endif
        sessions.removeAll { $0.id == session.id }
        saveSessions()
        #if os(iOS)
        pushContext()
        #endif
    }

    // MARK: Persistence
    private func load() {
        if let d = defaults.data(forKey: sessKey),
           let v = try? JSONDecoder().decode([Session].self, from: d) { sessions = v }
        else if let d = UserDefaults.standard.data(forKey: "ctt_sessions_v1"),
                let v = try? JSONDecoder().decode([Session].self, from: d) {
            sessions = v
            saveSessions()
        }
        if let d = defaults.data(forKey: liveKey),
           let v = try? JSONDecoder().decode(Session.self, from: d) { liveSession = v }
        else if let d = UserDefaults.standard.data(forKey: "ctt_live_v1"),
                let v = try? JSONDecoder().decode(Session.self, from: d) {
            liveSession = v
            saveLive()
        }
    }
    private func saveSessions() {
        if let d = try? JSONEncoder().encode(sessions) { defaults.set(d, forKey: sessKey) }
    }
    private func saveLive() {
        if let d = try? JSONEncoder().encode(liveSession) { defaults.set(d, forKey: liveKey) }
    }
    private func clearLive() { defaults.removeObject(forKey: liveKey) }

    // MARK: - Defaults / Helpers

    /// Returns the most recent avg bet actual / rated for a given game from history.
    /// Used to pre-populate closeout forms so user doesn't have to retype common bet sizes.
    func defaultAvgBets(for game: String) -> (actual: Int?, rated: Int?) {
        guard !game.isEmpty else { return (nil, nil) }
        let matching = sessions
            .filter { $0.game == game }
            .sorted { ($0.endTime ?? $0.startTime) > ($1.endTime ?? $1.startTime) }

        let actual = matching.first(where: { $0.avgBetActual != nil })?.avgBetActual
        let rated = matching.first(where: { $0.avgBetRated != nil })?.avgBetRated
        return (actual, rated)
    }

    /// Returns a reasonable default ending tier points for a given casino, based on history.
    /// Prefers the most recent session with an explicit ending tier; falls back to that
    /// session's starting tier points if needed.
    func defaultEndingTierPoints(for casino: String) -> Int? {
        guard !casino.isEmpty else { return nil }
        let matching = sessions
            .filter { $0.casino == casino }
            .sorted { ($0.endTime ?? $0.startTime) > ($1.endTime ?? $1.startTime) }

        if let withEnding = matching.first(where: { $0.endingTierPoints != nil }) {
            return withEnding.endingTierPoints
        }
        return matching.first?.startingTierPoints
    }

    /// Most recent initial buy-in at this casino (first buy-in of the latest session there), if any.
    func defaultInitialBuyIn(for casino: String) -> Int? {
        guard !casino.isEmpty else { return nil }
        let matching = sessions
            .filter { $0.casino == casino }
            .sorted { ($0.endTime ?? $0.startTime) > ($1.endTime ?? $1.startTime) }
        guard let bi = matching.first?.initialBuyIn, bi > 0 else { return nil }
        return bi
    }

    /// True if at least one saved session uses this exact casino name (used to avoid applying
    /// location defaults while the user is still typing a new casino name).
    func hasSessionHistory(forExactCasino casino: String) -> Bool {
        guard !casino.isEmpty else { return false }
        return sessions.contains { $0.casino == casino }
    }

    /// Returns true if recent sessions with mood show a downswing (3+ of last 5 with “bad” mood).
    /// Call after updating a session’s mood to decide whether to show Gamblers Anonymous support.
    func recentMoodDownswingDetected() -> Bool {
        let withMood = sessions
            .filter { $0.sessionMood != nil }
            .sorted { ($0.endTime ?? $0.startTime) > ($1.endTime ?? $1.startTime) }
        let recent = Array(withMood.prefix(5))
        guard recent.count >= 3 else { return false }
        let badCount = recent.filter { $0.sessionMood!.isDownswingMood }.count
        return badCount >= 3
    }

    /// Returns the casino (location) from the most recently played session.
    /// Used to pre-populate the location field when starting a new session.
    func mostRecentCasino() -> String? {
        let sorted = sessions
            .sorted { ($0.endTime ?? $0.startTime) > ($1.endTime ?? $1.startTime) }
        return sorted.first.flatMap { $0.casino.isEmpty ? nil : $0.casino }
    }
}
