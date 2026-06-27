import WidgetKit
import SwiftUI

// MARK: - Timeline

struct TierTapHomeWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: TierTapHomeWidgetSnapshot?
}

struct TierTapHomeWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TierTapHomeWidgetEntry {
        TierTapHomeWidgetEntry(date: Date(), snapshot: TierTapHomeWidgetPreviewData.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (TierTapHomeWidgetEntry) -> Void) {
        completion(TierTapHomeWidgetEntry(date: Date(), snapshot: TierTapWidgetSnapshotStore.load() ?? TierTapHomeWidgetPreviewData.sample))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TierTapHomeWidgetEntry>) -> Void) {
        completion(TierTapHomeWidgetTimelineBuilder.timeline())
    }
}

private enum TierTapHomeWidgetTimelineBuilder {
    static func timeline() -> Timeline<TierTapHomeWidgetEntry> {
        let now = Date()
        let snapshot = TierTapWidgetSnapshotStore.load()

        if snapshot?.isLiveSession == true {
            let entries: [TierTapHomeWidgetEntry] = (0..<60).compactMap { index in
                guard let date = Calendar.current.date(byAdding: .second, value: index * 30, to: now) else { return nil }
                return TierTapHomeWidgetEntry(date: date, snapshot: snapshot)
            }
            let refresh = Calendar.current.date(byAdding: .minute, value: 30, to: now) ?? now.addingTimeInterval(1800)
            return Timeline(entries: entries.isEmpty ? [TierTapHomeWidgetEntry(date: now, snapshot: snapshot)] : entries, policy: .after(refresh))
        }

        let entry = TierTapHomeWidgetEntry(date: now, snapshot: snapshot)
        let refresh = Calendar.current.date(byAdding: .minute, value: 15, to: now) ?? now.addingTimeInterval(900)
        return Timeline(entries: [entry], policy: .after(refresh))
    }
}

enum TierTapHomeWidgetPreviewData {
    static let sample = TierTapHomeWidgetSnapshot(
        updatedAt: Date(),
        currencySymbol: "$",
        primaryColorHex: "#1A1A2E",
        secondaryColorHex: "#16213E",
        layoutConfig: .default,
        isLiveSession: false,
        liveSessionStartTime: nil,
        liveCasino: nil,
        liveGame: nil,
        sessionMetricTitle: "Last Session",
        sessionMetricValue: "02:14:35",
        sessionMetricSubtitle: "Bellagio · 2d ago",
        sessionMetricTrend: .up,
        sessionChartPoints: [5400, 7200, 4800, 8100, 7700, 8040],
        metricCatalog: [
            "bankroll": .init(title: "Bankroll", value: "$4,820", metricId: "bankroll", trend: .up, chartPoints: [4200, 4380, 4510, 4620, 4710, 4820], subtitle: nil),
            "today": .init(title: "Today", value: "+$240", metricId: "today", trend: .up, chartPoints: [-120, 80, 40, 160, 200, 240], subtitle: "2 sessions"),
            "winRate": .init(title: "Win Rate", value: "58%", metricId: "winRate", trend: .up, chartPoints: [52, 54, 55, 56, 57, 58], subtitle: "24 sessions"),
            "lastTier": .init(title: "Last Tier", value: "18,420", metricId: "tier", trend: .up, chartPoints: [17200, 17550, 17800, 18020, 18200, 18420], subtitle: nil)
        ],
        tapLevel: 42,
        tapLevelEmoji: "🎰",
        tapLevelTitle: "Regular",
        tapLevelProgress: 0.64,
        lastPlayedLabel: "Bellagio · 2d ago",
        recentDayNets: [0, -80, 120, 0, 40, 160, 0, 0, 200, 0, 60, 0, 80, 240],
        cumulativeOutcomes: [-120, 80, 240, 180, 420, 380, 520, 610, 720, 840],
        recentSessions: [
            .init(id: UUID().uuidString, casino: "Bellagio", game: "Blackjack", timeLabel: "2:30 PM", winLossText: "+$420", tierPointsText: "+180 pts", isVerified: true),
            .init(id: UUID().uuidString, casino: "Aria", game: "Slots", timeLabel: "Jun 24", winLossText: "-$120", tierPointsText: "+45 pts", isVerified: false),
            .init(id: UUID().uuidString, casino: "Wynn", game: "Craps", timeLabel: "Jun 22", winLossText: "+$860", tierPointsText: "+220 pts", isVerified: true)
        ]
    )
}

