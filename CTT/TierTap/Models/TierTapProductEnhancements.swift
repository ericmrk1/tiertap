import Foundation
import UserNotifications

/// Master switch and shared helpers for the Jul 2026 product enhancements.
/// Flip `isEnabled` to `false` to hide every new surface during development/testing.
enum TierTapProductEnhancements {
    /// Global on/off for avg-bet close-out, Community browse, tier goals, streaks,
    /// loyalty paywall copy, Monthly Wrapped, and loyalty analytics dashboards.
    static let isEnabled = true

    /// Sprint 2 release surfaces (program ladders, trip prep/recap, nudges, Journal tab,
    /// paywall social proof, Community lurker upsell, Analytics 7/30/90 chips).
    /// Requires `isEnabled` — flip this alone to hide Sprint 2 without rolling back Sprint 1.
    static let sprint2Enabled = true

    /// Combined gate used by all Sprint 2 UI and notification paths.
    static var isSprint2Active: Bool { isEnabled && sprint2Enabled }

    static let showMonthlyWrappedNotificationName = Notification.Name("TierTapShowMonthlyWrapped")
    static let showTripPrepNotificationName = Notification.Name("TierTapShowTripPrep")
    static let showJournalNotificationName = Notification.Name("TierTapShowJournal")
    static let monthlyWrappedNotificationId = "ctt.monthly.wrapped"
    /// Matches `SettingsStore` / UserDefaults; default is on when the key is absent.
    static let monthlyWrappedNotificationsEnabledKey = "ctt_monthly_wrapped_notifications_enabled"
    private static let lastNotifiedMonthKey = "ctt_wrapped_last_notified_month"
    private static let lastTierPaceNudgeDayKey = "ctt_nudge_tier_pace_day"
    private static let lastTripNudgeTripIdKey = "ctt_nudge_trip_id"
    private static let dismissedTripPrepPrefix = "ctt_dismissed_trip_prep_"
    private static let dismissedTripRecapPrefix = "ctt_dismissed_trip_recap_"

    // MARK: - Logging streaks

    struct LoggingStreak: Equatable {
        /// Consecutive calendar weeks (ending this week) with ≥1 completed session.
        var consecutiveWeeks: Int
        /// Consecutive calendar days with ≥1 completed session, counting back from the most recent session day.
        var consecutiveVisitDays: Int

        var isActive: Bool { consecutiveWeeks > 0 || consecutiveVisitDays > 0 }

        var homeStatusLine: String? {
            if consecutiveWeeks >= 2 {
                return "\(consecutiveWeeks)-week logging streak"
            }
            if consecutiveVisitDays >= 2 {
                return "\(consecutiveVisitDays)-day visit streak"
            }
            if consecutiveWeeks == 1 {
                return "1-week logging streak"
            }
            if consecutiveVisitDays == 1 {
                return "Logged today"
            }
            return nil
        }
    }

    static func loggingStreak(from sessions: [Session], calendar: Calendar = .current, now: Date = Date()) -> LoggingStreak {
        let completed = sessions.filter { $0.isComplete && !$0.isLive }
        guard !completed.isEmpty else {
            return LoggingStreak(consecutiveWeeks: 0, consecutiveVisitDays: 0)
        }

        let dayKeys = Set(completed.map { calendar.startOfDay(for: $0.startTime) })
        let sortedDays = dayKeys.sorted(by: >)
        var visitStreak = 0
        if let mostRecent = sortedDays.first {
            var cursor = mostRecent
            while dayKeys.contains(cursor) {
                visitStreak += 1
                guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
                cursor = prev
            }
            // If the most recent session day is older than yesterday, streak is broken for "today" framing,
            // but we still report the consecutive run ending on that last session day.
        }

        var weekStreak = 0
        var weekCursor = startOfWeek(for: now, calendar: calendar)
        while true {
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekCursor) ?? weekCursor
            let hasSession = completed.contains { s in
                s.startTime >= weekCursor && s.startTime < weekEnd
            }
            if hasSession {
                weekStreak += 1
                guard let prev = calendar.date(byAdding: .day, value: -7, to: weekCursor) else { break }
                weekCursor = prev
            } else {
                break
            }
        }

