import SwiftUI
import UIKit

struct AnalyticsShareSelection {
    let includeVenn: Bool
    let includeWinLoss: Bool
    let includeTierProgress: Bool
    let includeGameBreakdown: Bool
}

struct AnalyticsView: View {
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    
    @State private var selectedGraphKind: GraphKind = .betCaptureDiff
    @State private var isShareSelectionPresented: Bool = false
    @State private var isShareSheetPresented: Bool = false
    @State private var analyticsFromDate: Date? = nil
    @State private var analyticsToDate: Date? = nil

#if os(iOS)
    @State private var shareImages: [UIImage] = []
    @State private var shareURLs: [URL] = []
    @State private var pendingShareSelection: AnalyticsShareSelection?
#endif

    private var allClosedSessions: [Session] {
        sessionStore.sessions.filter { $0.winLoss != nil }
    }

    private var closedSessions: [Session] {
        var base = allClosedSessions
        if let filter = settingsStore.selectedLocationFilter, !filter.isEmpty {
            base = base.filter { $0.casino == filter }
        }
        let cal = Calendar.current
        if let from = analyticsFromDate {
            let startOfFrom = cal.startOfDay(for: from)
            base = base.filter { $0.startTime >= startOfFrom }
        }
        if let to = analyticsToDate {
            let endOfTo = cal.date(bySettingHour: 23, minute: 59, second: 59, of: cal.startOfDay(for: to)) ?? cal.startOfDay(for: to)
            base = base.filter { $0.startTime <= endOfTo }
        }
        return base
    }

    private var availableCasinos: [String] {
        Array(Set(allClosedSessions.map { $0.casino })).sorted()
    }

    private var winningSessions: [Session] {
        closedSessions.filter { ($0.winLoss ?? 0) > 0 }
    }

    private var losingSessions: [Session] {
        closedSessions.filter { ($0.winLoss ?? 0) < 0 }
    }

    private var breakEvenSessions: [Session] {
        closedSessions.filter { ($0.winLoss ?? 0) == 0 }
    }

    private var sessionsWithTierGain: [Session] {
        closedSessions.filter { ($0.tierPointsEarned ?? 0) > 0 }
    }

    private var vennIntersectionCount: Int {
        closedSessions.filter { ($0.winLoss ?? 0) > 0 && ($0.tierPointsEarned ?? 0) > 0 }.count
    }

    private var totalProfit: Int {
        closedSessions.compactMap { $0.winLoss }.filter { $0 > 0 }.reduce(0, +)
    }

    private var totalLoss: Int {
        abs(closedSessions.compactMap { $0.winLoss }.filter { $0 < 0 }.reduce(0, +))
    }
    
    private var betCaptureDiffByDate: [(date: Date, diff: Int)] {
        let withBothBets: [(date: Date, diff: Int)] = closedSessions.compactMap { session -> (date: Date, diff: Int)? in
            guard let actual = session.avgBetActual,
                  let rated = session.avgBetRated else { return nil }
            // Positive diff means rated (captured) > actual, which is good
            return (date: session.startTime, diff: rated - actual)
        }
        return withBothBets.sorted(by: { lhs, rhs in
            lhs.date < rhs.date
        })
    }
    
    private var betCaptureGoodBadCounts: (good: Int, bad: Int) {
        let diffs = betCaptureDiffByDate.map { $0.diff }
        let good = diffs.filter { $0 >= 0 }.count
        let bad = diffs.filter { $0 < 0 }.count
        return (good, bad)
    }

    private var cumulativePointsByDate: [(date: Date, total: Int)] {
        let sorted = closedSessions.sorted { $0.startTime < $1.startTime }
        var running = 0
        return sorted.map { session in
            running += session.tierPointsEarned ?? 0
            return (date: session.startTime, total: running)
        }
    }

    private var analyticsDateRangeText: String? {
        guard !closedSessions.isEmpty,
              let first = closedSessions.map(\.startTime).min(),
              let last = closedSessions.map(\.startTime).max() else { return nil }
        let df = DateFormatter()
        df.dateStyle = .medium
        return "\(df.string(from: first)) – \(df.string(from: last))"
    }