// MARK: - Widget

struct TierTapHomeWidget: Widget {
    private let kind = "TierTapHomeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TierTapHomeWidgetProvider()) { entry in
            TierTapHomeWidgetEntryView(entry: entry)
                .tierTapWidgetContainer(snapshot: entry.snapshot ?? TierTapHomeWidgetPreviewData.sample)
        }
        .configurationDisplayName("TierTap Dashboard")
        .description("Session time, bankroll, trends, and tap level.")
        .supportedFamilies(supportedFamilies)
        .contentMarginsDisabled()
    }

    private var supportedFamilies: [WidgetFamily] {
        var families: [WidgetFamily] = [
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular
        ]
        if #available(iOS 17.0, *) {
            families.append(.systemExtraLarge)
        }
        return families
    }
}

// MARK: - Root view

struct TierTapHomeWidgetEntryView: View {
    let entry: TierTapHomeWidgetEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: TierTapHomeWidgetSnapshot {
        entry.snapshot ?? TierTapHomeWidgetPreviewData.sample
    }

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                TierTapHomeSmallWidgetView(snapshot: snapshot)
            case .systemMedium:
                TierTapHomeMediumWidgetView(snapshot: snapshot)
            case .systemLarge:
                TierTapHomeLargeWidgetView(snapshot: snapshot)
            case .systemExtraLarge:
                TierTapHomeExtraLargeWidgetView(snapshot: snapshot)
            case .accessoryInline:
                TierTapLockScreenInlineView(snapshot: snapshot)
            case .accessoryCircular:
                TierTapLockScreenCircularView(snapshot: snapshot)
            case .accessoryRectangular:
                TierTapLockScreenRectangularView(snapshot: snapshot)
            default:
                TierTapHomeMediumWidgetView(snapshot: snapshot)
            }
        }
    }
}

// MARK: - Small

private struct TierTapHomeSmallWidgetView: View {
    let snapshot: TierTapHomeWidgetSnapshot

    private let edgeInsets = EdgeInsets(top: 9, leading: 8, bottom: 9, trailing: 8)

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 6
            let contentW = geo.size.width - edgeInsets.leading - edgeInsets.trailing
            let contentH = geo.size.height - edgeInsets.top - edgeInsets.bottom
            let cellH = max((contentH - spacing) / 2, 1)
            let kinds = snapshot.layoutConfig.smallMetrics

            VStack(spacing: spacing) {
                ForEach(Array(kinds.enumerated()), id: \.offset) { _, kind in
                    if let metric = snapshot.metric(for: kind) {
                        smallMetricCell(kind: kind, metric: metric, width: contentW, height: cellH)
                    }
                }
            }
            .frame(width: contentW, height: contentH)
            .padding(edgeInsets)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
    }

    private func smallMetricCell(
        kind: TierTapWidgetMetricKind,
        metric: TierTapHomeWidgetSnapshot.Metric,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        let isSession = kind == .session
        let isLiveSession = isSession && snapshot.isLiveSession

        return Link(destination: TierTapWidgetDeepLink.forMetric(kind.linkMetricId, isLive: isLiveSession)) {
            TierTapWidgetLargeMetricTile(
                title: isLiveSession ? (snapshot.liveGame?.isEmpty == false ? snapshot.liveGame! : "Session") : metric.title,
                value: isLiveSession ? nil : metric.value,
                liveStart: isLiveSession ? snapshot.liveSessionStartTime : nil,
                metricId: kind.linkMetricId,
                trend: metric.trend?.liveTrend,
                cellHeight: height,
                showLiveDot: isLiveSession
            )
            .frame(width: width, height: height)
        }
    }
}

// MARK: - Medium

private struct TierTapHomeMediumWidgetView: View {
    let snapshot: TierTapHomeWidgetSnapshot

