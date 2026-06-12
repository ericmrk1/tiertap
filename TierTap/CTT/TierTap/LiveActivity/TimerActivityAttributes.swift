import ActivityKit
import Foundation
import SwiftUI

struct TimerActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var startTime: Date
        var casino: String
        var game: String
        var totalBuyIn: Int
        var startingTierPoints: Int
        var rewardsProgramName: String?
        var totalFreePlay: Int
        var totalComp: Int
        var liveTrackedStackAmount: Int?
        var currencySymbol: String
        /// When true, live summary omits stack (slots sessions close out only).
        var isSlotsSession: Bool = false
    }
    var sessionID: String
}

struct LiveSessionSummaryMetric: Identifiable, Hashable {
    let id: String
    let title: String
    let value: String
}

enum LiveSessionSummaryMetricsBuilder {
    static func metrics(
        casino: String,
        game: String,
        startingTierPoints: Int,
        totalBuyIn: Int,
        totalFreePlay: Int,
        totalComp: Int,
        liveTrackedStackAmount: Int?,
        currencySymbol: String,
        isSlotsSession: Bool = false
    ) -> [LiveSessionSummaryMetric] {
        func money(_ amount: Int) -> String {
            "\(currencySymbol)\(amount.formatted(.number.grouping(.automatic)))"
        }
        var metrics: [LiveSessionSummaryMetric] = [
            LiveSessionSummaryMetric(id: "location", title: "Location", value: casino),
            LiveSessionSummaryMetric(id: "game", title: "Game", value: game),
            LiveSessionSummaryMetric(
                id: "tier",
                title: "Tier",
                value: startingTierPoints.formatted(.number.grouping(.automatic))
            ),
            LiveSessionSummaryMetric(id: "buyIn", title: "Buy-In", value: money(totalBuyIn)),
            LiveSessionSummaryMetric(id: "freePlay", title: "Free Play", value: money(totalFreePlay)),
            LiveSessionSummaryMetric(id: "comps", title: "Comps", value: money(totalComp)),
        ]
        if !isSlotsSession {
            let stackValue: String = {
                if let stack = liveTrackedStackAmount {
                    return money(stack)
                }
                return "—"
            }()
            metrics.append(LiveSessionSummaryMetric(id: "stack", title: "Stack", value: stackValue))
        }
        return metrics
    }
}

extension TimerActivityAttributes.ContentState {
    var summaryMetrics: [LiveSessionSummaryMetric] {
        LiveSessionSummaryMetricsBuilder.metrics(
            casino: casino,
            game: game,
            startingTierPoints: startingTierPoints,
            totalBuyIn: totalBuyIn,
            totalFreePlay: totalFreePlay,
            totalComp: totalComp,
            liveTrackedStackAmount: liveTrackedStackAmount,
            currencySymbol: currencySymbol,
            isSlotsSession: isSlotsSession
        )
    }
}

enum LiveSessionMetricTrend: Equatable {
    case up
    case down
    case flat

    var symbolName: String {
        switch self {
        case .up: "arrow.up"
        case .down: "arrow.down"
        case .flat: "arrow.left.and.right"
        }
    }

    var color: Color {
        switch self {
        case .up: .green
        case .down: .red
        case .flat: .white
        }
    }

    static func from(current: Int, prior: Int) -> LiveSessionMetricTrend {
        if current > prior { return .up }
        if current < prior { return .down }
        return .flat
    }

    static func fromStack(current: Int?, prior: Int?) -> LiveSessionMetricTrend? {
        switch (current, prior) {
        case let (c?, p?):
            return from(current: c, prior: p)
        case let (c?, nil):
            return c > 0 ? .up : .flat
        case (nil, let p?) where p > 0:
            return .down
        default:
            return nil
        }
    }
}

/// Coin-style chip for stack metric labels (shared by app + widget; mirrors `TierTapChipStackIcon`).
private struct LiveSessionChipStackIcon: View {
    var side: CGFloat
    var currencySymbol: String

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.green.opacity(0.95))
            Circle()
                .stroke(Color.green.opacity(0.7), lineWidth: max(1, side * 0.08))
            Text(currencySymbol)
                .font(.system(size: side * 0.46, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundColor(.black.opacity(0.75))
                .offset(y: -0.2)
        }
        .frame(width: side, height: side)
        .accessibilityLabel("Coin icon")
    }
}

