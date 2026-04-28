import Foundation
import Combine
#if os(iOS) || os(watchOS)
import UserNotifications
#endif

/// Shown app-wide after closeout when ending tier points changed for a session linked to a wallet card.
struct WalletTierCloseoutToast: Equatable {
    let fromPoints: Int
    let toPoints: Int
}

/// Durations for `WalletTierCloseoutToastBanner` (count with ease-in-out motion, then hold on the final value).
enum WalletTierCloseoutTiming {
    /// Counting phase: eased so the value moves slowly, then quickly, then slowly to the target.
    static let countDuration: TimeInterval = 2.5
    /// After the count finishes, keep the final value on screen.
    static let holdOnFinalDuration: TimeInterval = 1.5
    static let dismissBuffer: TimeInterval = 0.12
    static var totalAutoDismiss: TimeInterval { countDuration + holdOnFinalDuration + dismissBuffer }
}

class SessionStore: ObservableObject {
    @Published var sessions: [Session] = []
    @Published var liveSession: Session?
    /// Brief full-screen toast; set before `closeSession` so it survives live-session dismissal.
    @Published var walletTierCloseoutToast: WalletTierCloseoutToast?
    #if os(iOS)
    /// After a session is fully completed (live close-out or finishing a Watch cash-out), set briefly so the app can offer share / publish / session art.
    @Published var postCloseoutSharePromptSessionId: UUID?
    #endif

    private let sessKey = "ctt_sessions_v2"
    private let liveKey = "ctt_live_v2"

    private var defaults: UserDefaults {
        UserDefaults(suiteName: "group.com.app.tiertap") ?? .standard
    }

    init() {
        #if os(watchOS)
        // Activate WCSession and assign delegate before any other init work so
        // `didReceiveApplicationContext` is never dropped, and wire state before
        // hydrating from `receivedApplicationContext` / follow-up requests.
        let sync = SessionSyncManager.shared
        load()
        sync.onContextReceived = { [weak self] sessions, liveSession in
            guard let self else { return }
            // Main thread: SessionSyncManager dispatches before invoking this.
            self.applySyncedState(sessions: sessions, liveSession: liveSession)
        }
        sync.requestContext { [weak self] sessions, liveSession in
            guard let self else { return }
            guard !sessions.isEmpty || liveSession != nil else { return }
            DispatchQueue.main.async {
                self.applySyncedState(sessions: sessions, liveSession: liveSession)
            }
        }
        #else
        load()
        #endif
        #if os(iOS)
        SessionSyncManager.shared.stateSnapshotProvider = { [weak self] in
            guard let self else { return (sessions: [], liveSession: nil) }
            return (sessions: self.sessions, liveSession: self.liveSession)
        }
        #endif
        setupSync()
        #if os(iOS) || os(watchOS)
        SessionReminderScheduler.shared.refresh(liveSession: liveSession)
        #endif
    }