    private let edgeInsets = EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)

    private var displayMetrics: [(kind: TierTapWidgetMetricKind, metric: TierTapHomeWidgetSnapshot.Metric)] {
        snapshot.layoutConfig.standardMetrics.compactMap { kind in
            guard let metric = snapshot.metric(for: kind) else { return nil }
            return (kind, metric)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let contentW = geo.size.width - edgeInsets.leading - edgeInsets.trailing
            let contentH = geo.size.height - edgeInsets.top - edgeInsets.bottom
            let graphW = min(max(contentW * 0.30, 64), 96)
            let showHeader = !snapshot.isLiveSession
            let headerH: CGFloat = showHeader ? 11 : 0
            let rowSpacing: CGFloat = 3
            let rowCount = CGFloat(displayMetrics.count)
            let rowH = max((contentH - headerH - rowSpacing * max(rowCount - 1, 0)) / max(rowCount, 1), 22)

            VStack(alignment: .leading, spacing: rowSpacing) {
                if showHeader {
                    mediumHeader
                        .frame(height: headerH)
                }

                ForEach(Array(displayMetrics.enumerated()), id: \.offset) { _, item in
                    metricRow(item.kind, metric: item.metric, graphWidth: graphW, rowHeight: rowH)
                }
            }
            .frame(width: contentW, height: contentH, alignment: .top)
            .padding(edgeInsets)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
    }

    @ViewBuilder
    private var mediumHeader: some View {
        HStack {
            if snapshot.isLiveSession {
                TierTapWidgetLiveBadge(compact: false)
            }
            Spacer(minLength: 0)
            Image("TierTapLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 12)
                .accessibilityLabel("TierTap")
        }
    }

    private func metricRow(
        _ kind: TierTapWidgetMetricKind,
        metric: TierTapHomeWidgetSnapshot.Metric,
        graphWidth: CGFloat,
        rowHeight: CGFloat
    ) -> some View {
        let isSession = kind == .session
        let isLiveSession = isSession && snapshot.isLiveSession
        let chartPoints = isSession ? snapshot.sessionChartPoints : metric.chartPoints
        let subtitle: String? = isSession ? nil : metric.subtitle

        return Link(destination: TierTapWidgetDeepLink.forMetric(kind.linkMetricId, isLive: isLiveSession)) {
            TierTapWidgetMetricRow(
                title: isLiveSession ? (snapshot.liveGame?.isEmpty == false ? snapshot.liveGame! : "Session") : metric.title,
                subtitle: subtitle,
                value: isLiveSession ? nil : metric.value,
                liveStart: isLiveSession ? snapshot.liveSessionStartTime : nil,
                metricId: kind.linkMetricId,
                trend: (isSession ? snapshot.sessionMetricTrend : metric.trend)?.liveTrend,
                chartPoints: chartPoints,
                style: .medium,
                emphasized: false,
                graphWidth: graphWidth,
                rowHeight: rowHeight
            )
        }
    }
}

// MARK: - Large

private struct TierTapHomeLargeWidgetView: View {
    let snapshot: TierTapHomeWidgetSnapshot

    private var displayMetrics: [(kind: TierTapWidgetMetricKind, metric: TierTapHomeWidgetSnapshot.Metric)] {
        snapshot.layoutConfig.standardMetrics.compactMap { kind in
            guard let metric = snapshot.metric(for: kind) else { return nil }
            return (kind, metric)
        }
    }

    private var showsTapLevelHero: Bool {
        !snapshot.isLiveSession && !snapshot.layoutConfig.standardMetrics.contains(.tapLevel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TierTapWidgetLargeHeader(snapshot: snapshot)

            if showsTapLevelHero {
                TierTapWidgetTapLevelHero(snapshot: snapshot)
                TierTapWidgetHeatStrip(nets: snapshot.recentDayNets)
            }

            ForEach(Array(displayMetrics.enumerated()), id: \.offset) { _, item in
                metricRow(item.kind, metric: item.metric)
            }
        }
        .padding(12)
    }

    private func metricRow(_ kind: TierTapWidgetMetricKind, metric: TierTapHomeWidgetSnapshot.Metric) -> some View {
        let isSession = kind == .session
        let isLiveSession = isSession && snapshot.isLiveSession
        let chartPoints = isSession ? snapshot.sessionChartPoints : metric.chartPoints
        let subtitle = isSession ? snapshot.sessionMetricSubtitle : metric.subtitle

        return Link(destination: TierTapWidgetDeepLink.forMetric(kind.linkMetricId, isLive: isLiveSession)) {
            TierTapWidgetMetricRow(
                title: isLiveSession ? (snapshot.liveGame?.isEmpty == false ? snapshot.liveGame! : "Session") : metric.title,
                subtitle: subtitle,
                value: isLiveSession ? nil : metric.value,
                liveStart: isLiveSession ? snapshot.liveSessionStartTime : nil,
                metricId: kind.linkMetricId,
                trend: (isSession ? snapshot.sessionMetricTrend : metric.trend)?.liveTrend,
                chartPoints: chartPoints,
                style: .large,
                emphasized: false,
                graphWidth: 96,
                rowHeight: nil
            )
        }
    }
}

// MARK: - Extra Large

private struct TierTapHomeExtraLargeWidgetView: View {
    let snapshot: TierTapHomeWidgetSnapshot

    private var displayMetrics: [(kind: TierTapWidgetMetricKind, metric: TierTapHomeWidgetSnapshot.Metric)] {
        snapshot.layoutConfig.standardMetrics.compactMap { kind in
            guard let metric = snapshot.metric(for: kind) else { return nil }
            return (kind, metric)
        }
    }

    private var showsTapLevelHero: Bool {
        !snapshot.isLiveSession && !snapshot.layoutConfig.standardMetrics.contains(.tapLevel)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                TierTapWidgetLargeHeader(snapshot: snapshot)
                if showsTapLevelHero {
                    TierTapWidgetTapLevelHero(snapshot: snapshot)
                    TierTapWidgetHeatStrip(nets: snapshot.recentDayNets)
                }
                ForEach(Array(displayMetrics.enumerated()), id: \.offset) { _, item in
                    metricRow(item.kind, metric: item.metric)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text("Cumulative Results")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.65))
                TierTapWidgetSparkline(
                    points: snapshot.cumulativeOutcomes,
                    trend: cumulativeTrend
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: 200)
        }
        .padding(14)
    }

    private var cumulativeTrend: LiveSessionMetricTrend? {
        guard let first = snapshot.cumulativeOutcomes.first,
              let last = snapshot.cumulativeOutcomes.last else { return nil }
        if last > first { return .up }
        if last < first { return .down }
        return .flat
    }

    private func metricRow(_ kind: TierTapWidgetMetricKind, metric: TierTapHomeWidgetSnapshot.Metric) -> some View {
        let isSession = kind == .session
        let isLiveSession = isSession && snapshot.isLiveSession
        let chartPoints = isSession ? snapshot.sessionChartPoints : metric.chartPoints
        let subtitle = isSession ? snapshot.sessionMetricSubtitle : metric.subtitle

        return Link(destination: TierTapWidgetDeepLink.forMetric(kind.linkMetricId, isLive: isLiveSession)) {
            TierTapWidgetMetricRow(
                title: isLiveSession ? (snapshot.liveGame?.isEmpty == false ? snapshot.liveGame! : "Session") : metric.title,
                subtitle: subtitle,
                value: isLiveSession ? nil : metric.value,
                liveStart: isLiveSession ? snapshot.liveSessionStartTime : nil,
                metricId: kind.linkMetricId,
                trend: (isSession ? snapshot.sessionMetricTrend : metric.trend)?.liveTrend,
                chartPoints: chartPoints,
                style: .large,
                emphasized: false,
                graphWidth: 80,
                rowHeight: nil
            )
        }
    }
}

