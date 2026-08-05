import SwiftUI

/// Tap to enable/disable auto-scrolling home tickers (sessions + tier goals).
struct HomeTickerAutoScrollButton: View {
    @Binding var isEnabled: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isEnabled.toggle()
            }
        } label: {
            ZStack {
                Image(systemName: "arrow.left.and.right")                    .foregroundColor(isEnabled ? .white : .white.opacity(0.45))

                if !isEnabled {
                    Rectangle()
                        .fill(Color.white.opacity(0.8))
                        .frame(width: 1.5, height: 16)
                        .rotationEffect(.degrees(-38))
                }
            }
            .frame(minWidth: 36, minHeight: 18)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Auto-scroll tickers")
        .accessibilityValue(isEnabled ? "Scroll on" : "Scroll off")
        .accessibilityHint("Toggles scrolling for recent sessions and tier goals.")
    }
}

private enum HomeSessionsMetricsPage: Int {
    case recent
    case grid
}

/// Swipeable TierTap Sessions widget: recent session tiles (default) and P&L activity grid.
struct HomeSessionsMetricsWidget: View {
    let sessions: [Session]
    var autoScrollEnabled: Bool = true
    var onOpenHistory: () -> Void = {}
    var onSessionTap: (Session) -> Void = { _ in }

    @State private var selectedPage = HomeSessionsMetricsPage.recent

    /// Page-specific heights — keep each page tight to its content (no tall empty chrome).
    private var contentHeight: CGFloat {
        switch selectedPage {
        case .recent: return 112
        case .grid: return 124
        }
    }

    var body: some View {
        TabView(selection: $selectedPage) {
            HomeRecentSessionsStripView(
                autoScrollEnabled: autoScrollEnabled,
                onSessionTap: onSessionTap
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .tag(HomeSessionsMetricsPage.recent)

            HomeSessionsCompactGridView(sessions: sessions, onTap: onOpenHistory)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .tag(HomeSessionsMetricsPage.grid)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: contentHeight)
        .animation(.easeInOut(duration: 0.22), value: selectedPage)
        .overlay(alignment: .bottom) {
            HomeSessionsMetricsPageIndicator(selectedPage: selectedPage.rawValue, pageCount: 2)
                .padding(.bottom, 1)
        }
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

/// Horizontally scrollable recent-session tiles for the home hero.
private struct HomeRecentSessionsStripView: View {
    var autoScrollEnabled: Bool = true
    var onSessionTap: (Session) -> Void = { _ in }

    @EnvironmentObject private var store: SessionStore

    private let maxTiles = 20
    /// Half the old two-row carousel height — square tiles.
    private let tileSize: CGFloat = 74
    private let tileSpacing: CGFloat = 8

    private var recentSessions: [Session] {
        store.sessions
            .sorted { $0.startTime > $1.startTime }
            .prefix(maxTiles)
            .map { $0 }
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

    var body: some View {
        Group {
            if recentSessions.isEmpty {
                Text("No sessions yet.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if autoScrollEnabled {
                HomeSessionTickerStrip(
                    sessions: recentSessions,
                    sessionsRevision: sessionsRevision,
                    tileSize: tileSize,
                    tileSpacing: tileSpacing,
                    onSessionTap: onSessionTap
                )
                .id(sessionsRevision)
            } else {
                manualSessionsScroll
            }
        }
        .frame(height: tileSize)
        .padding(.top, 2)
        .padding(.bottom, 14)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recent sessions")
        .accessibilityHint(autoScrollEnabled ? "Session ticker is scrolling. Opens session details." : "Swipe for more sessions. Opens session details.")
    }

    private var manualSessionsScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: tileSpacing) {
                ForEach(recentSessions) { session in
                    HomeRecentSessionTile(sessionID: session.id)
                        .frame(width: tileSize, height: tileSize)
                        .onTapGesture {
                            if let current = store.sessions.first(where: { $0.id == session.id }) {
                                onSessionTap(current)
                            }
                        }
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

/// Auto-scrolling ticker with a duplicated strip so the first tile follows the last without a blank gap.
private struct HomeSessionTickerStrip: View {
    let sessions: [Session]
    let sessionsRevision: String
    let tileSize: CGFloat
    let tileSpacing: CGFloat
    var onSessionTap: (Session) -> Void = { _ in }

    @EnvironmentObject private var store: SessionStore
    @State private var scrollOffset: CGFloat = 0

    private let pointsPerSecond: CGFloat = 22
    private let tickerTimer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    private var liveSessions: [Session] {
        let validIDs = Set(store.sessions.map(\.id))
        return sessions.filter { validIDs.contains($0.id) }
    }

    /// Width of one copy of the strip (no trailing gap).
    private var stripWidth: CGFloat {
        let count = CGFloat(liveSessions.count)
        guard count > 0 else { return 0 }
        return count * tileSize + max(0, count - 1) * tileSpacing
    }

    /// Distance to shift before the duplicated strip lines up with the first (includes inter-copy spacing).
    private var loopWidth: CGFloat {
        guard stripWidth > 0 else { return 0 }
        return stripWidth + tileSpacing
    }

    var body: some View {
        GeometryReader { _ in
            HStack(spacing: tileSpacing) {
                tickerRow(copyIndex: 0)
                // Second copy makes the loop seamless: first tile follows the last immediately.
                tickerRow(copyIndex: 1)
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
            guard width > 0, liveSessions.count > 1 else { return }
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

    private func tickerRow(copyIndex: Int) -> some View {
        HStack(spacing: tileSpacing) {
            ForEach(liveSessions) { session in
                HomeRecentSessionTile(sessionID: session.id)
                    .frame(width: tileSize, height: tileSize)
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
            let reservedBottom: CGFloat = 12
            let availableHeight = max(geo.size.height - reservedBottom, 1)
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
                    .scaleEffect(scale, anchor: .top)
                }
            }
            .frame(width: geo.size.width, height: availableHeight, alignment: .top)
            .padding(.top, 2)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Profit and loss session grid")
            .accessibilityHint("Opens session history")
            .accessibilityAddTraits(.isButton)
        }
    }
}