    private var analyticsLocationFilterText: String? {
        guard let filter = settingsStore.selectedLocationFilter, !filter.isEmpty else { return nil }
        return "Location: \(filter)"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                if closedSessions.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            headerSummary
                            locationFilterBar
                            dateFilterBar
                            graphTypePicker
                            selectedGraph
                            secondaryGraphs
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Analytics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !closedSessions.isEmpty {
                        Button {
                            isShareSelectionPresented = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .imageScale(.medium)
                        }
                        .foregroundColor(.white)
                    }
                }
            }
        }
        .sheet(isPresented: $isShareSelectionPresented) {
            AnalyticsShareSelectionSheet(
                closedSessions: closedSessions,
                gradient: settingsStore.primaryGradient,
                onShare: { selection in
                    pendingShareSelection = selection
                }
            )
            .environmentObject(settingsStore)
        }
#if os(iOS)
        .onChange(of: isShareSelectionPresented) { newValue in
            if !newValue, let selection = pendingShareSelection {
                shareImages = buildAnalyticsShareImages(
                    selection: selection,
                    closedSessions: closedSessions,
                    gradient: settingsStore.primaryGradient,
                    currencySymbol: settingsStore.currencySymbol,
                    locationFilterText: analyticsLocationFilterText
                )
                pendingShareSelection = nil

                if !shareImages.isEmpty {
                    shareURLs = writeShareImagesToTempFiles(shareImages)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        isShareSheetPresented = true
                    }
                }
            }
        }
        .sheet(isPresented: $isShareSheetPresented) {
            ShareSheet(items: shareURLs)
        }
        .onChange(of: isShareSheetPresented) { newValue in
            if !newValue {
                for url in shareURLs { try? FileManager.default.removeItem(at: url) }
                shareURLs = []
                shareImages = []
            }
        }
