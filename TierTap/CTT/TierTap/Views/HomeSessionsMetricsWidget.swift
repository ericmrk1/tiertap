import SwiftUI

private enum HomeSessionsMetricsPage: Int {
    case grid
    case rings
}

/// Swipeable TierTap Sessions widget: P&L activity grid (default) and closing-metrics rings.
struct HomeSessionsMetricsWidget: View {
    let sessions: [Session]
    /// When true, rings animate from 0% up to their current levels.
    var isRevealed: Bool = true
    var onOpenHistory: () -> Void = {}

    @State private var selectedPage = HomeSessionsMetricsPage.grid
    @State private var metricsPeriod: SessionClosingMetricsPeriod = .month

    /// Matches `SessionClosingMetricsRingsView` height so the hero section size stays stable.
    private let contentHeight: CGFloat = 200

    var body: some View {
        TabView(selection: $selectedPage) {
            HomeSessionsCompactGridView(sessions: sessions, onTap: onOpenHistory)
                .tag(HomeSessionsMetricsPage.grid)

            HomeSessionsRingsPage(
                sessions: sessions,
                period: $metricsPeriod,
                isRevealed: isRevealed,
                onOpenHistory: onOpenHistory
            )
            .tag(HomeSessionsMetricsPage.rings)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: contentHeight)
        .overlay(alignment: .bottom) {
            HomeSessionsMetricsPageIndicator(selectedPage: selectedPage.rawValue, pageCount: 2)
                .padding(.bottom, 2)
        }
    }
}

private struct HomeSessionsRingsPage: View {
    let sessions: [Session]
    @Binding var period: SessionClosingMetricsPeriod
    var isRevealed: Bool
    var onOpenHistory: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Picker("Period", selection: $period) {
                ForEach(SessionClosingMetricsPeriod.allCases) { item in
                    Text(item.label).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .colorScheme(.dark)

            SessionClosingMetricsRingsView(
                sessions: sessions,
                period: $period,
                isRevealed: isRevealed,
                onRingTap: onOpenHistory
            )
        }
        .padding(.bottom, 10)
    }
}

private struct HomeSessionsMetricsPageIndicator: View {
    let selectedPage: Int
    let pageCount: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<pageCount, id: \.self) { index in
                Circle()
                    .fill(index == selectedPage ? Color.white : Color.white.opacity(0.35))
                    .frame(width: 6, height: 6)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(selectedPage + 1) of \(pageCount)")
    }
}

/// Compact profit/loss grid for the home hero; tap opens full history.
private struct HomeSessionsCompactGridView: View {
    let sessions: [Session]
    var onTap: () -> Void = {}

    private let metricMode: HistoryGridMetricMode = .profitLoss
    private let calendar = Calendar.current

    private var aggregatesByDay: [Date: HistoryDayAggregate] {
        HistoryActivityGridEngine.aggregates(sessions: sessions, metricMode: metricMode, calendar: calendar)
    }

    var body: some View {
        GeometryReader { geo in
            let reservedBottom: CGFloat = 10
            let availableHeight = geo.size.height - reservedBottom
            let layout = HistoryActivityGridEngine.layout(
                for: geo.size.width,
                periodOffset: 0,
                calendar: calendar
            )
            let naturalHeight = HistoryActivityGridEngine.gridContentHeight(cellSize: layout.cellSize)
            let scale = min(
                geo.size.width / max(layout.totalWidth, 1),
                availableHeight / max(naturalHeight, 1)
            )

            Group {
                if layout.bands.isEmpty {
                    Text("No session data yet.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                } else {
                    HistoryActivityGridBandsView(
                        layout: layout,
                        aggregates: aggregatesByDay,
                        calendar: calendar
                    )
                    .scaleEffect(scale, anchor: .center)
                }
            }
            .frame(width: geo.size.width, height: availableHeight)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Profit and loss session grid")
            .accessibilityHint("Opens session history")
            .accessibilityAddTraits(.isButton)
        }
    }
}