    /// Apply state received from iPhone (Watch only) or after a sent action. Updates UI and persists locally.
    func applySyncedState(sessions: [Session], liveSession: Session?) {
        self.sessions = sessions
        self.liveSession = liveSession
        saveSessions()
        if liveSession != nil { saveLive() }
        else { clearLive() }
        #if os(iOS) || os(watchOS)
        SessionReminderScheduler.shared.refresh(liveSession: self.liveSession)
        #endif
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
            case "fastStartSession":
                guard let raw = params["category"] as? String,
                      let category = SessionGameCategory(rawValue: raw) else { return nil }
                self.fastStartSession(category: category)
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
            case "fastCloseOut":
                self.fastCloseSessionWithDefaultsUnverified()
                return (self.sessions, self.liveSession)
            case "pauseSession":
                self.stopLiveSessionTimer()
                return (self.sessions, self.liveSession)
            case "resumeSession":
                self.resumeLiveSessionTimer()
                return (self.sessions, self.liveSession)
            case "updateTier":
                guard let points = params["points"] as? Int else { return nil }
                self.updateLiveSessionStartingTier(points)
                return (self.sessions, self.liveSession)
            default:
                return nil
            }
        }
        pushContext()
        #endif
    }

    private func pushContext() {
        #if os(iOS)
        SessionSyncManager.shared.pushContext(sessions: sessions, liveSession: liveSession)
        #endif
    }

    // MARK: Live
    func startSession(
        game: String,
        casino: String,
        startingTier: Int,
        initialBuyIn: Int,
        rewardsProgramName: String? = nil,
        casinoLatitude: Double? = nil,
        casinoLongitude: Double? = nil,
        linkedRewardWalletCardId: UUID? = nil
    ) {
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
        guard liveSession == nil else { return }
        let ev = BuyInEvent(amount: initialBuyIn, timestamp: Date())
        let s = Session(
            game: game,
            casino: casino,
            casinoLatitude: casinoLatitude,
            casinoLongitude: casinoLongitude,
            startTime: Date(),
            startingTierPoints: startingTier,
            buyInEvents: [ev],
            isLive: true,
            rewardsProgramName: rewardsProgramName,
            linkedRewardWalletCardId: linkedRewardWalletCardId
        )
        liveSession = s
        saveLive()
        #if os(iOS) || os(watchOS)
        SessionReminderScheduler.shared.refresh(liveSession: liveSession)
        #endif
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

    func fastStartSession(category: SessionGameCategory) {
        #if os(watchOS)
        SessionSyncManager.shared.sendAction("fastStartSession", params: ["category": category.rawValue]) { [weak self] sessions, liveSession in
            DispatchQueue.main.async { self?.applySyncedState(sessions: sessions, liveSession: liveSession) }
        }
        return
        #endif
        guard liveSession == nil else { return }
        guard let template = mostRecentSession(forGameCategory: category) else { return }
        let gameName = template.game.isEmpty ? category.pickerTitle : template.game
        let initialBuyIn = template.initialBuyIn.flatMap { $0 > 0 ? $0 : nil } ?? 1
        startSession(
            game: gameName,
            casino: template.casino,
            startingTier: template.startingTierPoints,
            initialBuyIn: initialBuyIn,
            rewardsProgramName: template.rewardsProgramName,
            casinoLatitude: template.casinoLatitude,
            casinoLongitude: template.casinoLongitude,
            linkedRewardWalletCardId: template.linkedRewardWalletCardId
        )
        let slotMeta = Session.persistedSlotMetadata(
            gameCategory: template.gameCategory,
            format: template.slotFormat,
            formatOther: template.slotFormatOther ?? "",
            feature: template.slotFeature,
            featureOther: template.slotFeatureOther ?? "",
            notes: template.slotNotes ?? ""
        )
        updateLiveSessionGameMetadata(
            gameCategory: template.gameCategory ?? category,
            pokerGameKind: template.pokerGameKind,
            pokerAllowsRebuy: template.pokerAllowsRebuy,
            pokerAllowsAddOn: template.pokerAllowsAddOn,
            pokerHasFreeOut: template.pokerHasFreeOut,
            pokerVariant: template.pokerVariant,
            pokerSmallBlind: template.pokerSmallBlind,
            pokerBigBlind: template.pokerBigBlind,
            pokerAnte: template.pokerAnte,
            pokerLevelMinutes: template.pokerLevelMinutes,
            pokerStartingStack: template.pokerStartingStack,
            slotFormat: slotMeta.format,
            slotFormatOther: slotMeta.formatOther,
            slotFeature: slotMeta.feature,
            slotFeatureOther: slotMeta.featureOther,
            slotNotes: slotMeta.notes
        )
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

    /// End the live session immediately using the same defaults as the close-out sheet pre-fill:
    /// cash out = total buy-in, ending tier = starting tier (or recent history for this casino, else 0).
    /// Marks tier point figures as **unverified** so W/L and tier gains stay provisional.
    func fastCloseSessionWithDefaultsUnverified() {
        #if os(watchOS)
        SessionSyncManager.shared.sendAction("fastCloseOut", params: [:]) { [weak self] sessions, liveSession in
            DispatchQueue.main.async { self?.applySyncedState(sessions: sessions, liveSession: liveSession) }
        }
        return
        #endif
        guard var s = liveSession else { return }
        let cashOut = s.totalBuyIn
        let endingTier: Int
        if s.startingTierPoints > 0 {
            endingTier = s.startingTierPoints
        } else if let hist = defaultEndingTierPoints(for: s.casino) {
            endingTier = hist
        } else {
            endingTier = 0
        }
        s.tierPointsVerification = .unverified
        liveSession = s
        closeSession(cashOut: cashOut, endingTier: endingTier, privateNotes: nil)
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
        clearLive(); saveSessions()
        #if os(iOS) || os(watchOS)
        SessionReminderScheduler.shared.refresh(liveSession: liveSession)
        #endif
        #if os(iOS)
        LiveActivityManager.shared.end()
        pushContext()
        schedulePostCloseoutSharePrompt(sessionId: s.id)
        #endif
    }

    #if os(iOS)
    func clearPostCloseoutSharePrompt() {
        postCloseoutSharePromptSessionId = nil
    }

    /// Presents the same post-closeout share flow (`PostCloseoutShareFlowView`) used after ending a live session — e.g. from History → Tools.
    func presentPostCloseoutSharePrompt(sessionId: UUID) {
        postCloseoutSharePromptSessionId = sessionId
    }

    private func schedulePostCloseoutSharePrompt(sessionId: UUID) {
        // Wait until after nested sheets (close-out, mood picker, live session) finish dismissing;
        // presenting the root share sheet too soon often fails silently when `liveSession` clears.
        DispatchQueue.main.async { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) { [weak self] in
                guard let self else { return }
                self.postCloseoutSharePromptSessionId = sessionId
            }
        }
    }
    #endif

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
        clearLive(); saveSessions()
        #if os(iOS) || os(watchOS)
        SessionReminderScheduler.shared.refresh(liveSession: liveSession)
        #endif
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
        pokerStartingStack: Int? = nil,
        slotFormat: SessionSlotFormat? = nil,
        slotFormatOther: String? = nil,
        slotFeature: SessionSlotFeature? = nil,
        slotFeatureOther: String? = nil,
        slotNotes: String? = nil
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
        s.slotFormat = slotFormat
        s.slotFormatOther = slotFormatOther
        s.slotFeature = slotFeature
        s.slotFeatureOther = slotFeatureOther
        s.slotNotes = slotNotes
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
        #if os(iOS) || os(watchOS)
        SessionReminderScheduler.shared.refresh(liveSession: liveSession)
        #endif
        #if os(iOS)
        LiveActivityManager.shared.end()
        pushContext()
        #endif
    }

    /// Freeze the live session end time so duration stops increasing (e.g. while user fills closeout form).
    func stopLiveSessionTimer() {
        #if os(watchOS)
        SessionSyncManager.shared.sendAction("pauseSession", params: [:]) { [weak self] sessions, liveSession in
            DispatchQueue.main.async { self?.applySyncedState(sessions: sessions, liveSession: liveSession) }
        }
        return
        #endif
        guard var s = liveSession, s.endTime == nil else { return }
        s.endTime = Date()
        liveSession = s
        saveLive()
        #if os(iOS) || os(watchOS)
        SessionReminderScheduler.shared.refresh(liveSession: liveSession)
        #endif
        #if os(iOS)
        LiveActivityManager.shared.update(for: s)
        pushContext()
        #endif
    }

    /// Un-freeze the live session timer so duration resumes increasing.
    func resumeLiveSessionTimer() {
        #if os(watchOS)
        SessionSyncManager.shared.sendAction("resumeSession", params: [:]) { [weak self] sessions, liveSession in
            DispatchQueue.main.async { self?.applySyncedState(sessions: sessions, liveSession: liveSession) }
        }
        return
        #endif
        guard var s = liveSession, let pausedAt = s.endTime else { return }
        let pausedDuration = max(0, Date().timeIntervalSince(pausedAt))
        s.startTime = s.startTime.addingTimeInterval(pausedDuration)
        s.endTime = nil
        liveSession = s
        saveLive()
        #if os(iOS) || os(watchOS)
        SessionReminderScheduler.shared.refresh(liveSession: liveSession)
        #endif
        #if os(iOS)
        LiveActivityManager.shared.update(for: s)
        pushContext()
        #endif
    }

    func updateLiveSessionStartingTier(_ points: Int) {
        #if os(watchOS)
        SessionSyncManager.shared.sendAction("updateTier", params: ["points": points]) { [weak self] sessions, liveSession in
            DispatchQueue.main.async { self?.applySyncedState(sessions: sessions, liveSession: liveSession) }
        }
        return
        #endif
        guard var s = liveSession else { return }
        s.startingTierPoints = points
        liveSession = s
        saveLive()
        #if os(iOS)
        LiveActivityManager.shared.update(for: s)
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

    /// Whether tier point figures for the live session are verified (confirmed) or still provisional.
    func updateLiveSessionTierPointsVerification(_ value: SessionTierPointsVerification) {
        guard var s = liveSession else { return }
        if s.tierPointsVerification == nil, value == .verified { return }
        guard s.tierPointsVerification != value else { return }
        s.tierPointsVerification = value
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
        let prev = sessions[idx]
        var s = session; s.isLive = false
        sessions[idx] = s
        saveSessions()
        #if os(iOS)
        if prev.status == .requiringMoreInfo && s.status == .complete {
            schedulePostCloseoutSharePrompt(sessionId: s.id)
        }
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

    func deleteSessions(withIDs ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        #if os(iOS)
        let sessionsToDelete = sessions.filter { ids.contains($0.id) }
        for session in sessionsToDelete {
            CompPhotoStorage.deleteImages(for: session.compEvents)
        }
        #endif
        sessions.removeAll { ids.contains($0.id) }
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
        #if os(iOS)
        SessionSyncManager.shared.writeSimulatorMirrorFromDiskSessions(sessions: sessions, liveSession: liveSession)
        #endif
    }
    private func saveLive() {
        if let d = try? JSONEncoder().encode(liveSession) { defaults.set(d, forKey: liveKey) }
        #if os(iOS)
        SessionSyncManager.shared.writeSimulatorMirrorFromDiskSessions(sessions: sessions, liveSession: liveSession)
        #endif
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

    /// Most recent saved session for a game type (table = non-poker, non-slots, including legacy `nil` category).
    func mostRecentSession(forGameCategory category: SessionGameCategory) -> Session? {
        let sorted = sessions.sorted { ($0.endTime ?? $0.startTime) > ($1.endTime ?? $1.startTime) }
        return sorted.first { s in
            switch category {
            case .table:
                return s.gameCategory != .poker && s.gameCategory != .slots
            case .slots:
                return s.gameCategory == .slots
            case .poker:
                return s.gameCategory == .poker
            }
        }
    }
}

#if os(iOS) || os(watchOS)
/// Schedules local notifications for active session time checkpoints.
final class SessionReminderScheduler {
    static let shared = SessionReminderScheduler()
    /// Keep reminder presets local to avoid cross-target type dependencies (e.g. watch target missing `SettingsStore`).
    private static let reminderMessageOptions: [String] = [
        "Take a break.",
        "Quit while you're ahead.",
        "Protect your bankroll.",
        "Stop if your plan says stop.",
        "Hydrate and reset.",
        "Stay disciplined."
    ]

    private let reminderEnabledKey = "ctt_session_reminders_enabled"
    private let reminderFrequencyMinutesKey = "ctt_session_reminder_frequency_minutes"
    private let reminderMessagePresetKey = "ctt_session_reminder_message_preset"
    private let reminderCustomMessageKey = "ctt_session_reminder_custom_message"
    private let reminderIncludeStatsKey = "ctt_session_reminder_include_session_stats"
    private let requestPrefix = "ctt.session.reminder."
    /// iOS/watchOS allow a limited number of pending notifications; keep below system cap.
    private let maxScheduledReminders = 60
    private var lastScheduleSignature: String?

    private init() {}

    func refresh(liveSession: Session?) {
        guard remindersEnabled else {
            clearPendingSessionReminders()
            lastScheduleSignature = nil
            return
        }
        guard let session = liveSession, session.isLive, session.endTime == nil else {
            clearPendingSessionReminders()
            lastScheduleSignature = nil
            return
        }
        let signature = scheduleSignature(for: session, intervalMinutes: reminderFrequencyMinutes)
        guard signature != lastScheduleSignature else { return }
        lastScheduleSignature = signature
        ensureAuthorizationThenSchedule(session: session, intervalMinutes: reminderFrequencyMinutes)
    }

    /// Registers the app for notifications when Play Reminders are on so **Settings → Notifications** can list TierTap.
    /// (Otherwise authorization may never run until a live session exists — common on Simulator.)
    func primeAuthorizationWhenRemindersEnabled() {
        guard remindersEnabled else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    private var remindersEnabled: Bool {
        UserDefaults.standard.bool(forKey: reminderEnabledKey)
    }

    private var reminderFrequencyMinutes: Int {
        let stored = UserDefaults.standard.integer(forKey: reminderFrequencyMinutesKey)
        return max(1, stored > 0 ? stored : 30)
    }

    private var reminderMessagePreset: String {
        let fallback = Self.reminderMessageOptions.first ?? "Take a break."
        let stored = UserDefaults.standard.string(forKey: reminderMessagePresetKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Self.reminderMessageOptions.contains(stored) ? stored : fallback
    }

    private var reminderCustomMessage: String {
        UserDefaults.standard.string(forKey: reminderCustomMessageKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var reminderIncludeSessionStats: Bool {
        if UserDefaults.standard.object(forKey: reminderIncludeStatsKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: reminderIncludeStatsKey)
    }

    private func ensureAuthorizationThenSchedule(session: Session, intervalMinutes: Int) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                self.scheduleReminders(for: session, intervalMinutes: intervalMinutes)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    guard granted else {
                        self.lastScheduleSignature = nil
                        return
                    }
                    self.scheduleReminders(for: session, intervalMinutes: intervalMinutes)
                }
            case .denied:
                self.clearPendingSessionReminders()
                self.lastScheduleSignature = nil
            @unknown default:
                self.clearPendingSessionReminders()
                self.lastScheduleSignature = nil
            }
        }
    }

    private func clearPendingSessionReminders() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let ids = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(self.requestPrefix) }
            guard !ids.isEmpty else { return }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    private func scheduleSignature(for session: Session, intervalMinutes: Int) -> String {
        let custom = reminderCustomMessage
        return "\(session.id.uuidString)|\(Int(session.startTime.timeIntervalSince1970))|\(intervalMinutes)|\(reminderMessagePreset)|\(custom)|\(reminderIncludeSessionStats)"
    }

    private func scheduleReminders(for session: Session, intervalMinutes: Int) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { [weak self] requests in
            guard let self else { return }
            let existingIds = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(self.requestPrefix) }
            if !existingIds.isEmpty {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: existingIds)
            }

            let now = Date()
            let intervalSeconds = TimeInterval(intervalMinutes * 60)
            let elapsed = max(0, now.timeIntervalSince(session.startTime))
            let nextTick = Int(floor(elapsed / intervalSeconds)) + 1

            for index in nextTick..<(nextTick + self.maxScheduledReminders) {
                let reminderMinutes = index * intervalMinutes
                let fireDate = session.startTime.addingTimeInterval(TimeInterval(reminderMinutes * 60))
                let timeUntilFire = fireDate.timeIntervalSince(now)
                if timeUntilFire <= 0 { continue }

                let content = UNMutableNotificationContent()
                content.title = "Play Reminder"
                content.body = self.reminderBody(for: session, reminderMinutes: reminderMinutes)
                content.sound = .default

                let trigger = UNTimeIntervalNotificationTrigger(
                    timeInterval: max(1, timeUntilFire),
                    repeats: false
                )
                let identifier = "\(self.requestPrefix)\(session.id.uuidString).\(reminderMinutes)"
                let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                UNUserNotificationCenter.current().add(request)
            }
        }
    }

    private func reminderBody(for session: Session, reminderMinutes: Int) -> String {
        var lines: [String] = []
        lines.append("You've been playing this session for \(reminderMinutes) minutes.")
        lines.append(reminderMessagePreset)
        if !reminderCustomMessage.isEmpty {
            lines.append(reminderCustomMessage)
        }

        if reminderIncludeSessionStats {
            let buyIn = session.totalBuyIn.formatted(.number.grouping(.automatic))
            let comps = session.totalComp.formatted(.number.grouping(.automatic))
            let tier = session.startingTierPoints.formatted(.number.grouping(.automatic))
            let wlText: String
            if let winLoss = session.winLoss {
                let prefix = winLoss >= 0 ? "+" : ""
                wlText = "W/L: \(prefix)\(winLoss.formatted(.number.grouping(.automatic)))"
            } else {
                wlText = "W/L: pending close-out"
            }
            lines.append("Session stats - Buy-in: \(buyIn), Comps: \(comps), Tier: \(tier), \(wlText)")
        }

        return lines.joined(separator: "\n")
    }
}
#endif