#endif
    }

    private var locationFilterBar: some View {
        Group {
            if !availableCasinos.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Filter by location")
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                        Spacer()
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Button {
                                settingsStore.selectedLocationFilter = nil
                            } label: {
                                Text("All")
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(settingsStore.selectedLocationFilter == nil || settingsStore.selectedLocationFilter?.isEmpty == true ? Color.green : Color(.systemGray6).opacity(0.25))
                                    .foregroundColor(settingsStore.selectedLocationFilter == nil || settingsStore.selectedLocationFilter?.isEmpty == true ? .black : .white)
                                    .cornerRadius(8)
                            }
                            ForEach(availableCasinos, id: \.self) { casino in
                                Button {
                                    settingsStore.selectedLocationFilter = casino
                                } label: {
                                    Text(casino)
                                        .font(.caption)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(settingsStore.selectedLocationFilter == casino ? Color.green : Color(.systemGray6).opacity(0.25))
                                        .foregroundColor(settingsStore.selectedLocationFilter == casino ? .black : .white)
                                        .cornerRadius(8)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var dateFilterBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Date range")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                Spacer()
            }
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("From")
                        .font(.caption)
                        .foregroundColor(.gray)
                    HStack(spacing: 8) {
                        DatePicker("", selection: Binding(
                            get: { analyticsFromDate ?? Calendar.current.date(from: DateComponents(year: Calendar.current.component(.year, from: Date()), month: 1, day: 1)) ?? Date() },
                            set: { analyticsFromDate = $0 }
                        ), displayedComponents: .date)
                            .labelsHidden()
                            .colorScheme(.dark)
                        Button(analyticsFromDate == nil ? "All" : "Clear") {
                            analyticsFromDate = nil
                        }
                        .font(.caption)
                        .foregroundColor(.green)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    Text("To")
                        .font(.caption)
                        .foregroundColor(.gray)
                    HStack(spacing: 8) {
                        DatePicker("", selection: Binding(
                            get: { analyticsToDate ?? Date() },
                            set: { analyticsToDate = $0 }
                        ), displayedComponents: .date)
                            .labelsHidden()
                            .colorScheme(.dark)
                        Button(analyticsToDate == nil ? "All" : "Clear") {
                            analyticsToDate = nil
                        }
                        .font(.caption)
                        .foregroundColor(.green)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(Color(.systemGray6).opacity(0.15))
            .cornerRadius(12)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 52))
                .foregroundStyle(settingsStore.primaryGradient)
            Text("No Analytics Yet")
                .font(.title3)
                .foregroundColor(.gray)
            Text("Play and complete a few sessions to unlock win/loss, tier point, and pace-of-play analytics.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(.gray.opacity(0.7))
                .padding(.horizontal)
        }
    }

    private var headerSummary: some View {
        let total = closedSessions.count
        let wins = winningSessions.count
        let losses = losingSessions.count
        let breakeven = breakEvenSessions.count
        let winRate = total > 0 ? Double(wins) / Double(total) : 0

        return VStack(spacing: 12) {
            HStack {
                Text("Session Overview")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(total) sessions")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    if let filter = settingsStore.selectedLocationFilter, !filter.isEmpty {
                        Text(filter)
                            .font(.caption2)
                            .foregroundColor(.gray)
                    } else {
                        Text("All locations")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
            }

            HStack(spacing: 12) {
                MetricPill(title: "Win rate", value: String(format: "%.0f%%", winRate * 100), color: .green)
                MetricPill(title: "Profit", value: "\(settingsStore.currencySymbol)\(totalProfit)", color: .green)
                MetricPill(title: "Loss", value: "-\(settingsStore.currencySymbol)\(totalLoss)", color: .red)
            }

            HStack(spacing: 12) {
                MetricPill(title: "Wins", value: "\(wins)", color: .green)
                MetricPill(title: "Losses", value: "\(losses)", color: .red)
                MetricPill(title: "Even", value: "\(breakeven)", color: .gray)
            }
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.15))
        .cornerRadius(16)
    }

    private var graphTypePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Graph style")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                Spacer()
            }
            Picker("Graph style", selection: $selectedGraphKind) {
                ForEach(GraphKind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var selectedGraph: some View {
        Group {
            switch selectedGraphKind {
            case .betCaptureDiff:
                BetCaptureDiffLineChartCard(
                    series: betCaptureDiffByDate,
                    goodBadCounts: betCaptureGoodBadCounts,
                    gradient: settingsStore.primaryGradient,
                    dateRangeText: analyticsDateRangeText,
                    locationFilterText: analyticsLocationFilterText
                )
            case .venn:
                VennDiagramCard(
                    leftLabel: "Winning sessions",
                    rightLabel: "Tier gain",
                    leftCount: winningSessions.count,
                    rightCount: sessionsWithTierGain.count,
                    intersectionCount: vennIntersectionCount,
                    total: closedSessions.count,
                    gradient: settingsStore.primaryGradient,
                    dateRangeText: analyticsDateRangeText,
                    locationFilterText: analyticsLocationFilterText
                )
            case .winLossBars:
                WinLossBarChartCard(
                    totalProfit: totalProfit,
                    totalLoss: totalLoss,
                    totalSessions: closedSessions.count,
                    gradient: settingsStore.primaryGradient,
                    currencySymbol: settingsStore.currencySymbol,
                    dateRangeText: analyticsDateRangeText,
                    locationFilterText: analyticsLocationFilterText
                )
            case .tierProgress:
                TierProgressLineChartCard(
                    pointsByDate: cumulativePointsByDate,
                    gradient: settingsStore.primaryGradient,
                    dateRangeText: analyticsDateRangeText,
                    locationFilterText: analyticsLocationFilterText
                )
            }
        }
    }

    private var secondaryGraphs: some View {
        VStack(spacing: 16) {
            GameBreakdownBars(
                sessions: closedSessions,
                gradient: settingsStore.primaryGradient,
                dateRangeText: analyticsDateRangeText,
                locationFilterText: analyticsLocationFilterText
            )
        }
    }
}

// MARK: - Graph kinds

enum GraphKind: String, CaseIterable, Identifiable {
    case betCaptureDiff
    case venn
    case winLossBars
    case tierProgress

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .betCaptureDiff: return "Bet Rating"
        case .venn: return "Venn"
        case .winLossBars: return "Win/Loss"
        case .tierProgress: return "Tier curve"
        }
    }
}

// MARK: - Reusable components

struct MetricPill: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2)
                .foregroundColor(.gray)
            Text(value)
                .font(.subheadline.bold())
                .foregroundColor(color)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6).opacity(0.15))
        .cornerRadius(12)
    }
}

struct BetCaptureDiffLineChartCard: View {
    let series: [(date: Date, diff: Int)]
    let goodBadCounts: (good: Int, bad: Int)
    let gradient: LinearGradient
    var dateRangeText: String? = nil
    var locationFilterText: String? = nil
    
    private var hasData: Bool { !series.isEmpty }
    