// MARK: - Lock Screen

private struct TierTapLockScreenInlineView: View {
    let snapshot: TierTapHomeWidgetSnapshot

    var body: some View {
        if snapshot.isLiveSession, let start = snapshot.liveSessionStartTime {
            HStack(spacing: 4) {
                Text("LIVE")
                    .foregroundColor(.red)
                Text(start, style: .timer)
                    .monospacedDigit()
            }
            .widgetURL(TierTapWidgetDeepLink.live)
        } else if let today = snapshot.metric(for: .today) ?? snapshot.metric(for: .winRate) {
            Text("\(today.title) \(today.value)")
                .widgetURL(TierTapWidgetDeepLink.forMetric(today.metricId, isLive: false))
        } else {
            Text("TierTap")
                .widgetURL(TierTapWidgetDeepLink.home)
        }
    }
}

private struct TierTapLockScreenCircularView: View {
    let snapshot: TierTapHomeWidgetSnapshot

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if snapshot.isLiveSession, let start = snapshot.liveSessionStartTime {
                VStack(spacing: 0) {
                    Text(start, style: .timer)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .minimumScaleFactor(0.6)
                    Text("LIVE")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.red)
                }
            } else if let bankroll = snapshot.metric(for: .bankroll) {
                VStack(spacing: 0) {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 10))
                    Text(bankroll.value)
                        .font(.system(size: 8, weight: .bold))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
            } else {
                Image("TierTapLogo")
                    .resizable()
                    .scaledToFit()
                    .padding(4)
            }
        }
        .widgetURL(TierTapWidgetDeepLink.forMetric("bankroll", isLive: snapshot.isLiveSession))
    }
}

