import Foundation

enum TierTapWidgetSnapshotBuilder {
    static func build(
        sessions: [Session],
        liveSession: Session?,
        currencyCode: String,
        useExpectedValue: Bool,
        primaryColorHex: String?,
        settingsBankroll: Int,
        bankrollResets: [BankrollResetEvent]
    ) -> TierTapHomeWidgetSnapshot {
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

        let sessionTitle = isLive ? "Session" : "Last Session"
        let sessionValue = isLive ? "" : Session.durationString(lastDuration ?? 0)
        let sessionTrend: TierTapHomeWidgetSnapshot.MetricTrend? = {
            if isLive { return .flat }
            guard let last = lastDuration, let prior = priorDuration else { return nil }
            return trend(current: Int(last), prior: Int(prior))
        }()

        let todayMetric: TierTapHomeWidgetSnapshot.Metric = {
            if !todaySessions.isEmpty {
                return .init(
                    title: "Today",
                    value: signedMoney(todayNet, symbol: currencySymbol),
                    metricId: "today",
                    trend: trend(current: todayNet, prior: yesterdayNet)
                )
            }
            let wins = closed.filter { ($0.analyticsOutcome(useExpectedValue: useExpectedValue) ?? 0) > 0 }.count
            let rate = closed.isEmpty ? 0 : Int((Double(wins) / Double(closed.count)) * 100.0)
            return .init(
                title: "Win Rate",
                value: "\(rate)%",
                metricId: "winRate",
                trend: winRateTrend(for: closed, useExpectedValue: useExpectedValue)
            )
        }()

        let lastTier = lastClosed?.endingTierPoints ?? lastClosed?.startingTierPoints
        let priorTier = priorClosed?.endingTierPoints ?? priorClosed?.startingTierPoints

        let metrics: [TierTapHomeWidgetSnapshot.Metric] = [
            .init(
                title: "Bankroll",
                value: "\(currencySymbol)\(bankroll.formatted(.number.grouping(.automatic)))",
                metricId: "bankroll",
                trend: priorBankroll.map { trend(current: bankroll, prior: $0) }
            ),
            todayMetric,
            .init(
                title: "Last Tier",
                value: lastTier.map { $0.formatted(.number.grouping(.automatic)) } ?? "—",
                metricId: "tier",
                trend: {
                    guard let lastTier, let priorTier else { return nil }
                    return trend(current: lastTier, prior: priorTier)
                }()
            )
        ]

        return TierTapHomeWidgetSnapshot(
            updatedAt: Date(),
            currencySymbol: currencySymbol,
            primaryColorHex: primaryColorHex,
            isLiveSession: isLive,
            liveSessionStartTime: liveStart,
            sessionMetricTitle: sessionTitle,
            sessionMetricValue: sessionValue,
            sessionMetricTrend: sessionTrend,
            metrics: metrics
        )
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
        guard let last = sessions.last else { return nil }
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