    private var goodPercentageText: String {
        let total = series.count
        guard total > 0 else { return "—" }
        let pct = Double(goodBadCounts.good) / Double(total) * 100.0
        return String(format: "%.0f%% of sessions", pct)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Bet Rating vs Actual", systemImage: "chart.line.uptrend.xyaxis")
                .font(.headline)
                .foregroundColor(.white)
            
            if hasData {
                LineChart(points: series.map { Double($0.diff) }, gradient: gradient, showValueLabels: true)
                    .frame(height: 180)
                
                HStack(spacing: 8) {
                    Label("\(goodBadCounts.good) good", systemImage: "hand.thumbsup.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                    Label("\(goodBadCounts.bad) bad", systemImage: "hand.thumbsdown.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                    Spacer()
                    Text(goodPercentageText)
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            } else {
                Text("No sessions with both actual and rated average bet yet.")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Text("Above 0 means your rated (captured) average bet is higher than your actual average bet, which is good. Below 0 means you’re effectively overbetting relative to what the casino tracks.")
                .font(.caption)
                .foregroundColor(.gray)
            
            if let range = dateRangeText {
                Text("Date range: \(range)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            if let loc = locationFilterText {
                Text(loc)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.15))
        .cornerRadius(16)
    }
}

struct VennDiagramCard: View {
    let leftLabel: String
    let rightLabel: String
    let leftCount: Int
    let rightCount: Int
    let intersectionCount: Int
    let total: Int
    let gradient: LinearGradient
    var dateRangeText: String? = nil
    var locationFilterText: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Win vs. Tier Gain", systemImage: "circle.grid.2x1.fill")
                .font(.headline)
                .foregroundColor(.white)

            VennDiagramView(
                leftColor: Color.green.opacity(0.7),
                rightColor: Color.blue.opacity(0.7),
                gradient: gradient,
                leftLabel: leftLabel,
                rightLabel: rightLabel,
                leftCount: leftCount,
                rightCount: rightCount,
                intersectionCount: intersectionCount
            )
            .frame(height: 220)

            Text("Shows how often you both win money and gain tier points in the same session.")
                .font(.caption)
                .foregroundColor(.gray)

            if let range = dateRangeText {
                Text("Date range: \(range)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            if let loc = locationFilterText {
                Text(loc)
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            HStack {
                Text("Intersection")
                    .font(.caption)
                    .foregroundColor(.gray)
                Spacer()
                Text("\(intersectionCount) of \(total) sessions")
                    .font(.caption.bold())
                    .foregroundColor(.white)
            }
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.15))
        .cornerRadius(16)
    }
}

struct VennDiagramView: View {
    let leftColor: Color
    let rightColor: Color
    let gradient: LinearGradient
    let leftLabel: String
    let rightLabel: String
    let leftCount: Int
    let rightCount: Int
    let intersectionCount: Int

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let radius = size * 0.32
            let centerY = geo.size.height * 0.45
            let offset = radius * 0.7

            ZStack {
                Circle()
                    .fill(leftColor)
                    .frame(width: radius * 2, height: radius * 2)
                    .position(x: geo.size.width * 0.5 - offset, y: centerY)
                Circle()
                    .fill(rightColor)
                    .frame(width: radius * 2, height: radius * 2)
                    .position(x: geo.size.width * 0.5 + offset, y: centerY)

                Circle()
                    .fill(gradient)
                    .opacity(0.8)
                    .frame(width: radius * 1.6, height: radius * 1.6)
                    .position(x: geo.size.width * 0.5, y: centerY)

                VStack(spacing: 4) {
                    Text("\(intersectionCount)")
                        .font(.title.bold())
                        .foregroundColor(.white)
                    Text("Both")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.8))
                }
                .position(x: geo.size.width * 0.5, y: centerY)

                VStack(alignment: .center, spacing: 4) {
                    Text(leftLabel)
                        .font(.caption)
                        .foregroundColor(.white)
                    Text("\(leftCount)")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                .frame(width: radius * 1.3)
                .position(x: geo.size.width * 0.5 - offset, y: centerY - radius - 10)

                VStack(alignment: .center, spacing: 4) {
                    Text(rightLabel)
                        .font(.caption)
                        .foregroundColor(.white)
                    Text("\(rightCount)")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                .frame(width: radius * 1.3)
                .position(x: geo.size.width * 0.5 + offset, y: centerY - radius - 10)
            }
        }
    }
}

struct WinLossBarChartCard: View {
    let totalProfit: Int
    let totalLoss: Int
    let totalSessions: Int
    let gradient: LinearGradient
    let currencySymbol: String
    var dateRangeText: String? = nil
    var locationFilterText: String? = nil

