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

/// Horizontally scrollable recent-session tiles for the home hero.
private struct HomeRecentSessionsStripView: View {
    var onSessionTap: (Session) -> Void = { _ in }

    @EnvironmentObject private var store: SessionStore
    @State private var autoScrollEnabled = false

    private let maxTiles = 20
    private let cardTileWidth: CGFloat = 148
    private let tickerTileWidth: CGFloat = 168
    private let tileSpacing: CGFloat = 10
    private let carouselHeight: CGFloat = 148

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
                String(session.winLoss ?? 0),
                String(session.tierPointsEarned ?? 0),
                session.effectiveTierPointsVerification.rawValue
            ].joined(separator: ";")
        }.joined(separator: "|")
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
                        sessions: recentSessions,
                        sessionsRevision: sessionsRevision,
                        tileWidth: tickerTileWidth,
                        tileHeight: carouselHeight,
                        tileSpacing: tileSpacing,
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
            HStack(spacing: tileSpacing) {
                ForEach(recentSessions) { session in
                    HomeRecentSessionTile(sessionID: session.id, style: .card)
                        .frame(width: cardTileWidth, height: carouselHeight)
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

/// Auto-scrolling ticker — one tile per session (no duplicated strip) so deleted sessions cannot linger off-screen.
private struct HomeSessionTickerStrip: View {
    let sessions: [Session]
    let sessionsRevision: String
    let tileWidth: CGFloat
    let tileHeight: CGFloat
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

    private var loopWidth: CGFloat {
        let count = CGFloat(liveSessions.count)
        guard count > 0 else { return 0 }
        return count * tileWidth + max(0, count - 1) * tileSpacing
    }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: tileSpacing) {
                ForEach(liveSessions) { session in
                    HomeRecentSessionTile(sessionID: session.id, style: .ticker)
                        .frame(width: tileWidth, height: geo.size.height)
                        .id("\(session.id.uuidString)-\(sessionsRevision)")
                        .onTapGesture {
                            if let current = store.sessions.first(where: { $0.id == session.id }) {
                                onSessionTap(current)
                            }
                        }
                }
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
            if scrollOffset <= -width {
                scrollOffset = 0
            }
        }
        .onChange(of: sessionsRevision) { _ in
            scrollOffset = 0
        }
        .onAppear {
            scrollOffset = 0
        }
    }
}

private enum HomeSessionTileStyle {
    case card
    case ticker
}

/// Pulsing emphasis for ticker metrics — peaks briefly like a stock price flash.
private struct HomeTickerPopMetric: View {
    let text: String
    let color: Color
    let animationSeed: Double
    let windowStart: Double

    private let cycleDuration = 5.2
    private let windowWidth = 0.14

    private func emphasis(at phase: Double) -> Double {
        let local = (phase - windowStart + 1).truncatingRemainder(dividingBy: 1)
        guard local < windowWidth else { return 0 }
        let center = windowWidth / 2
        let distance = abs(local - center) / max(center, 0.001)
        return max(0, 1 - distance)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate + animationSeed
            let phase = elapsed.truncatingRemainder(dividingBy: cycleDuration) / cycleDuration
            let pop = emphasis(at: phase)

            Text(text)
                .font(.system(.subheadline, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .scaleEffect(1 + pop * 0.24, anchor: .leading)
                .opacity(0.72 + pop * 0.28)
                .shadow(color: color.opacity(pop * 0.55), radius: pop * 8, y: pop * 2)
        }
    }
}

private struct HomeRecentSessionTile: View {
    let sessionID: UUID
    var style: HomeSessionTileStyle = .card
    var animationSeed: Double = 0

    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var settingsStore: SettingsStore

    private var session: Session? {
        store.sessions.first(where: { $0.id == sessionID })
    }

    private var verificationLabel: String {
        guard let session else { return "" }
        return session.effectiveTierPointsVerification == .verified ? "Verified" : "Unverified"
    }

    private var verificationForeground: Color {
        guard let session else { return .white.opacity(0.45) }
        return session.effectiveTierPointsVerification == .verified
            ? Color(red: 0.28, green: 0.92, blue: 0.48)
            : Color.yellow.opacity(0.95)
    }