private struct TierTapLockScreenRectangularView: View {
    let snapshot: TierTapHomeWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                if snapshot.isLiveSession {
                    TierTapWidgetLiveBadge(compact: true)
                } else {
                    Text("TierTap")
                        .font(.caption2.weight(.bold))
                }
                Spacer(minLength: 0)
            }
            if snapshot.isLiveSession, let start = snapshot.liveSessionStartTime {
                Text(start, style: .timer)
                    .font(.headline.monospacedDigit())
                    .foregroundColor(.green)
                if let subtitle = snapshot.sessionMetricSubtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            } else {
                ForEach(Array(snapshot.smallDisplayMetrics().enumerated()), id: \.offset) { _, metric in
                    HStack {
                        Text(metric.title)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer(minLength: 0)
                        Text(metric.value)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(TierTapWidgetValueStyle.color(for: metric.metricId, trend: metric.trend?.liveTrend))
                    }
                }
            }
        }
        .widgetURL(TierTapWidgetDeepLink.home)
    }
}

// MARK: - Shared chrome

private struct TierTapWidgetLargeHeader: View {
    let snapshot: TierTapHomeWidgetSnapshot

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 4) {
                Image("TierTapLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .accessibilityLabel("TierTap")

                if snapshot.isLiveSession {
                    TierTapWidgetLiveBadge(compact: false)
                } else if let lastPlayed = snapshot.lastPlayedLabel {
                    Text(lastPlayed)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct TierTapWidgetLiveBadge: View {
    var compact: Bool

    var body: some View {
        HStack(spacing: compact ? 3 : 4) {
            Circle()
                .fill(Color.red)
                .frame(width: compact ? 4 : 5, height: compact ? 4 : 5)
            Text("LIVE")
                .font(.system(size: compact ? 7 : 8, weight: .bold))
                .foregroundColor(.red)
        }
        .padding(.horizontal, compact ? 4 : 6)
        .padding(.vertical, compact ? 2 : 3)
        .background(Color.red.opacity(0.18))
        .clipShape(Capsule())
    }
}

private struct TierTapWidgetTapLevelHero: View {
    let snapshot: TierTapHomeWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(snapshot.tapLevelEmoji)
                    .font(.system(size: 18))
                Text("Level \(snapshot.tapLevel) · \(snapshot.tapLevelTitle)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(Color.green.opacity(0.85))
                        .frame(width: max(geo.size.width * snapshot.tapLevelProgress, 4))
                }
            }
            .frame(height: 5)
        }
    }
}

private struct TierTapWidgetHeatStrip: View {
    let nets: [Int]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(nets.enumerated()), id: \.offset) { _, net in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color(for: net))
                    .frame(maxWidth: .infinity)
                    .frame(height: 8)
            }
        }
    }

    private func color(for net: Int) -> Color {
        if net > 0 { return .green.opacity(0.85) }
        if net < 0 { return .red.opacity(0.85) }
        return .white.opacity(0.18)
    }
}

// MARK: - Metric tile (small — two full-width stacked metrics)