    var body: some View {
        let maxValue = max(Double(totalProfit), Double(totalLoss), 1)

        return VStack(alignment: .leading, spacing: 12) {
            Label("Win/Loss Distribution", systemImage: "chart.bar.fill")
                .font(.headline)
                .foregroundColor(.white)

            VStack(spacing: 10) {
                BarRow(label: "Total profit", value: Double(totalProfit), maxValue: maxValue, gradient: gradient, currencySymbol: currencySymbol)
                BarRow(label: "Total loss", value: Double(totalLoss), maxValue: maxValue, gradient: LinearGradient(colors: [.red, .orange], startPoint: .leading, endPoint: .trailing), currencySymbol: currencySymbol)
            }

            Text("How much you’ve won vs. lost across all completed sessions.")
                .font(.caption)
                .foregroundColor(.gray)

            if let range = dateRangeText {
                Text("Date range: \(range)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            if let loc = locationFilterText {
                Text(loc)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.15))
        .cornerRadius(16)
    }
}

struct BarRow: View {
    let label: String
    let value: Double
    let maxValue: Double
    let gradient: LinearGradient
    let currencySymbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.gray)
                Spacer()
                Text("\(currencySymbol)\(Int(value))")
                    .font(.caption2.bold())
                    .foregroundColor(.white)
            }
            GeometryReader { geo in
                let width = max(2, geo.size.width * CGFloat(value / maxValue))
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.systemGray6).opacity(0.4))
                    RoundedRectangle(cornerRadius: 6)
                        .fill(gradient)
                        .frame(width: width)
                }
            }
            .frame(height: 10)
        }
    }
}

struct TierProgressLineChartCard: View {
    let pointsByDate: [(date: Date, total: Int)]
    let gradient: LinearGradient
    var dateRangeText: String? = nil
    var locationFilterText: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Tier Progress Over Time", systemImage: "chart.line.uptrend.xyaxis")
                .font(.headline)
                .foregroundColor(.white)

            if pointsByDate.isEmpty {
                Text("No tier point data yet.")
                    .font(.caption)
                    .foregroundColor(.gray)
            } else {
                LineChart(points: pointsByDate.map { Double($0.total) }, gradient: gradient)
                    .frame(height: 180)
            }

            Text("Cumulative tier points earned across your recorded sessions.")
                .font(.caption)
                .foregroundColor(.gray)

            if let range = dateRangeText {
                Text("Date range: \(range)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            if let loc = locationFilterText {
                Text(loc)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.15))
        .cornerRadius(16)
    }
}

struct LineChart: View {
    let points: [Double]
    let gradient: LinearGradient
    let showValueLabels: Bool

    init(points: [Double], gradient: LinearGradient, showValueLabels: Bool = false) {
        self.points = points
        self.gradient = gradient
        self.showValueLabels = showValueLabels
    }