    private var verificationBackground: Color {
        guard let session else { return .clear }
        return session.effectiveTierPointsVerification == .verified
            ? Color(red: 0.28, green: 0.92, blue: 0.48).opacity(0.18)
            : Color.yellow.opacity(0.18)
    }

    private var winLossText: String? {
        guard let session, let wl = session.winLoss else { return nil }
        return wl >= 0
            ? "+\(settingsStore.currencySymbol)\(wl.formatted(.number.grouping(.automatic)))"
            : "-\(settingsStore.currencySymbol)\(abs(wl).formatted(.number.grouping(.automatic)))"
    }

    private var winLossColor: Color {
        guard let session, let wl = session.winLoss else { return .white.opacity(0.45) }
        return wl >= 0 ? .green : .red
    }

    private var tierPointsText: String? {
        guard let session, let earned = session.tierPointsEarned else { return nil }
        return "\(earned >= 0 ? "+" : "")\(earned.formatted(.number.grouping(.automatic))) pts"
    }

    private var tierPointsColor: Color {
        guard let session, let earned = session.tierPointsEarned else { return .white.opacity(0.45) }
        return earned >= 0 ? .green : .orange
    }

    private var sessionStartedToday: Bool {
        guard let session else { return false }
        return Calendar.current.isDateInToday(session.startTime)
    }

    @ViewBuilder
    private var sessionStartLabel: some View {
        if let session {
            if sessionStartedToday {
                Text(session.startTime, style: .time)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.55))
            } else {
                Text(session.startTime, style: .date)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.55))
            }
        }
    }

    /// Location, game, and time/date stacked so each line can use the full tile width.
    @ViewBuilder
    private var sessionDetailsColumn: some View {
        if let session {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.casino.isEmpty ? "Session" : session.casino)
                    .font(style == .ticker ? .caption.weight(.bold) : .subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(session.game.isEmpty ? "—" : session.game)
                    .font(.caption)
                    .foregroundColor(.white.opacity(style == .ticker ? 0.78 : 0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                sessionStartLabel
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var body: some View {
        Group {
            if let session {
                Group {
                    switch style {
                    case .card:
                        cardBody
                    case .ticker:
                        tickerBody
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(session.casino), \(session.game), \(verificationLabel)")
            }
        }
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            sessionDetailsColumn

            Spacer(minLength: 0)

            HStack(alignment: .firstTextBaseline) {
                if let winLossText {
                    Text(winLossText)
                        .font(.subheadline.bold())
                        .foregroundColor(winLossColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else {
                    Text("—")
                        .font(.subheadline.bold())
                        .foregroundColor(.white.opacity(0.45))
                }
                Spacer(minLength: 0)
                if let tierPointsText {
                    Text(tierPointsText)
                        .font(.caption2.bold())
                        .foregroundColor(tierPointsColor)
                        .lineLimit(1)
                }
            }

            verificationBadge
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
    }

    private var tickerBody: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                sessionDetailsColumn

                HStack(spacing: 10) {
                    if let winLossText {
                        HomeTickerPopMetric(
                            text: winLossText,
                            color: winLossColor,
                            animationSeed: animationSeed,
                            windowStart: 0.04
                        )
                    }

                    if let tierPointsText {
                        HomeTickerPopMetric(
                            text: tierPointsText,
                            color: tierPointsColor,
                            animationSeed: animationSeed,
                            windowStart: 0.2
                        )
                    }
                }

                if let session, session.hoursPlayed > 0 {
                    HomeTickerPopMetric(
                        text: String(format: "%.1f hr", session.hoursPlayed),
                        color: .white.opacity(0.82),
                        animationSeed: animationSeed,
                        windowStart: 0.36
                    )
                }

                verificationBadge
            }
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .padding(.vertical, 10)

            Rectangle()
                .fill(Color.white.opacity(0.16))
                .frame(width: 1)
                .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        }
    }

    private var verificationBadge: some View {
        Text(verificationLabel)
            .font(.caption2.bold())
            .foregroundColor(verificationForeground)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(verificationBackground)
            .cornerRadius(4)
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
