import Foundation

enum TierTapWidgetSnapshotBuilder {
    private static let chartPointLimit = 14
    private static let heatStripDays = 14

    static func build(
        sessions: [Session],
        liveSession: Session?,
        currencyCode: String,
        useExpectedValue: Bool,
        primaryColorHex: String?,
        secondaryColorHex: String?,
        layoutConfig: TierTapWidgetLayoutConfig,
        settingsBankroll: Int,
        bankrollResets: [BankrollResetEvent]
    ) -> TierTapHomeWidgetSnapshot {
        let layout = TierTapWidgetLayoutConfig.normalized(layoutConfig)
        let currencySymbol = TierTapWidgetSnapshotStore.currencySymbol(from: currencyCode)
        let closed = sessions.filter { $0.winLoss != nil }.sorted { $0.startTime < $1.startTime }
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        let yesterdayStart = cal.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart

        let bankroll = currentBankroll(
            sessions: closed,
            settingsBankroll: settingsBankroll,
            bankrollResets: bankrollResets
        )
        let priorBankroll = bankrollBeforeLastSession(
            sessions: closed,
            settingsBankroll: settingsBankroll,
            bankrollResets: bankrollResets
        )

        let todaySessions = closed.filter { cal.isDate($0.startTime, inSameDayAs: Date()) }
        let yesterdaySessions = closed.filter {
            $0.startTime >= yesterdayStart && $0.startTime < todayStart
        }
        let todayNet = todaySessions.reduce(0) { $0 + ($1.analyticsOutcome(useExpectedValue: useExpectedValue) ?? 0) }
        let yesterdayNet = yesterdaySessions.reduce(0) { $0 + ($1.analyticsOutcome(useExpectedValue: useExpectedValue) ?? 0) }

        let lastClosed = closed.last
        let priorClosed = closed.count >= 2 ? closed[closed.count - 2] : nil

        let isLive = liveSession != nil
        let liveStart = liveSession?.startTime
        let lastDuration = lastClosed.map { $0.duration }
        let priorDuration = priorClosed?.duration

        let sessionTitle: String
        let sessionValue: String
        let sessionSubtitle: String?
        if isLive, let live = liveSession {
            sessionTitle = live.game.isEmpty ? "Live Session" : live.game
            sessionValue = ""
            let casino = live.casino.trimmingCharacters(in: .whitespacesAndNewlines)
            sessionSubtitle = casino.isEmpty ? "Session in progress" : casino
        } else {
            sessionTitle = "Last Session"
            sessionValue = Session.durationString(lastDuration ?? 0)
            sessionSubtitle = lastClosed.map { relativeLastPlayed(casino: $0.casino, date: $0.startTime) }
        }

        let sessionTrend: TierTapHomeWidgetSnapshot.MetricTrend? = {
            if isLive { return .flat }
            guard let last = lastDuration, let prior = priorDuration else { return nil }
            return trend(current: Int(last), prior: Int(prior))
        }()

        let sessionChartPoints = closed.suffix(chartPointLimit).map { Int($0.duration) }
        let bankrollChartPoints = bankrollTimelineValues(
            sessions: closed,
            settingsBankroll: settingsBankroll,
            bankrollResets: bankrollResets
        )
        let dailyNetChartPoints = dailyNetSeries(
            sessions: closed,
            useExpectedValue: useExpectedValue,
            dayCount: chartPointLimit
        )
        let tierChartPoints = closed.suffix(chartPointLimit).compactMap {
            $0.endingTierPoints ?? $0.startingTierPoints
        }

        let lastTier = lastClosed?.endingTierPoints ?? lastClosed?.startingTierPoints
        let priorTier = priorClosed?.endingTierPoints ?? priorClosed?.startingTierPoints

        let winRate = winRatePercent(sessions: closed, useExpectedValue: useExpectedValue)
        let tap = TapLevel.compute(from: sessions)

        var catalog: [String: TierTapHomeWidgetSnapshot.Metric] = [
            TierTapWidgetMetricKind.bankroll.rawValue: .init(
                title: "Bankroll",
                value: "\(currencySymbol)\(bankroll.formatted(.number.grouping(.automatic)))",
                metricId: "bankroll",
                trend: priorBankroll.map { trend(current: bankroll, prior: $0) },
                chartPoints: bankrollChartPoints,
                subtitle: nil
            ),
            TierTapWidgetMetricKind.today.rawValue: .init(
                title: "Today",
                value: signedMoney(todayNet, symbol: currencySymbol),
                metricId: "today",
                trend: trend(current: todayNet, prior: yesterdayNet),
                chartPoints: dailyNetChartPoints,
                subtitle: todaySessions.isEmpty
                    ? "No sessions today"
                    : "\(todaySessions.count) session\(todaySessions.count == 1 ? "" : "s")"
            ),
            TierTapWidgetMetricKind.winRate.rawValue: .init(
                title: "Win Rate",
                value: "\(winRate)%",
                metricId: "winRate",
                trend: winRateTrend(for: closed, useExpectedValue: useExpectedValue),
                chartPoints: rollingWinRateSeries(
                    sessions: closed,
                    useExpectedValue: useExpectedValue,
                    windowSize: 4,
                    pointCount: chartPointLimit
                ),
                subtitle: closed.isEmpty ? "No sessions yet" : "\(closed.count) sessions"
            ),
            TierTapWidgetMetricKind.lastTier.rawValue: .init(
                title: "Last Tier",
                value: lastTier.map { $0.formatted(.number.grouping(.automatic)) } ?? "—",
                metricId: "tier",
                trend: {
                    guard let lastTier, let priorTier else { return nil }
                    return trend(current: lastTier, prior: priorTier)
                }(),
                chartPoints: tierChartPoints,
                subtitle: nil
            ),
            TierTapWidgetMetricKind.tapLevel.rawValue: .init(
                title: "Tap Level",
                value: "\(tap.emoji) Lv \(tap.level)",
                metricId: "tapLevel",
                trend: nil,
                chartPoints: [],
                subtitle: tap.title
            )
        ]

        if isLive, let live = liveSession {
            if let running = live.liveSessionRunningWinLoss {
                catalog[TierTapWidgetMetricKind.runningPL.rawValue] = .init(
                    title: "Running P/L",
                    value: signedMoney(running, symbol: currencySymbol),
                    metricId: "runningPL",
                    trend: running > 0 ? .up : (running < 0 ? .down : .flat),
                    chartPoints: [],
                    subtitle: nil
                )
            } else {
                catalog[TierTapWidgetMetricKind.runningPL.rawValue] = unavailableMetric(
                    title: "Running P/L",
                    metricId: "runningPL"
                )
            }

            if live.totalBuyIn > 0 {
                catalog[TierTapWidgetMetricKind.buyIn.rawValue] = .init(
                    title: "Buy-In",
                    value: "\(currencySymbol)\(live.totalBuyIn.formatted(.number.grouping(.automatic)))",
                    metricId: "buyIn",
                    trend: nil,
                    chartPoints: [],
                    subtitle: nil
                )
            } else {
                catalog[TierTapWidgetMetricKind.buyIn.rawValue] = unavailableMetric(
                    title: "Buy-In",
                    metricId: "buyIn"
                )
            }
        } else {
            catalog[TierTapWidgetMetricKind.runningPL.rawValue] = unavailableMetric(
                title: "Running P/L",
                metricId: "runningPL"
            )
            catalog[TierTapWidgetMetricKind.buyIn.rawValue] = unavailableMetric(
                title: "Buy-In",
                metricId: "buyIn"
            )
        }

        let recentDayNets = dailyNetSeries(
            sessions: closed,
            useExpectedValue: useExpectedValue,
            dayCount: heatStripDays
        )
        let cumulativeOutcomes = cumulativeOutcomeSeries(
            sessions: closed,
            useExpectedValue: useExpectedValue,
            limit: 24
        )

        return TierTapHomeWidgetSnapshot(
            updatedAt: Date(),
            currencySymbol: currencySymbol,
            primaryColorHex: primaryColorHex,
            secondaryColorHex: secondaryColorHex,
            layoutConfig: layout,
            isLiveSession: isLive,
            liveSessionStartTime: liveStart,
            liveCasino: liveSession?.casino,
            liveGame: liveSession?.game,
            sessionMetricTitle: sessionTitle,
            sessionMetricValue: sessionValue,
            sessionMetricSubtitle: sessionSubtitle,
            sessionMetricTrend: sessionTrend,
            sessionChartPoints: sessionChartPoints,
            metricCatalog: catalog,
            tapLevel: tap.level,
            tapLevelEmoji: tap.emoji,
            tapLevelTitle: tap.title,
            tapLevelProgress: tap.progressToNext,
            lastPlayedLabel: isLive ? nil : lastClosed.map { relativeLastPlayed(casino: $0.casino, date: $0.startTime) },
            recentDayNets: recentDayNets,
            cumulativeOutcomes: cumulativeOutcomes
        )
    }