    var body: some View {
        GeometryReader { geo in
            let maxVal = max(points.max() ?? 1, 1)
            let minVal = min(points.min() ?? 0, 0)
            let span = max(maxVal - minVal, 1)

            let stepX = points.count > 1 ? geo.size.width / CGFloat(points.count - 1) : 0

            let path = Path { p in
                for (idx, value) in points.enumerated() {
                    let x = CGFloat(idx) * stepX
                    let normalized = (value - minVal) / span
                    let y = geo.size.height * (1 - CGFloat(normalized))
                    if idx == 0 {
                        p.move(to: CGPoint(x: x, y: y))
                    } else {
                        p.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }

            ZStack {
                path
                    .stroke(gradient, style: StrokeStyle(lineWidth: 3, lineJoin: .round))
                ForEach(Array(points.enumerated()), id: \.offset) { idx, value in
                    let x = CGFloat(idx) * stepX
                    let normalized = (value - minVal) / span
                    let y = geo.size.height * (1 - CGFloat(normalized))

                    VStack(spacing: 2) {
                        Circle()
                            .fill(Color.white.opacity(0.9))
                            .frame(width: 4, height: 4)
                        if showValueLabels {
                            let intValue = Int(value.rounded())
                            let signPrefix = intValue > 0 ? "+" : ""
                            Text("\(signPrefix)\(intValue)")
                                .font(.caption2)
                                .foregroundColor(.white)
                        }
                    }
                    .position(x: x, y: y)
                }
            }
        }
    }
}

struct GameBreakdownBars: View {
    let sessions: [Session]
    let gradient: LinearGradient
    var dateRangeText: String? = nil
    var locationFilterText: String? = nil

    private var totalsByGame: [(game: String, count: Int)] {
        let counts = Dictionary(grouping: sessions, by: { $0.game })
            .mapValues { $0.count }
        return counts
            .map { ($0.key, $0.value) }
            .sorted { $0.count > $1.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Sessions by Game", systemImage: "square.grid.2x2.fill")
                .font(.headline)
                .foregroundColor(.white)

            if totalsByGame.isEmpty {
                Text("No game breakdown yet.")
                    .font(.caption)
                    .foregroundColor(.gray)
            } else {
                let maxCount = max(totalsByGame.map { Double($0.count) }.max() ?? 1, 1)
                ForEach(totalsByGame.prefix(5), id: \.game) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(row.game)
                                .font(.caption)
                                .foregroundColor(.white)
                            Spacer()
                            Text("\(row.count)x")
                                .font(.caption2.bold())
                                .foregroundColor(.gray)
                        }
                        GeometryReader { geo in
                            let width = max(2, geo.size.width * CGFloat(Double(row.count) / maxCount))
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(.systemGray6).opacity(0.4))
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(gradient)
                                    .frame(width: width)
                            }
                        }
                        .frame(height: 10)
                    }
                }
            }

            if let range = dateRangeText {
                Text("Date range: \(range)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            if let loc = locationFilterText {
                Text(loc)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.15))
        .cornerRadius(16)
    }
}

#if os(iOS)
@MainActor
private func buildAnalyticsShareImages(
    selection: AnalyticsShareSelection,
    closedSessions: [Session],
    gradient: LinearGradient,
    currencySymbol: String,
    locationFilterText: String? = nil
) -> [UIImage] {
    var images: [UIImage] = []

    let winningSessions = closedSessions.filter { ($0.winLoss ?? 0) > 0 }
    let sessionsWithTierGain = closedSessions.filter { ($0.tierPointsEarned ?? 0) > 0 }
    let vennIntersectionCount = closedSessions.filter { ($0.winLoss ?? 0) > 0 && ($0.tierPointsEarned ?? 0) > 0 }.count
    let totalProfit = closedSessions.compactMap { $0.winLoss }.filter { $0 > 0 }.reduce(0, +)
    let totalLoss = abs(closedSessions.compactMap { $0.winLoss }.filter { $0 < 0 }.reduce(0, +))

    let cumulativePointsByDate: [(date: Date, total: Int)] = {
        let sorted = closedSessions.sorted { $0.startTime < $1.startTime }
        var running = 0
        return sorted.map { session in
            running += session.tierPointsEarned ?? 0
            return (date: session.startTime, total: running)
        }
    }()

    let dateRangeText: String? = {
        guard !closedSessions.isEmpty,
              let first = closedSessions.map(\.startTime).min(),
              let last = closedSessions.map(\.startTime).max() else { return nil }
        let df = DateFormatter()
        df.dateStyle = .medium
        return "\(df.string(from: first)) – \(df.string(from: last))"
    }()

    if selection.includeVenn {
        let card = VennDiagramCard(
            leftLabel: "Winning sessions",
            rightLabel: "Tier gain",
            leftCount: winningSessions.count,
            rightCount: sessionsWithTierGain.count,
            intersectionCount: vennIntersectionCount,
            total: closedSessions.count,
            gradient: gradient,
            dateRangeText: dateRangeText,
            locationFilterText: locationFilterText
        )
        if let image = renderAnalyticsCard(card) {
            images.append(image)
        }
    }

    if selection.includeWinLoss {
        let card = WinLossBarChartCard(
            totalProfit: totalProfit,
            totalLoss: totalLoss,
            totalSessions: closedSessions.count,
            gradient: gradient,
            currencySymbol: currencySymbol,
            dateRangeText: dateRangeText,
            locationFilterText: locationFilterText
        )
        if let image = renderAnalyticsCard(card) {
            images.append(image)
        }
    }

    if selection.includeTierProgress && !cumulativePointsByDate.isEmpty {
        let card = TierProgressLineChartCard(
            pointsByDate: cumulativePointsByDate,
            gradient: gradient,
            dateRangeText: dateRangeText,
            locationFilterText: locationFilterText
        )
        if let image = renderAnalyticsCard(card) {
            images.append(image)
        }
    }

    if selection.includeGameBreakdown {
        let card = GameBreakdownBars(
            sessions: closedSessions,
            gradient: gradient,
            dateRangeText: dateRangeText,
            locationFilterText: locationFilterText
        )
        if let image = renderAnalyticsCard(card) {
            images.append(image)
        }
    }

    return images
}