private struct TierTapWidgetLargeMetricTile: View {
    let title: String
    let value: String?
    let liveStart: Date?
    let metricId: String
    let trend: LiveSessionMetricTrend?
    let cellHeight: CGFloat
    var showLiveDot: Bool = false

    private var iconSide: CGFloat { max(10, min(cellHeight * 0.14, 12)) }
    private var titleSize: CGFloat { max(10, min(cellHeight * 0.16, 11)) }
    private var valueSize: CGFloat { max(14, min(cellHeight * 0.28, 20)) }
    private var trendSize: CGFloat { max(10, min(cellHeight * 0.18, 14)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                if showLiveDot {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 5, height: 5)
                }
                TierTapWidgetMetricIcon(metricId: metricId, side: iconSide)
                Text(title)
                    .font(.system(size: titleSize, weight: .medium))
                    .foregroundColor(.white.opacity(0.65))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 0)

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                valueText
                    .font(.system(size: valueSize, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                Spacer(minLength: 0)
                if let trend {
                    Image(systemName: trend.symbolName)
                        .font(.system(size: trendSize, weight: .semibold))
                        .foregroundColor(trend.color)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var valueText: some View {
        if let liveStart {
            Text(liveStart, style: .timer)
                .monospacedDigit()
                .foregroundColor(.green)
        } else {
            Text(value ?? "—")
                .foregroundColor(TierTapWidgetValueStyle.color(for: metricId, trend: trend))
        }
    }
}

// MARK: - Metric tile (compact grid — legacy)

private struct TierTapWidgetMetricTile: View {
    let title: String
    let value: String?
    let liveStart: Date?
    let metricId: String
    let trend: LiveSessionMetricTrend?
    let cellSize: CGSize
    var showLiveDot: Bool = false

    private var iconSide: CGFloat { 8 }
    private var titleSize: CGFloat { max(8, min(cellSize.height * 0.18, 9)) }
    private var valueSize: CGFloat { max(10, min(cellSize.height * 0.24, 12)) }
    private var trendSize: CGFloat { max(8, min(cellSize.height * 0.16, 10)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                if showLiveDot {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 4, height: 4)
                }
                TierTapWidgetMetricIcon(metricId: metricId, side: iconSide)
                Text(title)
                    .font(.system(size: titleSize, weight: .medium))
                    .foregroundColor(.white.opacity(0.65))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 0)

            HStack(alignment: .lastTextBaseline, spacing: 3) {
                valueText
                    .font(.system(size: valueSize, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                Spacer(minLength: 0)
                if let trend {
                    Image(systemName: trend.symbolName)
                        .font(.system(size: trendSize, weight: .semibold))
                        .foregroundColor(trend.color)
                }
            }
        }
        .padding(2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var valueText: some View {
        if let liveStart {
            Text(liveStart, style: .timer)
                .monospacedDigit()
                .foregroundColor(.green)
        } else {
            Text(value ?? "—")
                .foregroundColor(TierTapWidgetValueStyle.color(for: metricId, trend: trend))
        }
    }
}

// MARK: - Metric row

private enum TierTapWidgetMetricRowStyle {
    case medium
    case large
}

private struct TierTapWidgetMetricRow: View {
    let title: String
    let subtitle: String?
    let value: String?
    let liveStart: Date?
    let metricId: String
    let trend: LiveSessionMetricTrend?
    let chartPoints: [Int]
    let style: TierTapWidgetMetricRowStyle
    let emphasized: Bool
    let graphWidth: CGFloat
    let rowHeight: CGFloat?

    private var isLarge: Bool { style == .large }

    private var titleFont: Font {
        switch style {
        case .medium: return .system(size: 9, weight: .medium)
        case .large: return .system(size: 11, weight: .medium)
        }
    }

    private var valueFont: Font {
        switch style {
        case .medium:
            return .system(size: emphasized ? 14 : 13, weight: .semibold)
        case .large:
            return .system(size: emphasized ? 22 : 20, weight: .semibold)
        }
    }

    private var iconSide: CGFloat { isLarge ? 11 : 9 }

    var body: some View {
        Group {
            if let rowHeight {
                rowContent(chartHeight: max(rowHeight - 6, 18))
                    .frame(height: rowHeight)
            } else {
                GeometryReader { rowGeo in
                    rowContent(chartHeight: max(rowGeo.size.height * 0.85, isLarge ? 36 : 24))
                        .frame(width: rowGeo.size.width, height: rowGeo.size.height, alignment: .leading)
                }
                .frame(minHeight: isLarge ? 44 : 32)
            }
        }
    }

    private func rowContent(chartHeight: CGFloat) -> some View {
        HStack(alignment: .center, spacing: isLarge ? 10 : 10) {
            VStack(alignment: .leading, spacing: isLarge ? 2 : 2) {
                HStack(spacing: 3) {
                    TierTapWidgetMetricIcon(metricId: metricId, side: iconSide)
                    Text(title)
                        .font(titleFont)
                        .foregroundColor(.white.opacity(0.65))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                if isLarge, let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.45))
                        .lineLimit(1)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    valueText
                        .font(valueFont)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                    if let trend {
                        Image(systemName: trend.symbolName)
                            .font(.system(size: isLarge ? 14 : 11, weight: .semibold))
                            .foregroundColor(trend.color)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !chartPoints.isEmpty {
                TierTapWidgetSparkline(points: chartPoints, trend: trend)
                    .frame(width: graphWidth, height: chartHeight)
            }
        }
    }

    @ViewBuilder
    private var valueText: some View {
        if let liveStart {
            Text(liveStart, style: .timer)
                .monospacedDigit()
                .foregroundColor(.green)
        } else {
            Text(value ?? "—")
                .foregroundColor(TierTapWidgetValueStyle.color(for: metricId, trend: trend))
        }
    }
}

// MARK: - Value styling

private enum TierTapWidgetValueStyle {
    static func color(for metricId: String, trend: LiveSessionMetricTrend?) -> Color {
        switch trend {
        case .up: return .green
        case .down: return .red
        case .flat: return .white
        case .none:
            if metricId == "timer" { return .white }
            return .white.opacity(0.9)
        }
    }
}

// MARK: - Metric icon

private enum TierTapWidgetMetricIcons {
    static func sfSymbol(for metricId: String) -> String? {
        switch metricId {
        case "timer": "clock.fill"
        case "bankroll": "dollarsign.circle.fill"
        case "today": "calendar"
        case "winRate": "percent"
        case "tier": "star.circle"
        case "runningPL": "chart.line.uptrend.xyaxis"
        case "buyIn": "plus.circle"
        case "tapLevel": "star.fill"
        default: nil
        }
    }
}

private struct TierTapWidgetMetricIcon: View {
    let metricId: String
    let side: CGFloat

    var body: some View {
        if let symbol = TierTapWidgetMetricIcons.sfSymbol(for: metricId) {
            Image(systemName: symbol)
                .font(.system(size: side, weight: .semibold))
                .foregroundColor(.white.opacity(0.65))
        }
    }
}

// MARK: - Sparkline

private struct TierTapWidgetSparkline: View {
    let points: [Int]
    let trend: LiveSessionMetricTrend?

    private var strokeColor: Color {
        switch trend {
        case .up: return .green
        case .down: return .red
        case .flat, .none: return chartDirectionColor
        }
    }

    private var chartDirectionColor: Color {
        guard points.count >= 2 else { return .white.opacity(0.55) }
        let first = points.first!
        let last = points.last!
        if last > first { return .green }
        if last < first { return .red }
        return .white.opacity(0.55)
    }

    var body: some View {
        GeometryReader { geo in
            let values = normalizedValues
            let minV = values.min() ?? 0
            let maxV = values.max() ?? 1
            let range = max(maxV - minV, 0.001)
            let stepX = geo.size.width / CGFloat(max(values.count - 1, 1))
            let lastIndex = values.count - 1
            let lastX = CGFloat(lastIndex) * stepX
            let lastY = geo.size.height - ((values[lastIndex] - minV) / range) * geo.size.height

            ZStack {
                if values.count > 1 {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: geo.size.height))
                        for (index, value) in values.enumerated() {
                            let x = CGFloat(index) * stepX
                            let y = geo.size.height - ((value - minV) / range) * geo.size.height
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                        path.addLine(to: CGPoint(x: lastX, y: geo.size.height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [strokeColor.opacity(0.28), strokeColor.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }

                Path { path in
                    for (index, value) in values.enumerated() {
                        let x = CGFloat(index) * stepX
                        let y = geo.size.height - ((value - minV) / range) * geo.size.height
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(strokeColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

                if values.count > 1 {
                    Circle()
                        .fill(strokeColor)
                        .frame(width: 5, height: 5)
                        .position(x: lastX, y: lastY)
                }
            }
        }
    }

    private var normalizedValues: [CGFloat] {
        let raw = points.isEmpty ? [0, 0] : points
        return raw.map { CGFloat($0) }
    }
}

// MARK: - Background

struct TierTapWidgetBackground: View {
    let snapshot: TierTapHomeWidgetSnapshot

    var body: some View {
        LinearGradient(
            colors: [
                TierTapWidgetColor.fromHex(snapshot.primaryColorHex) ?? Color(red: 0.06, green: 0.06, blue: 0.1),
                TierTapWidgetColor.fromHex(snapshot.secondaryColorHex) ?? Color(red: 0.02, green: 0.02, blue: 0.06),
                Color(red: 0.01, green: 0.01, blue: 0.03)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct TierTapWidgetContainerModifier: ViewModifier {
    let snapshot: TierTapHomeWidgetSnapshot

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.containerBackground(for: .widget) {
                TierTapWidgetBackground(snapshot: snapshot)
            }
        } else {
            content.background(TierTapWidgetBackground(snapshot: snapshot))
        }
    }
}

extension View {
    func tierTapWidgetContainer(snapshot: TierTapHomeWidgetSnapshot) -> some View {
        modifier(TierTapWidgetContainerModifier(snapshot: snapshot))
    }
}

enum TierTapWidgetDeepLink {
    static let home = URL(string: "com.app.tiertap://sessions")!
    static let bankroll = URL(string: "com.app.tiertap://sessions/bankroll")!
    static let analytics = URL(string: "com.app.tiertap://analytics")!
    static let history = URL(string: "com.app.tiertap://sessions/history")!
    static let live = URL(string: "com.app.tiertap://sessions/live")!

    static func sessionDetail(_ sessionID: String) -> URL {
        URL(string: "com.app.tiertap://sessions/detail/\(sessionID)")!
    }

    static func forMetric(_ metricId: String, isLive: Bool) -> URL {
        switch metricId {
        case "timer", "runningPL", "buyIn":
            return isLive ? live : home
        case "bankroll":
            return bankroll
        case "today", "winRate":
            return analytics
        case "tier":
            return history
        default:
            return home
        }
    }
}

private extension TierTapHomeWidgetSnapshot.MetricTrend {
    var liveTrend: LiveSessionMetricTrend {
        switch self {
        case .up: return .up
        case .down: return .down
        case .flat: return .flat
        }
    }
}

enum TierTapWidgetColor {
    static func fromHex(_ hex: String?) -> Color? {
        guard var raw = hex?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if raw.hasPrefix("#") { raw.removeFirst() }
        guard raw.count == 6, let value = UInt64(raw, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}

#if DEBUG
struct TierTapHomeWidget_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            TierTapHomeWidgetEntryView(entry: .init(date: Date(), snapshot: TierTapHomeWidgetPreviewData.sample))
                .tierTapWidgetContainer(snapshot: TierTapHomeWidgetPreviewData.sample)
                .previewContext(WidgetPreviewContext(family: .systemSmall))
            TierTapHomeWidgetEntryView(entry: .init(date: Date(), snapshot: TierTapHomeWidgetPreviewData.sample))
                .tierTapWidgetContainer(snapshot: TierTapHomeWidgetPreviewData.sample)
                .previewContext(WidgetPreviewContext(family: .systemMedium))
            TierTapHomeWidgetEntryView(entry: .init(date: Date(), snapshot: TierTapHomeWidgetPreviewData.sample))
                .tierTapWidgetContainer(snapshot: TierTapHomeWidgetPreviewData.sample)
                .previewContext(WidgetPreviewContext(family: .systemLarge))
        }
    }
}
#endif