/// SF Symbol / chip icons aligned with live-session quick-action buttons.
private enum LiveSessionSummaryMetricIcons {
    static func sfSymbol(for metricId: String) -> String? {
        switch metricId {
        case "location": "building.columns"
        case "tier": "star.circle"
        case "buyIn": "plus.circle"
        case "freePlay": "ticket.fill"
        case "comps": "gift.fill"
        default: nil
        }
    }

    static func usesChipStack(for metricId: String) -> Bool {
        metricId == "stack"
    }
}

struct LiveSessionSummaryCell: View {
    let title: String
    let value: String
    var metricId: String? = nil
    var compact: Bool = false
    var dense: Bool = false
    var trend: LiveSessionMetricTrend?

    private var titleIconSide: CGFloat {
        dense ? 8 : (compact ? 10 : 12)
    }

    private var metricCurrencySymbol: String {
        let code = UserDefaults(suiteName: "group.com.app.tiertap")?.string(forKey: "ctt_currency_code") ?? "USD"
        switch code.uppercased() {
        case "EUR": return "€"
        case "GBP": return "£"
        case "JPY", "CNY": return "¥"
        case "KRW": return "₩"
        case "INR": return "₹"
        default: return "$"
        }
    }

    private var valueFont: Font {
        if dense {
            return .system(size: 9, weight: .semibold)
        }
        if compact {
            return .system(size: 14, weight: .semibold)
        }
        return .caption.weight(.semibold)
    }

    @ViewBuilder
    private var titleLabel: some View {
        let titleFont = dense ? Font.system(size: 8) : (compact ? Font.system(size: 9) : Font.caption2)
        HStack(spacing: 3) {
            if let metricId {
                metricLabelIcon(for: metricId)
            }
            Text(title)
                .font(titleFont)
                .foregroundColor(.white.opacity(0.65))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    @ViewBuilder
    private func metricLabelIcon(for metricId: String) -> some View {
        if LiveSessionSummaryMetricIcons.usesChipStack(for: metricId) {
            LiveSessionChipStackIcon(side: titleIconSide, currencySymbol: metricCurrencySymbol)
        } else if let symbol = LiveSessionSummaryMetricIcons.sfSymbol(for: metricId) {
            Image(systemName: symbol)
                .font(.system(size: titleIconSide, weight: .semibold))
                .foregroundColor(.white.opacity(0.65))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: dense ? 0 : (compact ? 1 : 2)) {
            titleLabel
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(valueFont)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Spacer(minLength: 0)
                if let trend {
                    Image(systemName: trend.symbolName)
                        .font(valueFont)
                        .foregroundColor(trend.color)
                        .accessibilityLabel(trendAccessibilityLabel(trend))
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: dense ? 24 : (compact ? 28 : 36), alignment: .leading)
        .padding(.horizontal, dense ? 4 : (compact ? 6 : 8))
        .padding(.vertical, dense ? 3 : (compact ? 4 : 6))
        .background(Color.white.opacity(0.08))
        .cornerRadius(dense ? 5 : (compact ? 6 : 8))
    }

    private func trendAccessibilityLabel(_ trend: LiveSessionMetricTrend) -> String {
        switch trend {
        case .up: "Increased"
        case .down: "Decreased"
        case .flat: "Unchanged"
        }
    }
}

struct LiveSessionSummaryGrid: View {
    let metrics: [LiveSessionSummaryMetric]
    var compact: Bool = false
    var columnCount: Int = 2

    private var columns: [GridItem] {
        let spacing: CGFloat = compact ? 6 : 8
        return Array(repeating: GridItem(.flexible(), spacing: spacing), count: max(2, columnCount))
    }

    private var spansFullWidthOnLastRow: Bool {
        columnCount == 2
    }

    var body: some View {
        let dense = compact && columnCount >= 3
        LazyVGrid(columns: columns, spacing: dense ? 4 : (compact ? 6 : 8)) {
            ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                LiveSessionSummaryCell(
                    title: metric.title,
                    value: metric.value,
                    metricId: metric.id,
                    compact: compact,
                    dense: dense
                )
                .gridCellColumns(
                    spansFullWidthOnLastRow && index == metrics.count - 1 ? columnCount : 1
                )
            }
        }
    }
}