private func writeShareImagesToTempFiles(_ images: [UIImage]) -> [URL] {
    let df = DateFormatter()
    df.dateFormat = "yyyyMMddHHmmss"
    let timestamp = df.string(from: Date())
    let tempDir = FileManager.default.temporaryDirectory
    var urls: [URL] = []
    for (index, image) in images.enumerated() {
        let name = images.count > 1 ? "TierTap\(timestamp)-\(index + 1).png" : "TierTap\(timestamp).png"
        let url = tempDir.appendingPathComponent(name)
        guard let data = image.pngData() else { continue }
        try? data.write(to: url)
        urls.append(url)
    }
    return urls
}

@MainActor
private func renderAnalyticsCard<V: View>(_ view: V) -> UIImage? {
    let width = UIScreen.main.bounds.width * 0.9
    let height: CGFloat = 420

    if #available(iOS 16.0, *) {
        let wrapped = view
            .padding()
            .frame(width: width, height: height)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 16))

        let renderer = ImageRenderer(content: wrapped)
        renderer.scale = UIScreen.main.scale
        renderer.proposedSize = ProposedViewSize(width: width, height: height)
        return renderer.uiImage
    } else {
        let controller = UIHostingController(
            rootView: view
                .padding()
                .frame(width: width, height: height)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        )

        let size = CGSize(width: width, height: height)
        controller.view.bounds = CGRect(origin: .zero, size: size)
        controller.view.backgroundColor = .clear

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
    }
}
#endif

struct AnalyticsShareSelectionSheet: View {
    let closedSessions: [Session]
    let gradient: LinearGradient
    let onShare: (AnalyticsShareSelection) -> Void

    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) var dismiss

    @State private var includeVenn = true
    @State private var includeWinLoss = true
    @State private var includeTierProgress = true
    @State private var includeGameBreakdown = true

    private var hasTierData: Bool {
        !closedSessions
            .filter { ($0.tierPointsEarned ?? 0) != 0 }
            .isEmpty
    }

    private var canShare: Bool {
        includeVenn || includeWinLoss || (includeTierProgress && hasTierData) || includeGameBreakdown
    }

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                List {
                    Section(header: Text("Include in share").foregroundColor(.white)) {
                        HStack {
                            Button {
                                includeVenn = true
                                includeWinLoss = true
                                includeTierProgress = true
                                includeGameBreakdown = true
                            } label: {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("Select All")
                                        .foregroundColor(.white)
                                }
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Button {
                                includeVenn = false
                                includeWinLoss = false
                                includeTierProgress = false
                                includeGameBreakdown = false
                            } label: {
                                HStack {
                                    Image(systemName: "xmark.circle")
                                        .foregroundColor(.red)
                                    Text("Deselect All")
                                        .foregroundColor(.white)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .listRowBackground(Color(.systemGray6).opacity(0.2))

                        Toggle("Win vs. Tier Gain (Venn)", isOn: $includeVenn)
                        Toggle("Win/Loss Distribution", isOn: $includeWinLoss)
                        Toggle("Tier Progress Over Time", isOn: $includeTierProgress)
                            .disabled(!hasTierData)
                        Toggle("Sessions by Game", isOn: $includeGameBreakdown)
                    }

                    Section(
                        footer: Text("We’ll generate images for the selected analytics and open the system share sheet so you can send them however you like.")
                            .font(.footnote)
                            .foregroundColor(.gray)
                    ) {
                        EmptyView()
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Share Analytics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.green)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Share") {
                        #if os(iOS)
                        let selection = AnalyticsShareSelection(
                            includeVenn: includeVenn,
                            includeWinLoss: includeWinLoss,
                            includeTierProgress: includeTierProgress,
                            includeGameBreakdown: includeGameBreakdown
                        )
                        onShare(selection)
                        #endif
                        dismiss()
                    }
                    .disabled(!canShare)
                    .foregroundColor(canShare ? .green : .gray)
                }
            }
        }
    }
}