        return LoggingStreak(consecutiveWeeks: weekStreak, consecutiveVisitDays: visitStreak)
    }

    private static func startOfWeek(for date: Date, calendar: Calendar) -> Date {
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: comps) ?? calendar.startOfDay(for: date)
    }

    // MARK: - Rated capture

    struct RatedCaptureSummary {
        var sessionsWithBothBets: Int
        var averageGap: Double
        var underRatedCount: Int
        var overOrEqualCount: Int
        var byProperty: [(property: String, averageGap: Double, count: Int)]
        var byGame: [(game: String, averageGap: Double, count: Int)]

        var underRatedPercent: Double {
            guard sessionsWithBothBets > 0 else { return 0 }
            return Double(underRatedCount) / Double(sessionsWithBothBets) * 100
        }
    }

    static func ratedCaptureSummary(from sessions: [Session]) -> RatedCaptureSummary {
        let rows: [(Session, Int)] = sessions.compactMap { s in
            guard s.isComplete, !s.isLive,
                  let actual = s.avgBetActual, let rated = s.avgBetRated else { return nil }
            return (s, rated - actual)
        }
        guard !rows.isEmpty else {
            return RatedCaptureSummary(
                sessionsWithBothBets: 0,
                averageGap: 0,
                underRatedCount: 0,
                overOrEqualCount: 0,
                byProperty: [],
                byGame: []
            )
        }
        let gaps = rows.map(\.1)
        let avg = Double(gaps.reduce(0, +)) / Double(gaps.count)
        let under = gaps.filter { $0 < 0 }.count
        let over = gaps.count - under

        func group(_ key: (Session) -> String) -> [(String, Double, Int)] {
            let grouped = Dictionary(grouping: rows, by: { key($0.0) })
            return grouped.compactMap { name, items -> (String, Double, Int)? in
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                let g = items.map(\.1)
                let a = Double(g.reduce(0, +)) / Double(g.count)
                return (trimmed, a, g.count)
            }
            .sorted { $0.2 > $1.2 }
        }

        return RatedCaptureSummary(
            sessionsWithBothBets: rows.count,
            averageGap: avg,
            underRatedCount: under,
            overOrEqualCount: over,
            byProperty: group { $0.casino }.prefix(8).map { (property: $0.0, averageGap: $0.1, count: $0.2) },
            byGame: group { $0.game }.prefix(8).map { (game: $0.0, averageGap: $0.1, count: $0.2) }
        )
    }

    // MARK: - Tiers fastest

    struct TierEfficiencyRow: Identifiable, Equatable {
        var id: String { "\(property)|\(game)|\(program)" }
        var property: String
        var game: String
        var program: String
        var sessionCount: Int
        var tiersPerHour: Double
        var tiersPerHundredRatedBetHour: Double?
    }

    static func tierEfficiencyRankings(from sessions: [Session], minimumSessions: Int = 2) -> [TierEfficiencyRow] {
        let eligible = sessions.filter {
            $0.isComplete && !$0.isLive && ($0.tierPointsEarned ?? 0) != 0 && $0.hoursPlayed > 0
        }
        let grouped = Dictionary(grouping: eligible) { s -> String in
            let property = s.casino.trimmingCharacters(in: .whitespacesAndNewlines)
            let game = s.game.trimmingCharacters(in: .whitespacesAndNewlines)
            let program = (s.rewardsProgramName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(property)|\(game)|\(program)"
        }
        return grouped.compactMap { _, items -> TierEfficiencyRow? in
            guard items.count >= minimumSessions else { return nil }
            let tphValues = items.compactMap(\.tiersPerHour)
            guard !tphValues.isEmpty else { return nil }
            let avgTPH = tphValues.reduce(0, +) / Double(tphValues.count)
            let per100 = items.compactMap(\.tiersPerHundredRatedBetHour)
            let avgPer100 = per100.isEmpty ? nil : per100.reduce(0, +) / Double(per100.count)
            let first = items[0]
            return TierEfficiencyRow(
                property: first.casino,
                game: first.game,
                program: (first.rewardsProgramName ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                sessionCount: items.count,
                tiersPerHour: avgTPH,
                tiersPerHundredRatedBetHour: avgPer100
            )
        }
        .sorted { $0.tiersPerHour > $1.tiersPerHour }
    }

    // MARK: - Comp ROI / True EV

    struct CompROISummary {
        var sessionCount: Int
        var cashNet: Int
        var totalComps: Int
        var freePlay: Int
        var expectedValue: Int
        var hours: Double
        var compsAsPercentOfLoss: Double?
        var byProperty: [(property: String, cashNet: Int, comps: Int, ev: Int, hours: Double)]

        var evPerHour: Double? {
            guard hours > 0 else { return nil }
            return Double(expectedValue) / hours
        }
    }

    static func compROISummary(from sessions: [Session]) -> CompROISummary {
        let closed = sessions.filter { $0.isComplete && !$0.isLive && $0.winLoss != nil }
        let cashNet = closed.compactMap(\.winLoss).reduce(0, +)
        let comps = closed.reduce(0) { $0 + $1.totalComp }
        let freePlay = closed.reduce(0) { $0 + $1.totalFreePlay }
        let ev = closed.compactMap(\.expectedValue).reduce(0, +)
        let hours = closed.reduce(0.0) { $0 + $1.hoursPlayed }
        let losses = closed.compactMap(\.winLoss).filter { $0 < 0 }.map { abs($0) }.reduce(0, +)
        let compsPct: Double? = losses > 0 ? Double(comps) / Double(losses) * 100 : nil

        let byProp = Dictionary(grouping: closed, by: { $0.casino.trimmingCharacters(in: .whitespacesAndNewlines) })
            .compactMap { name, items -> (String, Int, Int, Int, Double)? in
                guard !name.isEmpty else { return nil }
                let c = items.compactMap(\.winLoss).reduce(0, +)
                let co = items.reduce(0) { $0 + $1.totalComp }
                let e = items.compactMap(\.expectedValue).reduce(0, +)
                let h = items.reduce(0.0) { $0 + $1.hoursPlayed }
                return (name, c, co, e, h)
            }
            .sorted { $0.3 > $1.3 }
            .prefix(8)
            .map { (property: $0.0, cashNet: $0.1, comps: $0.2, ev: $0.3, hours: $0.4) }

        return CompROISummary(
            sessionCount: closed.count,
            cashNet: cashNet,
            totalComps: comps,
            freePlay: freePlay,
            expectedValue: ev,
            hours: hours,
            compsAsPercentOfLoss: compsPct,
            byProperty: Array(byProp)
        )
    }

    // MARK: - Monthly Wrapped

    struct MonthlyWrappedSummary: Identifiable, Equatable {
        var id: String { monthKey }
        var monthKey: String
        var monthLabel: String
        var sessionCount: Int
        var tierPointsEarned: Int
        var cashNet: Int
        var expectedValue: Int
        var hoursPlayed: Double
        var bestGameForTiers: String?
        var bestGameTiersPerHour: Double?
        var topMood: SessionMood?
        var biggestEVSession: Int?
    }

    static func previousMonthKey(calendar: Calendar = .current, now: Date = Date()) -> String {
        guard let prev = calendar.date(byAdding: .month, value: -1, to: now) else {
            return monthKey(for: now, calendar: calendar)
        }
        return monthKey(for: prev, calendar: calendar)
    }

    static func monthKey(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    static func wrappedSummary(
        forMonthKey targetKey: String,
        sessions: [Session],
        calendar: Calendar = .current
    ) -> MonthlyWrappedSummary? {
        let closed = sessions.filter { $0.isComplete && !$0.isLive }
        let inMonth = closed.filter { monthKey(for: $0.startTime, calendar: calendar) == targetKey }
        guard !inMonth.isEmpty else { return nil }

        let parts = targetKey.split(separator: "-").compactMap { Int($0) }
        var label = targetKey
        if parts.count == 2,
           let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: 1)) {
            let df = DateFormatter()
            df.dateFormat = "MMMM yyyy"
            label = df.string(from: date)
        }

        let tiers = inMonth.compactMap(\.tierPointsEarned).reduce(0, +)
        let cash = inMonth.compactMap(\.winLoss).reduce(0, +)
        let ev = inMonth.compactMap(\.expectedValue).reduce(0, +)
        let hours = inMonth.reduce(0.0) { $0 + $1.hoursPlayed }

        let byGame = Dictionary(grouping: inMonth.filter { ($0.tierPointsEarned ?? 0) != 0 && $0.hoursPlayed > 0 }, by: \.game)
        var bestGame: String?
        var bestTPH: Double?
        for (game, items) in byGame {
            let tph = items.compactMap(\.tiersPerHour)
            guard !tph.isEmpty else { continue }
            let avg = tph.reduce(0, +) / Double(tph.count)
            if bestTPH == nil || avg > (bestTPH ?? -.infinity) {
                bestTPH = avg
                bestGame = game
            }
        }

        let moodCounts = Dictionary(grouping: inMonth.compactMap(\.sessionMood), by: { $0 }).mapValues(\.count)
        let topMood = moodCounts.max(by: { $0.value < $1.value })?.key
        let biggestEV = inMonth.compactMap(\.expectedValue).max()

        return MonthlyWrappedSummary(
            monthKey: targetKey,
            monthLabel: label,
            sessionCount: inMonth.count,
            tierPointsEarned: tiers,
            cashNet: cash,
            expectedValue: ev,
            hoursPlayed: hours,
            bestGameForTiers: bestGame,
            bestGameTiersPerHour: bestTPH,
            topMood: topMood,
            biggestEVSession: biggestEV
        )
    }

    static func currentWrappedSummary(sessions: [Session], calendar: Calendar = .current, now: Date = Date()) -> MonthlyWrappedSummary? {
        // Prefer previous calendar month; fall back to current month if previous is empty.
        let prevKey = previousMonthKey(calendar: calendar, now: now)
        if let prev = wrappedSummary(forMonthKey: prevKey, sessions: sessions, calendar: calendar) {
            return prev
        }
        return wrappedSummary(forMonthKey: monthKey(for: now, calendar: calendar), sessions: sessions, calendar: calendar)
    }

    // MARK: - Wrapped notifications

    /// Whether Monthly Wrapped local notifications are allowed. Defaults to `true` when unset.
    static var monthlyWrappedNotificationsEnabled: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: monthlyWrappedNotificationsEnabledKey) == nil { return true }
        return defaults.bool(forKey: monthlyWrappedNotificationsEnabledKey)
    }

    static func cancelPendingMonthlyWrappedNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [monthlyWrappedNotificationId])
        center.removeDeliveredNotifications(withIdentifiers: [monthlyWrappedNotificationId])
    }

    static func scheduleMonthlyWrappedNotificationIfNeeded(sessions: [Session]) {
        guard isEnabled else { return }
        guard monthlyWrappedNotificationsEnabled else {
            cancelPendingMonthlyWrappedNotifications()
            return
        }
        let key = previousMonthKey()
        if UserDefaults.standard.string(forKey: lastNotifiedMonthKey) == key { return }
        guard let summary = wrappedSummary(forMonthKey: key, sessions: sessions) else { return }

        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                postWrappedNotification(summary: summary, monthKey: key)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    guard granted else { return }
                    postWrappedNotification(summary: summary, monthKey: key)
                }
            default:
                break
            }
        }
    }

    private static func postWrappedNotification(summary: MonthlyWrappedSummary, monthKey: String) {
        let content = UNMutableNotificationContent()
        content.title = "Your TierTap Wrapped is ready"
        content.body = "\(summary.monthLabel): \(summary.sessionCount) sessions, \(summary.tierPointsEarned) tier points. Tap to open your recap."
        content.sound = .default
        content.userInfo = ["type": "monthly_wrapped", "monthKey": monthKey]

        let request = UNNotificationRequest(
            identifier: monthlyWrappedNotificationId,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1.5, repeats: false)
        )
        UNUserNotificationCenter.current().add(request) { error in
            guard error == nil else { return }
            UserDefaults.standard.set(monthKey, forKey: lastNotifiedMonthKey)
        }
    }

    static func handleNotificationResponse(_ response: UNNotificationResponse) -> Bool {
        guard isEnabled else { return false }
        let info = response.notification.request.content.userInfo
        guard let type = info["type"] as? String else { return false }
        switch type {
        case "monthly_wrapped":
            NotificationCenter.default.post(name: showMonthlyWrappedNotificationName, object: nil)
            return true
        case "trip_prep", "tier_pace":
            guard isSprint2Active else { return false }
            NotificationCenter.default.post(name: showTripPrepNotificationName, object: nil)
            return true
        case "wrapped_nudge":
            guard isSprint2Active else { return false }
            NotificationCenter.default.post(name: showMonthlyWrappedNotificationName, object: nil)
            return true
        default:
            return false
        }
    }

    // MARK: - Sprint 2: program ladder presets

    struct LadderTierStep: Identifiable, Hashable {
        let label: String
        let points: Int
        let isCustom: Bool
        let customID: UUID?

        var id: String {
            if let customID { return customID.uuidString }
            return "\(label)-\(points)"
        }

        init(label: String, points: Int, isCustom: Bool = false, customID: UUID? = nil) {
            self.label = label
            self.points = points
            self.isCustom = isCustom
            self.customID = customID
        }
    }

    struct ProgramLadder: Identifiable, Hashable {
        var id: String { programName }
        let programName: String
        let tiers: [LadderTierStep]
    }

    /// Static status ladders (tier credits / points thresholds). Approximate for lesser-published programs.
    static let programLadders: [ProgramLadder] = [
        ProgramLadder(programName: "MGM Rewards", tiers: [
            LadderTierStep(label: "Pearl", points: 20_000),
            LadderTierStep(label: "Gold", points: 75_000),
            LadderTierStep(label: "Platinum", points: 200_000)
        ]),
        ProgramLadder(programName: "Caesars Rewards", tiers: [
            LadderTierStep(label: "Platinum", points: 5_000),
            LadderTierStep(label: "Diamond", points: 15_000),
            LadderTierStep(label: "Diamond Plus", points: 25_000),
            LadderTierStep(label: "Diamond Elite", points: 75_000),
            LadderTierStep(label: "Seven Stars", points: 150_000)
        ]),
        ProgramLadder(programName: "Wynn Rewards", tiers: [
            LadderTierStep(label: "Red", points: 5_000),
            LadderTierStep(label: "Black", points: 25_000),
            LadderTierStep(label: "Elite", points: 75_000)
        ]),
        ProgramLadder(programName: "Grazie Rewards", tiers: [
            LadderTierStep(label: "Grazie Gold", points: 10_000),
            LadderTierStep(label: "Grazie Platinum", points: 35_000),
            LadderTierStep(label: "Grazie Elite", points: 100_000)
        ]),
        ProgramLadder(programName: "Identity Rewards", tiers: [
            LadderTierStep(label: "Silver", points: 10_000),
            LadderTierStep(label: "Gold", points: 40_000),
            LadderTierStep(label: "Platinum", points: 100_000)
        ]),
        ProgramLadder(programName: "B Connected", tiers: [
            LadderTierStep(label: "Preferred", points: 5_000),
            LadderTierStep(label: "Elite", points: 20_000),
            LadderTierStep(label: "Premier", points: 50_000)
        ])
    ]

    static func ladder(matchingProgram name: String) -> ProgramLadder? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let exact = programLadders.first(where: { $0.programName.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return exact
        }
        return programLadders.first { ladder in
            trimmed.localizedCaseInsensitiveContains(ladder.programName)
                || ladder.programName.localizedCaseInsensitiveContains(trimmed)
        }
    }

    /// Built-in ladder (if any) merged with user-authored custom status steps for that program.
    static func resolvedLadder(
        matchingProgram name: String,
        customEntries: [CustomLadderTierEntry]
    ) -> ProgramLadder? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let builtIn = ladder(matchingProgram: trimmed)
        let programName = builtIn?.programName ?? trimmed
        let customForProgram = customEntries.filter {
            $0.programName.caseInsensitiveCompare(programName) == .orderedSame
                || $0.programName.caseInsensitiveCompare(trimmed) == .orderedSame
        }
        guard builtIn != nil || !customForProgram.isEmpty else { return nil }

        var tiers = builtIn?.tiers ?? []
        var existingPoints = Set(tiers.map(\.points))
        var existingLabels = Set(tiers.map { $0.label.lowercased() })
        for entry in customForProgram.sorted(by: { $0.points < $1.points }) {
            let labelKey = entry.label.lowercased()
            if existingPoints.contains(entry.points) || existingLabels.contains(labelKey) {
                continue
            }
            tiers.append(
                LadderTierStep(
                    label: entry.label,
                    points: entry.points,
                    isCustom: true,
                    customID: entry.id
                )
            )
            existingPoints.insert(entry.points)
            existingLabels.insert(labelKey)
        }
        tiers.sort { $0.points < $1.points }
        return ProgramLadder(programName: programName, tiers: tiers)
    }

    /// Program names available in the ladder picker (built-ins + programs that already have custom tiers + extras).
    static func availableLadderProgramNames(
        customEntries: [CustomLadderTierEntry],
        extraProgramNames: [String] = []
    ) -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        func appendUnique(_ raw: String) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { return }
            seen.insert(key)
            names.append(trimmed)
        }
        for ladder in programLadders {
            appendUnique(ladder.programName)
        }
        for entry in customEntries {
            appendUnique(entry.programName)
        }
        for extra in extraProgramNames {
            appendUnique(extra)
        }
        return names
    }

    // MARK: - Sprint 2: trip prep / post-trip recap

    struct TripHomeCardModel: Identifiable, Equatable {
        enum Kind { case prep, recap }
        var id: String { "\(kind)-\(trip.id.uuidString)" }
        let kind: Kind
        let trip: Trip
        let daysUntilStart: Int?
        let daysSinceEnd: Int?
        let sessionCount: Int
        let tierPoints: Int
        let cashNet: Int
        let hoursPlayed: Double
    }

    static func tripPrepCandidates(
        trips: [Trip],
        sessions: [Session],
        withinDays: Int = 7,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> [TripHomeCardModel] {
        guard isSprint2Active else { return [] }
        let today = calendar.startOfDay(for: now)
        return trips.compactMap { trip in
            guard trip.timelineStatus(relativeTo: now, calendar: calendar) == .upcoming else { return nil }
            let startDay = calendar.startOfDay(for: trip.startDate)
            let days = calendar.dateComponents([.day], from: today, to: startDay).day ?? 999
            guard days >= 0, days <= withinDays else { return nil }
            if UserDefaults.standard.bool(forKey: dismissedTripPrepPrefix + trip.id.uuidString) { return nil }
            let stats = tripSessionStats(trip: trip, sessions: sessions, calendar: calendar)
            return TripHomeCardModel(
                kind: .prep,
                trip: trip,
                daysUntilStart: days,
                daysSinceEnd: nil,
                sessionCount: stats.count,
                tierPoints: stats.tiers,
                cashNet: stats.cash,
                hoursPlayed: stats.hours
            )
        }
        .sorted { ($0.daysUntilStart ?? 99) < ($1.daysUntilStart ?? 99) }
    }

    static func tripRecapCandidates(
        trips: [Trip],
        sessions: [Session],
        withinDays: Int = 7,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> [TripHomeCardModel] {
        guard isSprint2Active else { return [] }
        let today = calendar.startOfDay(for: now)
        return trips.compactMap { trip in
            guard trip.timelineStatus(relativeTo: now, calendar: calendar) == .past else { return nil }
            let endDay = calendar.startOfDay(for: trip.endDate)
            let days = calendar.dateComponents([.day], from: endDay, to: today).day ?? 999
            guard days >= 0, days <= withinDays else { return nil }
            if UserDefaults.standard.bool(forKey: dismissedTripRecapPrefix + trip.id.uuidString) { return nil }
            let stats = tripSessionStats(trip: trip, sessions: sessions, calendar: calendar)
            return TripHomeCardModel(
                kind: .recap,
                trip: trip,
                daysUntilStart: nil,
                daysSinceEnd: days,
                sessionCount: stats.count,
                tierPoints: stats.tiers,
                cashNet: stats.cash,
                hoursPlayed: stats.hours
            )
        }
        .sorted { ($0.daysSinceEnd ?? 99) < ($1.daysSinceEnd ?? 99) }
    }

    static func dismissTripCard(_ model: TripHomeCardModel) {
        let prefix = model.kind == .prep ? dismissedTripPrepPrefix : dismissedTripRecapPrefix
        UserDefaults.standard.set(true, forKey: prefix + model.trip.id.uuidString)
    }

    private static func tripSessionStats(
        trip: Trip,
        sessions: [Session],
        calendar: Calendar
    ) -> (count: Int, tiers: Int, cash: Int, hours: Double) {
        let ids = Trip.eligibleSessionIDs(
            startDate: trip.startDate,
            endDate: trip.endDate,
            sessions: sessions,
            calendar: calendar
        )
        let matched = sessions.filter { ids.contains($0.id) && $0.isComplete && !$0.isLive }
        let tiers = matched.compactMap(\.tierPointsEarned).reduce(0, +)
        let cash = matched.compactMap(\.winLoss).reduce(0, +)
        let hours = matched.reduce(0.0) { $0 + $1.hoursPlayed }
        return (matched.count, tiers, cash, hours)
    }

    // MARK: - Sprint 2: between-session nudges

    static func scheduleBetweenSessionNudgesIfNeeded(
        sessions: [Session],
        trips: [Trip],
        walletCards: [RewardWalletCard]
    ) {
        guard isSprint2Active else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            let allowed: Bool
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                allowed = true
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    if granted {
                        postBetweenSessionNudges(sessions: sessions, trips: trips, walletCards: walletCards)
                    }
                }
                return
            default:
                allowed = false
            }
            guard allowed else { return }
            postBetweenSessionNudges(sessions: sessions, trips: trips, walletCards: walletCards)
        }
    }

    private static func postBetweenSessionNudges(
        sessions: [Session],
        trips: [Trip],
        walletCards: [RewardWalletCard],
        calendar: Calendar = .current,
        now: Date = Date()
    ) {
        // Trip tomorrow (or today-start within 1 day)
        if let prep = tripPrepCandidates(trips: trips, sessions: sessions, withinDays: 1, calendar: calendar, now: now).first,
           UserDefaults.standard.string(forKey: lastTripNudgeTripIdKey) != prep.trip.id.uuidString {
            let days = prep.daysUntilStart ?? 0
            let when = days == 0 ? "today" : "tomorrow"
            let content = UNMutableNotificationContent()
            content.title = "Trip \(when): \(prep.trip.displayTitle)"
            content.body = "Open TierTap to prep goals, wallet, and session logging."
            content.sound = .default
            content.userInfo = ["type": "trip_prep", "tripId": prep.trip.id.uuidString]
            let request = UNNotificationRequest(
                identifier: "ctt.nudge.trip.\(prep.trip.id.uuidString)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
            )
            UNUserNotificationCenter.current().add(request) { error in
                guard error == nil else { return }
                UserDefaults.standard.set(prep.trip.id.uuidString, forKey: lastTripNudgeTripIdKey)
            }
        }

        // Tier pace: points remaining + quiet stretch (≥3 days since last session)
        let dayKey = monthDayKey(for: now, calendar: calendar)
        if UserDefaults.standard.string(forKey: lastTierPaceNudgeDayKey) != dayKey,
           let goalCard = walletCards.first(where: { ($0.pointsRemainingToTierGoal ?? 0) > 0 }),
           let remaining = goalCard.pointsRemainingToTierGoal {
            let completed = sessions.filter { $0.isComplete && !$0.isLive }
            let lastSessionDay = completed.map { calendar.startOfDay(for: $0.startTime) }.max()
            let quietDays: Int
            if let last = lastSessionDay {
                quietDays = calendar.dateComponents([.day], from: last, to: calendar.startOfDay(for: now)).day ?? 0
            } else {
                quietDays = 3
            }
            if quietDays >= 3 {
                let label = (goalCard.tierGoalLabel ?? "next tier").trimmingCharacters(in: .whitespacesAndNewlines)
                let content = UNMutableNotificationContent()
                content.title = "\(remaining) pts to \(label.isEmpty ? "your goal" : label)"
                content.body = quietDays >= 7
                    ? "It’s been a while — log a session to keep your loyalty pace honest."
                    : "A short session can move the needle. Open TierTap when you’re ready."
                content.sound = .default
                content.userInfo = ["type": "tier_pace"]
                let request = UNNotificationRequest(
                    identifier: "ctt.nudge.tier_pace.\(dayKey)",
                    content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3.5, repeats: false)
                )
                UNUserNotificationCenter.current().add(request) { error in
                    guard error == nil else { return }
                    UserDefaults.standard.set(dayKey, forKey: lastTierPaceNudgeDayKey)
                }
            }
        }
    }

    private static func monthDayKey(for date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    // MARK: - Sprint 2: paywall social proof

    struct PaywallSocialProofLine: Identifiable, Equatable {
        let id: String
        let text: String
    }

    static func paywallSocialProofLines(
        from sessions: [Session],
        currencySymbol: String = "$"
    ) -> [PaywallSocialProofLine] {
        guard isSprint2Active else { return [] }
        var lines: [PaywallSocialProofLine] = []
        let closed = sessions.filter { $0.isComplete && !$0.isLive && $0.winLoss != nil }

        let rankings = tierEfficiencyRankings(from: closed, minimumSessions: 2)
        if let best = rankings.first, best.tiersPerHour > 0 {
            let game = best.game.trimmingCharacters(in: .whitespacesAndNewlines)
            let property = best.property.trimmingCharacters(in: .whitespacesAndNewlines)
            let whereText: String
            if !game.isEmpty && !property.isEmpty {
                whereText = "\(game) at \(property)"
            } else if !game.isEmpty {
                whereText = game
            } else if !property.isEmpty {
                whereText = property
            } else {
                whereText = "your best mix"
            }
            lines.append(PaywallSocialProofLine(
                id: "tph",
                text: String(format: "Your best pace: %.0f tiers/hr on %@", best.tiersPerHour, whereText)
            ))
        }

        let comps = compROISummary(from: closed)
        if let pct = comps.compsAsPercentOfLoss, pct > 0, comps.totalComps > 0 {
            lines.append(PaywallSocialProofLine(
                id: "comps",
                text: String(format: "Comps covered %.0f%% of your losses in logged sessions", pct)
            ))
        }

        let rated = ratedCaptureSummary(from: closed)
        if rated.sessionsWithBothBets >= 2 {
            let gap = Int(rated.averageGap.rounded())
            if gap < 0 {
                lines.append(PaywallSocialProofLine(
                    id: "rated",
                    text: "Hosts under-rate you by ~\(currencySymbol)\(abs(gap)) avg bet — worth watching"
                ))
            } else if gap > 0 {
                lines.append(PaywallSocialProofLine(
                    id: "rated",
                    text: "You’re rated ~\(currencySymbol)\(gap) above actual bet on average"
                ))
            }
        }

        if closed.count >= 5 {
            lines.append(PaywallSocialProofLine(
                id: "count",
                text: "Built from \(closed.count) completed sessions on this device"
            ))
        }

        return Array(lines.prefix(3))
    }
}

