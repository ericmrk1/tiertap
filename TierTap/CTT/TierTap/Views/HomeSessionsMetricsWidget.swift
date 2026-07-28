import SwiftUI

private enum HomeSessionsMetricsPage: Int {
    case recent
    case grid
    case rings
}

/// Swipeable TierTap Sessions widget: recent session tiles (default), P&L activity grid, and closing-metrics rings.
struct HomeSessionsMetricsWidget: View {
    let sessions: [Session]
    /// When true, rings animate from 0% up to their current levels.
    var isRevealed: Bool = true
    var onOpenHistory: () -> Void = {}
    var onSessionTap: (Session) -> Void = { _ in }

    @State private var selectedPage = HomeSessionsMetricsPage.recent
    @State private var metricsPeriod: SessionClosingMetricsPeriod = .month

    /// Matches `SessionClosingMetricsRingsView` height so the hero section size stays stable.
    private let contentHeight: CGFloat = 200

    var body: some View {
        TabView(selection: $selectedPage) {
            HomeRecentSessionsStripView(onSessionTap: onSessionTap)
                .tag(HomeSessionsMetricsPage.recent)

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
            HomeSessionsMetricsPageIndicator(selectedPage: selectedPage.rawValue, pageCount: 3)
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

/// Horizontally scrollable recent-session tiles for the home hero (two compact rows).
private struct HomeRecentSessionsStripView: View {
    var onSessionTap: (Session) -> Void = { _ in }

    @EnvironmentObject private var store: SessionStore
    @State private var autoScrollEnabled = false

    private let maxTiles = 20
    private let cardTileWidth: CGFloat = 74
    private let tickerTileWidth: CGFloat = 84
    private let tileSpacing: CGFloat = 8
    private let rowSpacing: CGFloat = 8
    private let carouselHeight: CGFloat = 148

    private var recentSessions: [Session] {
        store.sessions
            .sorted { $0.startTime > $1.startTime }
            .prefix(maxTiles)
            .map { $0 }
    }

    /// Interleave into two rows so both fill evenly while scrolling together.
    private var sessionRows: (top: [Session], bottom: [Session]) {
        var top: [Session] = []
        var bottom: [Session] = []
        for (index, session) in recentSessions.enumerated() {
            if index.isMultiple(of: 2) {
                top.append(session)
            } else {
                bottom.append(session)
            }
        }
        return (top, bottom)
    }

    /// Changes when sessions are added, deleted, or edited so the ticker rebuilds instead of showing stale tiles.
    private var sessionsRevision: String {
        recentSessions.map { session in
            [
                session.id.uuidString,
                String(session.startTime.timeIntervalSince1970),
                session.casino,
                session.game,
                String(session.winLoss ?? 0)
            ].joined(separator: ";")
        }.joined(separator: "|")
    }

    private var tileHeight: CGFloat {
        (carouselHeight - rowSpacing) / 2
    }

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if recentSessions.isEmpty {
                    Text("No sessions yet.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if autoScrollEnabled {
                    HomeSessionTickerStrip(
                        topSessions: sessionRows.top,
                        bottomSessions: sessionRows.bottom,
                        sessionsRevision: sessionsRevision,
                        tileWidth: tickerTileWidth,
                        tileHeight: tileHeight,
                        tileSpacing: tileSpacing,
                        rowSpacing: rowSpacing,
                        onSessionTap: onSessionTap
                    )
                    .id(sessionsRevision)
                } else {
                    manualSessionsScroll
                }
            }
            .frame(height: carouselHeight)

            if !recentSessions.isEmpty {
                Toggle(isOn: $autoScrollEnabled) {
                    Text("")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.85))
                }
                .toggleStyle(SwitchToggleStyle(tint: .green))
                .scaleEffect(0.8, anchor: .trailing)
                .frame(maxWidth: .infinity, minHeight: 16, maxHeight: 16, alignment: .trailing)
                .padding(.horizontal, 2)
            }
        }
        .padding(.bottom, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recent sessions")
        .accessibilityHint(autoScrollEnabled ? "Session ticker is scrolling. Opens session details." : "Swipe for more sessions. Opens session details.")
    }

    private var manualSessionsScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: rowSpacing) {
                sessionRow(sessionRows.top)
                sessionRow(sessionRows.bottom)
            }
            .padding(.horizontal, 2)
        }
    }

    private func sessionRow(_ sessions: [Session]) -> some View {
        HStack(spacing: tileSpacing) {
            ForEach(sessions) { session in
                HomeRecentSessionTile(sessionID: session.id)
                    .frame(width: cardTileWidth, height: tileHeight)
                    .onTapGesture {
                        if let current = store.sessions.first(where: { $0.id == session.id }) {
                            onSessionTap(current)
                        }
                    }
            }
        }
    }
}

/// Auto-scrolling two-row ticker with a duplicated strip so the first column follows the last without a blank gap.
private struct HomeSessionTickerStrip: View {
    let topSessions: [Session]
    let bottomSessions: [Session]
    let sessionsRevision: String
    let tileWidth: CGFloat
    let tileHeight: CGFloat
    let tileSpacing: CGFloat
    let rowSpacing: CGFloat
    var onSessionTap: (Session) -> Void = { _ in }

