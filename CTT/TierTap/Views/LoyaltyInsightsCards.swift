import SwiftUI

/// Native (non-AI) loyalty analytics cards gated by `TierTapProductEnhancements.isEnabled`.
struct LoyaltyInsightsSection: View {
    let sessions: [Session]
    let currencySymbol: String
    let gradient: LinearGradient
    let dateRangeText: String?
    let locationFilterText: String?

    @State private var isExpanded = true

    private var rated: TierTapProductEnhancements.RatedCaptureSummary {
        TierTapProductEnhancements.ratedCaptureSummary(from: sessions)
    }

    private var rankings: [TierTapProductEnhancements.TierEfficiencyRow] {
        TierTapProductEnhancements.tierEfficiencyRankings(from: sessions)
    }

    private var compROI: TierTapProductEnhancements.CompROISummary {
        TierTapProductEnhancements.compROISummary(from: sessions)
    }

    var body: some View {
        AnalyticsCollapsibleSection(
            title: "Loyalty Insights",
            systemImage: "chart.bar.doc.horizontal",
            isExpanded: $isExpanded
        ) {
            VStack(spacing: 16) {
                RatedCaptureScorecard(
                    summary: rated,
                    currencySymbol: currencySymbol,
                    dateRangeText: dateRangeText,
                    locationFilterText: locationFilterText
                )
                TiersFastestRankingCard(
                    rows: rankings,
                    dateRangeText: dateRangeText,
                    locationFilterText: locationFilterText
                )
                CompROIDashboardCard(
                    summary: compROI,
                    currencySymbol: currencySymbol,
                    dateRangeText: dateRangeText,
                    locationFilterText: locationFilterText
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct RatedCaptureScorecard: View {
    let summary: TierTapProductEnhancements.RatedCaptureSummary
    let currencySymbol: String
    var dateRangeText: String?
    var locationFilterText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header(title: "Rated Capture Scorecard", subtitle: "Host rated bet vs what you actually bet")
            if summary.sessionsWithBothBets == 0 {
                Text("Log avg bet actual and rated on close-out to unlock this report.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.75))
            } else {
                HStack(spacing: 12) {
                    metricBubble(
                        title: "Avg gap",
                        value: signedCurrency(Int(summary.averageGap.rounded())),
                        detail: "rated − actual"
                    )
                    metricBubble(
                        title: "Under-rated",
                        value: String(format: "%.0f%%", summary.underRatedPercent),
                        detail: "\(summary.underRatedCount) of \(summary.sessionsWithBothBets)"
                    )
                }
                if !summary.byProperty.isEmpty {
                    Text("By property")
                        .font(.caption.bold())
                        .foregroundColor(.white.opacity(0.8))
                    ForEach(summary.byProperty.prefix(5), id: \.property) { row in
                        rankingRow(
                            title: row.property,
                            trailing: "\(signedCurrency(Int(row.averageGap.rounded()))) · \(row.count) sess"
                        )
                    }
                }
                if !summary.byGame.isEmpty {
                    Text("By game")
                        .font(.caption.bold())
                        .foregroundColor(.white.opacity(0.8))
                    ForEach(summary.byGame.prefix(5), id: \.game) { row in
                        rankingRow(
                            title: row.game,
                            trailing: "\(signedCurrency(Int(row.averageGap.rounded()))) · \(row.count) sess"
                        )
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.18))
        .cornerRadius(14)
    }

    private func signedCurrency(_ value: Int) -> String {
        value >= 0 ? "+\(currencySymbol)\(value)" : "-\(currencySymbol)\(abs(value))"
    }
}

struct TiersFastestRankingCard: View {
    let rows: [TierTapProductEnhancements.TierEfficiencyRow]
    var dateRangeText: String?
    var locationFilterText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header(title: "Where You Earn Tiers Fastest", subtitle: "Min 2 sessions · ranked by tiers/hour")
            if rows.isEmpty {
                Text("Need at least two completed sessions with tier gains at the same property + game.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.75))
            } else {
                ForEach(Array(rows.prefix(8).enumerated()), id: \.element.id) { index, row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("#\(index + 1)")
                                .font(.caption.bold())
                                .foregroundColor(.green)
                            Text(row.property.isEmpty ? "Unknown" : row.property)
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Spacer()
                            Text(String(format: "%.1f tph", row.tiersPerHour))
                                .font(.subheadline.bold())
                                .foregroundColor(.cyan)
                        }
                        Text("\(row.game)\(row.program.isEmpty ? "" : " · \(row.program)") · \(row.sessionCount) sessions")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.7))
                        if let per100 = row.tiersPerHundredRatedBetHour {
                            Text(String(format: "%.2f tiers / $100 rated-hour", per100))
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.65))
                        }
                    }
                    .padding(.vertical, 4)
                    if index < min(rows.count, 8) - 1 {
                        Divider().background(Color.white.opacity(0.15))
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.18))
        .cornerRadius(14)
    }
}

struct CompROIDashboardCard: View {
    let summary: TierTapProductEnhancements.CompROISummary
    let currencySymbol: String
    var dateRangeText: String?
    var locationFilterText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header(title: "Comp ROI + True EV", subtitle: "Cash net + comps (free play excluded from EV)")
            if summary.sessionCount == 0 {
                Text("Close sessions with cash-out to see EV and comp ROI.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.75))
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    metricBubble(title: "Cash net", value: signed(summary.cashNet), detail: "\(summary.sessionCount) sessions")
                    metricBubble(title: "Comps", value: "\(currencySymbol)\(summary.totalComps)", detail: "logged value")
                    metricBubble(title: "True EV", value: signed(summary.expectedValue), detail: "cash + comps")
                    metricBubble(
                        title: "EV / hour",
                        value: summary.evPerHour.map { signed(Int($0.rounded())) + "/hr" } ?? "—",
                        detail: String(format: "%.1f hrs", summary.hours)
                    )
                }
                if let pct = summary.compsAsPercentOfLoss {
                    Text(String(format: "Comps covered %.0f%% of cash losses", pct))
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
                if summary.freePlay > 0 {
                    Text("Free play logged: \(currencySymbol)\(summary.freePlay) (excluded from EV)")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.65))
                }
                if !summary.byProperty.isEmpty {
                    Text("EV by property")
                        .font(.caption.bold())
                        .foregroundColor(.white.opacity(0.8))
                    ForEach(summary.byProperty.prefix(5), id: \.property) { row in
                        rankingRow(
                            title: row.property,
                            trailing: "\(signed(row.ev)) · \(currencySymbol)\(row.comps) comps"
                        )
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.18))
        .cornerRadius(14)
    }

    private func signed(_ value: Int) -> String {
        value >= 0 ? "+\(currencySymbol)\(value)" : "-\(currencySymbol)\(abs(value))"
    }
}

// MARK: - Shared chrome

private func header(title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Text(title)
            .font(.subheadline.bold())
            .foregroundColor(.white)
        Text(subtitle)
            .font(.caption2)
            .foregroundColor(.white.opacity(0.65))
    }
}

private func metricBubble(title: String, value: String, detail: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(title)
            .font(.caption2)
            .foregroundColor(.white.opacity(0.65))
        Text(value)
            .font(.headline)
            .foregroundColor(.white)
        Text(detail)
            .font(.caption2)
            .foregroundColor(.white.opacity(0.55))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(10)
    .background(Color.black.opacity(0.25))
    .cornerRadius(10)
}

private func rankingRow(title: String, trailing: String) -> some View {
    HStack {
        Text(title)
            .font(.caption)
            .foregroundColor(.white)
            .lineLimit(1)
        Spacer()
        Text(trailing)
            .font(.caption2.monospacedDigit())
            .foregroundColor(.white.opacity(0.75))
    }
}