    private static func unavailableMetric(title: String, metricId: String) -> TierTapHomeWidgetSnapshot.Metric {
        .init(
            title: title,
            value: "—",
            metricId: metricId,
            trend: nil,
            chartPoints: [],
            subtitle: nil
        )
    }

    private static func relativeLastPlayed(casino: String, date: Date) -> String {
        let trimmed = casino.trimmingCharacters(in: .whitespacesAndNewlines)
        let venue = trimmed.isEmpty ? "Last session" : trimmed
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let relative = formatter.localizedString(for: date, relativeTo: Date())
        return "\(venue) · \(relative)"
    }

    private static func cumulativeOutcomeSeries(
        sessions: [Session],
        useExpectedValue: Bool,
        limit: Int
    ) -> [Int] {
        var running = 0
        let points = sessions.map { session -> Int in
            running += session.analyticsOutcome(useExpectedValue: useExpectedValue) ?? 0
            return running
        }
        return Array(points.suffix(limit))
    }

    private static func bankrollTimelineValues(
        sessions: [Session],
        settingsBankroll: Int,
        bankrollResets: [BankrollResetEvent]
    ) -> [Int] {
        enum Event: Comparable {
            case reset(BankrollResetEvent)
            case session(Session)
            var date: Date {
                switch self {
                case .reset(let e): return e.date
                case .session(let s): return s.startTime
                }
            }
            static func < (l: Event, r: Event) -> Bool { l.date < r.date }
        }

        var events: [Event] = []
        events += bankrollResets.map { .reset($0) }
        events += sessions.map { .session($0) }
        events.sort(by: { $0.date < $1.date })

        guard !events.isEmpty else { return [settingsBankroll] }

        let lastReset = bankrollResets.last
        let baselineDate = lastReset?.date ?? Date.distantPast
        let sessionsBeforeBaseline = sessions.filter { $0.startTime < baselineDate }
        let initialRunning = (lastReset?.value ?? settingsBankroll)
            - sessionsBeforeBaseline.compactMap(\.winLoss).reduce(0, +)

        var running = initialRunning
        var values: [Int] = []
        for event in events {
            switch event {
            case .reset(let e):
                running = e.value
                values.append(running)
            case .session(let s):
                running += s.winLoss ?? 0
                values.append(running)
            }
        }
        return Array(values.suffix(chartPointLimit))
    }