    @EnvironmentObject private var store: SessionStore
    @State private var scrollOffset: CGFloat = 0

    private let pointsPerSecond: CGFloat = 22
    private let tickerTimer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    private var liveTop: [Session] {
        let validIDs = Set(store.sessions.map(\.id))
        return topSessions.filter { validIDs.contains($0.id) }
    }

    private var liveBottom: [Session] {
        let validIDs = Set(store.sessions.map(\.id))
        return bottomSessions.filter { validIDs.contains($0.id) }
    }

    private var liveSessionCount: Int {
        liveTop.count + liveBottom.count
    }

    /// Width of one copy of the two-row strip (no trailing gap).
    private var stripWidth: CGFloat {
        let maxCount = CGFloat(max(liveTop.count, liveBottom.count))
        guard maxCount > 0 else { return 0 }
        return maxCount * tileWidth + max(0, maxCount - 1) * tileSpacing
    }

    /// Distance to shift before the duplicated strip lines up with the first (includes inter-copy spacing).
    private var loopWidth: CGFloat {
        guard stripWidth > 0 else { return 0 }
        return stripWidth + tileSpacing
    }

    var body: some View {
        GeometryReader { _ in
            HStack(alignment: .top, spacing: tileSpacing) {
                tickerStrip(copyIndex: 0)
                // Second copy makes the loop seamless: first column follows the last immediately.
                tickerStrip(copyIndex: 1)
            }
            .offset(x: scrollOffset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .mask {
            HStack(spacing: 0) {
                LinearGradient(
                    colors: [.clear, .black],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 18)
                Rectangle().fill(Color.black)
                LinearGradient(
                    colors: [.black, .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 18)
            }
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.white.opacity(0.14))
                .frame(width: 1)
                .padding(.vertical, 10)
        }
        .clipped()
        .onReceive(tickerTimer) { _ in
            let width = loopWidth
            guard width > 0, liveSessionCount > 1 else { return }
            scrollOffset -= pointsPerSecond / 60.0
            // Jump by exactly one strip so the duplicate lands on the original with no blank gap.
            while scrollOffset <= -width {
                scrollOffset += width
            }
        }
        .onChange(of: sessionsRevision) { _ in
            scrollOffset = 0
        }
        .onAppear {
            scrollOffset = 0
        }
    }

    private func tickerStrip(copyIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            tickerRow(liveTop, copyIndex: copyIndex)
            tickerRow(liveBottom, copyIndex: copyIndex)
        }
    }

    private func tickerRow(_ sessions: [Session], copyIndex: Int) -> some View {
        HStack(spacing: tileSpacing) {
            ForEach(sessions) { session in
                HomeRecentSessionTile(sessionID: session.id)
                    .frame(width: tileWidth, height: tileHeight)
                    .id("\(copyIndex)-\(session.id.uuidString)-\(sessionsRevision)")
                    .onTapGesture {
                        if let current = store.sessions.first(where: { $0.id == session.id }) {
                            onSessionTap(current)
                        }
                    }
            }
        }
    }
}

private struct HomeRecentSessionTile: View {
    let sessionID: UUID

    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var settingsStore: SettingsStore

    private var session: Session? {
        store.sessions.first(where: { $0.id == sessionID })
    }

    private var winLossText: String? {
        guard let session, let wl = session.winLoss else { return nil }
        return wl >= 0
            ? "+\(settingsStore.currencySymbol)\(wl.formatted(.number.grouping(.automatic)))"
            : "-\(settingsStore.currencySymbol)\(abs(wl).formatted(.number.grouping(.automatic)))"
    }

    private var tileTint: Color {
        guard let session, let wl = session.winLoss else {
            return Color.white.opacity(0.08)
        }
        return wl >= 0
            ? Color.green.opacity(0.28)
            : Color.red.opacity(0.28)
    }

    private var tileStroke: Color {
        guard let session, let wl = session.winLoss else {
            return Color.white.opacity(0.12)
        }
        return wl >= 0
            ? Color.green.opacity(0.45)
            : Color.red.opacity(0.45)
    }

    private var sessionStartedToday: Bool {
        guard let session else { return false }
        return Calendar.current.isDateInToday(session.startTime)
    }

    var body: some View {
        Group {
            if let session {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.game.isEmpty ? "—" : session.game)
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text(session.casino.isEmpty ? "Session" : session.casino)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.72))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    if sessionStartedToday {
                        Text(session.startTime, style: .time)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.55))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    } else {
                        Text(session.startTime, style: .date)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.55))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }

                    Spacer(minLength: 0)

                    if let winLossText {
                        Text(winLossText)
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                    } else {
                        Text("—")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.white.opacity(0.45))
                    }
                }
                .padding(7)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(tileTint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(tileStroke, lineWidth: 1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(session.game), \(session.casino), \(winLossText ?? "no result")")
            }
        }
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