/// User-authored loyalty ladder status step (persisted via SettingsStore).
struct CustomLadderTierEntry: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var programName: String
    var label: String
    var points: Int

    init(id: UUID = UUID(), programName: String, label: String, points: Int) {
        self.id = id
        self.programName = programName
        self.label = label
        self.points = points
    }
}

// MARK: - Wallet tier goals

extension RewardWalletCard {
    /// Parses a numeric points value from `currentTier` when the field is numeric (loyalty points).
    var parsedCurrentTierPoints: Int? {
        let trimmed = currentTier.trimmingCharacters(in: .whitespacesAndNewlines)
        if let n = Int(trimmed) { return n }
        let digits = trimmed.filter(\.isNumber)
        guard !digits.isEmpty, let n = Int(digits) else { return nil }
        return n
    }

    var hasTierGoal: Bool {
        (tierGoalPoints ?? 0) > 0
    }

    var pointsRemainingToTierGoal: Int? {
        guard let goal = tierGoalPoints, goal > 0, let current = parsedCurrentTierPoints else { return nil }
        return max(0, goal - current)
    }

    var tierGoalProgress: Double? {
        guard let goal = tierGoalPoints, goal > 0, let current = parsedCurrentTierPoints else { return nil }
        return min(1, max(0, Double(current) / Double(goal)))
    }
}