    private static func dailyNetSeries(
        sessions: [Session],
        useExpectedValue: Bool,
        dayCount: Int
    ) -> [Int] {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        return (0..<dayCount).reversed().map { offset in
            guard let dayStart = cal.date(byAdding: .day, value: -offset, to: todayStart),
                  let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return 0 }
            return sessions
                .filter { $0.startTime >= dayStart && $0.startTime < dayEnd }
                .reduce(0) { $0 + ($1.analyticsOutcome(useExpectedValue: useExpectedValue) ?? 0) }
        }
    }

    private static func rollingWinRateSeries(
        sessions: [Session],
        useExpectedValue: Bool,
        windowSize: Int,
        pointCount: Int
    ) -> [Int] {
        guard sessions.count >= windowSize else {
            return sessions.map { session in
                (session.analyticsOutcome(useExpectedValue: useExpectedValue) ?? 0) > 0 ? 100 : 0
            }
        }
        let rates = (windowSize...sessions.count).map { endIndex in
            let window = Array(sessions[(endIndex - windowSize)..<endIndex])
            return winRatePercent(sessions: window, useExpectedValue: useExpectedValue)
        }
        return Array(rates.suffix(pointCount))
    }

    private static func currentBankroll(
        sessions: [Session],
        settingsBankroll: Int,
        bankrollResets: [BankrollResetEvent]
    ) -> Int {
        let lastReset = bankrollResets.last
        let after = lastReset?.date ?? Date.distantPast
        let baseline = lastReset?.value ?? settingsBankroll
        let sum = sessions
            .filter { $0.startTime >= after }
            .compactMap(\.winLoss)
            .reduce(0, +)
        return baseline + sum
    }

    private static func bankrollBeforeLastSession(
        sessions: [Session],
        settingsBankroll: Int,
        bankrollResets: [BankrollResetEvent]
    ) -> Int? {
        guard sessions.last != nil else { return nil }
        let withoutLast = Array(sessions.dropLast())
        return currentBankroll(
            sessions: withoutLast,
            settingsBankroll: settingsBankroll,
            bankrollResets: bankrollResets
        )
    }

    private static func winRateTrend(
        for closed: [Session],
        useExpectedValue: Bool
    ) -> TierTapHomeWidgetSnapshot.MetricTrend? {
        guard closed.count >= 4 else { return nil }
        let recent = Array(closed.suffix(2))
        let prior = Array(closed.dropLast(2).suffix(2))
        let recentRate = winRatePercent(sessions: recent, useExpectedValue: useExpectedValue)
        let priorRate = winRatePercent(sessions: prior, useExpectedValue: useExpectedValue)
        return trend(current: recentRate, prior: priorRate)
    }

    private static func winRatePercent(sessions: [Session], useExpectedValue: Bool) -> Int {
        guard !sessions.isEmpty else { return 0 }
        let wins = sessions.filter { ($0.analyticsOutcome(useExpectedValue: useExpectedValue) ?? 0) > 0 }.count
        return Int((Double(wins) / Double(sessions.count)) * 100.0)
    }

    private static func trend(current: Int, prior: Int) -> TierTapHomeWidgetSnapshot.MetricTrend {
        if current > prior { return .up }
        if current < prior { return .down }
        return .flat
    }

    private static func signedMoney(_ amount: Int, symbol: String) -> String {
        if amount > 0 { return "+\(symbol)\(amount.formatted(.number.grouping(.automatic)))" }
        if amount < 0 { return "-\(symbol)\(abs(amount).formatted(.number.grouping(.automatic)))" }
        return "\(symbol)0"
    }
}
