import SwiftUI
import UIKit
import Supabase

struct AnalyticsShareSelection {
    let includeBetCaptureDiff: Bool
    let includeVenn: Bool
    let includeWinLoss: Bool
    let includeTierProgress: Bool
    let includeGameBreakdown: Bool
    let includeTierByLoyaltyProgram: Bool
    let includeSessionMoods: Bool
}

struct AnalyticsView: View {
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var authStore: AuthStore
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    
    @State private var isAISheetPresented: Bool = false
    @State private var isPaywallPresented: Bool = false
    
    @State private var selectedGraphKind: GraphKind = .betCaptureDiff
    @State private var isShareSelectionPresented: Bool = false
    @State private var isShareSheetPresented: Bool = false
    @State private var analyticsFromDate: Date? = nil
    @State private var analyticsToDate: Date? = nil
    @State private var isFiltersExpanded: Bool = false

#if os(iOS)
    @State private var shareImages: [UIImage] = []
    @State private var shareURLs: [URL] = []
    @State private var pendingShareSelection: AnalyticsShareSelection?
#endif

    @State private var selectedAnalyticsCategory: SessionGameCategory = .table

    private var allClosedSessions: [Session] {
        sessionStore.sessions.filter { $0.winLoss != nil }
    }

    /// Whether there are any closed sessions at all, regardless of category.
    private var hasAnyClosedSessions: Bool {
        !allClosedSessions.isEmpty
    }

    /// Table-only closed sessions.
    private var tableClosedSessions: [Session] {
        allClosedSessions.filter { $0.gameCategory != .poker }
    }

    /// Poker-only closed sessions.
    private var pokerClosedSessions: [Session] {
        allClosedSessions.filter { $0.gameCategory == .poker }
    }

    /// Closed sessions for the currently selected analytics category.
    private var closedSessions: [Session] {
        let baseAll: [Session]
        switch selectedAnalyticsCategory {
        case .table:
            baseAll = tableClosedSessions
        case .poker:
            baseAll = pokerClosedSessions
        }
        var base = baseAll
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

    /// Sessions that have a mood set (for mood bar chart).
    private var sessionsWithMood: [Session] {
        closedSessions.filter { $0.sessionMood != nil }
    }

    /// Count per mood, ordered for display (positive first, then neutral, then negative).
    private var moodCounts: [(mood: SessionMood, count: Int)] {
        let grouped = Dictionary(grouping: sessionsWithMood, by: { $0.sessionMood! })
            .mapValues { $0.count }
        return SessionMood.allCases
            .compactMap { mood in (grouped[mood]).map { (mood: mood, count: $0) } }
            .filter { $0.count > 0 }
            .sorted { $0.count > $1.count }
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

    private var hasProAccess: Bool {
        subscriptionStore.isPro || settingsStore.isSubscriptionOverrideActive
    }

    private struct GameTypePillAnalytics: View {
        let title: String
        let isSelected: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Text(title)
                    .font(.caption.bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(isSelected ? Color.green : Color(.systemGray6).opacity(0.25))
                    .foregroundColor(isSelected ? .black : .white)
                    .clipShape(Capsule())
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                if !hasAnyClosedSessions {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            headerSummary
                            filtersSection
                            gameCategoryToggle
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
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if hasProAccess && authStore.isSignedIn {
                            isAISheetPresented = true
                        } else {
                            isPaywallPresented = true
                        }
                    } label: {
                        Image(systemName: "wand.and.stars")
                            .imageScale(.medium)
                    }
                    .foregroundColor(.white)
                    .accessibilityLabel("AI analysis")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 8) {
                        if !closedSessions.isEmpty {
                            Button {
                                if settingsStore.enableCasinoFeedback {
                                    CelebrationPlayer.shared.playQuickChime()
                                }
                                isShareSelectionPresented = true
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                                    .imageScale(.medium)
                            }
                            .foregroundColor(.white)
                        }

                        Button {
                            NotificationCenter.default.post(name: NSNotification.Name("ShowAccountSheet"), object: nil)
                        } label: {
                            HStack(spacing: 6) {
                                if authStore.isSignedIn,
                                   let data = authStore.userProfilePhotoData,
                                   let uiImage = UIImage(data: data) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 24, height: 24)
                                        .clipShape(Circle())
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white.opacity(0.7), lineWidth: 1)
                                        )
                                } else {
                                    Image(systemName: authStore.isSignedIn ? "person.crop.circle.fill" : "person.crop.circle")
                                }
                                if authStore.isSignedIn {
                                    if authStore.userProfilePhotoData == nil,
                                       let emojis = authStore.userProfileEmojis,
                                       !emojis.isEmpty {
                                        Text(emojis)
                                            .font(.caption)
                                    }
                                    Text(authStore.signedInSummary ?? authStore.userEmail ?? "Account")
                                        .lineLimit(1)
                                        .font(.caption)
                                } else {
                                    Text("Account")
                                        .font(.caption)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.18))
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .adaptiveSheet(isPresented: $isAISheetPresented) {
            AIAnalyticsSheet()
                .environmentObject(settingsStore)
                .environmentObject(subscriptionStore)
                .environmentObject(authStore)
        }
        .adaptiveSheet(isPresented: $isPaywallPresented) {
            TierTapPaywallView()
                .environmentObject(subscriptionStore)
                .environmentObject(settingsStore)
                .environmentObject(authStore)
        }
        .adaptiveSheet(isPresented: $isShareSelectionPresented) {
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
        .adaptiveSheet(isPresented: $isShareSheetPresented) {
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

    private var filtersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut) {
                    isFiltersExpanded.toggle()
                }
            } label: {
                HStack {
                    Text("Filters")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: isFiltersExpanded ? "chevron.up" : "chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .buttonStyle(.plain)

            if isFiltersExpanded {
                VStack(spacing: 16) {
                    locationFilterBar
                    dateFilterBar
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
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
                Text(selectedAnalyticsCategory == .table ? "Table Session Overview" : "Poker Session Overview")
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
            if !moodCounts.isEmpty {
                SessionMoodBarChartCard(
                    moodCounts: moodCounts,
                    gradient: settingsStore.primaryGradient,
                    dateRangeText: analyticsDateRangeText,
                    locationFilterText: analyticsLocationFilterText
                )
            }
            if selectedAnalyticsCategory == .table {
                GameBreakdownBars(
                    sessions: closedSessions,
                    gradient: settingsStore.primaryGradient,
                    dateRangeText: analyticsDateRangeText,
                    locationFilterText: analyticsLocationFilterText
                )
                TierPointsByLoyaltyProgramBars(
                    sessions: closedSessions,
                    gradient: settingsStore.primaryGradient,
                    dateRangeText: analyticsDateRangeText,
                    locationFilterText: analyticsLocationFilterText
                )
            } else {
                PokerPerformanceSummaryCard(
                    sessions: closedSessions,
                    gradient: settingsStore.primaryGradient,
                    currencySymbol: settingsStore.currencySymbol,
                    dateRangeText: analyticsDateRangeText,
                    locationFilterText: analyticsLocationFilterText
                )
                PokerROITrendChartCard(
                    sessions: closedSessions,
                    gradient: settingsStore.primaryGradient,
                    currencySymbol: settingsStore.currencySymbol,
                    dateRangeText: analyticsDateRangeText,
                    locationFilterText: analyticsLocationFilterText
                )
            }
        }
    }

    /// Toggle between Table and Poker analytics.
    private var gameCategoryToggle: some View {
        HStack(spacing: 8) {
            Text("Game type")
                .font(.subheadline.bold())
                .foregroundColor(.white)
            Spacer()
            GameTypePillAnalytics(
                title: "Table",
                isSelected: selectedAnalyticsCategory == .table
            ) {
                selectedAnalyticsCategory = .table
            }
            GameTypePillAnalytics(
                title: "Poker",
                isSelected: selectedAnalyticsCategory == .poker
            ) {
                selectedAnalyticsCategory = .poker
            }
        }
    }
}

struct AIAnalyticsSheet: View {
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @Environment(\.dismiss) private var dismiss
    
    enum TierTapAIQuestion: String, CaseIterable, Identifiable {
        // Table-focused questions
        case whereEarnTiersFastest
        case rankProgramsByTierEfficiency
        case rankPropertiesByTierEfficiency
        case bestGamePropertyCombos
        case optimizeForFastestTierGain
        
        case showRatedVsActualGaps
        case whereUnderRated
        case trendGapByProperty
        case trendGapByGame
        case ratingInsightsConfidence
        
        case moodVsPlay
        case whenTiltedOrOff
        case gentleBreakMoments
        
        case highVolatilitySessions
        case riskVolatilityProfile
        case stopLossAndBreakNudges
        
        case tapPointsEarningLately
        case nextBadgeOrLevel
        case consistencyTapPointsIdeas
        case bestFittingRewards
        
        // Poker-focused questions
        case pokerProfitabilityOverview
        case pokerWinrateByGame
        case pokerROITrends
        case pokerSessionPatterns
        case pokerRiskProfile
        
        var id: String { rawValue }
        
        /// Questions intended when analyzing non‑poker (table) sessions.
        static var tableQuestions: [TierTapAIQuestion] {
            [
                .whereEarnTiersFastest,
                .rankProgramsByTierEfficiency,
                .rankPropertiesByTierEfficiency,
                .bestGamePropertyCombos,
                .optimizeForFastestTierGain,
                .showRatedVsActualGaps,
                .whereUnderRated,
                .trendGapByProperty,
                .trendGapByGame,
                .ratingInsightsConfidence,
                .moodVsPlay,
                .whenTiltedOrOff,
                .gentleBreakMoments,
                .highVolatilitySessions,
                .riskVolatilityProfile,
                .stopLossAndBreakNudges,
                .tapPointsEarningLately,
                .nextBadgeOrLevel,
                .consistencyTapPointsIdeas,
                .bestFittingRewards
            ]
        }
        
        /// Questions intended when analyzing poker sessions only.
        static var pokerQuestions: [TierTapAIQuestion] {
            [
                .pokerProfitabilityOverview,
                .pokerWinrateByGame,
                .pokerROITrends,
                .pokerSessionPatterns,
                .pokerRiskProfile,
                .moodVsPlay,
                .whenTiltedOrOff,
                .gentleBreakMoments,
                .highVolatilitySessions,
                .riskVolatilityProfile,
                .stopLossAndBreakNudges
            ]
        }
        
        var title: String {
            switch self {
            case .whereEarnTiersFastest: return "Where do I earn tiers fastest?"
            case .rankProgramsByTierEfficiency: return "Rank my casino programs by tier efficiency"
            case .rankPropertiesByTierEfficiency: return "Rank my properties by tier efficiency"
            case .bestGamePropertyCombos: return "Best game and property combos for tiers"
            case .optimizeForFastestTierGain: return "Optimize my play for fastest tier gain"
            case .showRatedVsActualGaps: return "Show my rated vs actual gaps"
            case .whereUnderRated: return "Where am I consistently under-rated?"
            case .trendGapByProperty: return "Trend my rating gaps by property"
            case .trendGapByGame: return "Trend my rating gaps by game"
            case .ratingInsightsConfidence: return "How confident are my rating insights?"
            case .moodVsPlay: return "How does my mood relate to my play?"
            case .whenTiltedOrOff: return "When do I tend to feel tilted or off?"
            case .gentleBreakMoments: return "When might a gentle break reminder help?"
            case .highVolatilitySessions: return "Show my high-volatility sessions"
            case .riskVolatilityProfile: return "Explain my typical risk/volatility profile"
            case .stopLossAndBreakNudges: return "When should I see stop-loss or break nudges?"
            case .tapPointsEarningLately: return "How am I earning TapPoints lately?"
            case .nextBadgeOrLevel: return "What do I need for my next badge or level?"
            case .consistencyTapPointsIdeas: return "Easy ways to earn more TapPoints through consistency"
            case .bestFittingRewards: return "Which rewards best fit my habits?"
            case .pokerProfitabilityOverview: return "How is my poker profitability overall?"
            case .pokerWinrateByGame: return "How do my poker results vary by game type?"
            case .pokerROITrends: return "How is my poker ROI trending over time?"
            case .pokerSessionPatterns: return "What patterns show up in my poker sessions?"
            case .pokerRiskProfile: return "What is my risk/volatility profile in poker?"
            }
        }
        
        func instruction(toneLabel: String) -> String {
            switch self {
            case .whereEarnTiersFastest:
                return "From non‑poker sessions only, show where the player earns tiers fastest by program, property, and game, using tiers per hour and tiers per unit of rated bet. Keep it \(toneLabel), concise, and specific to this history."
            case .rankProgramsByTierEfficiency:
                return "Using table sessions (excluding poker), rank casino loyalty programs by tier‑earning efficiency and briefly note why the top few stand out, in \(toneLabel)."
            case .rankPropertiesByTierEfficiency:
                return "Rank properties from table play by how efficiently they earn tiers. Highlight only a few clear leaders, using \(toneLabel)."
            case .bestGamePropertyCombos:
                return "From non‑poker play, list the best property + game combinations for earning tiers efficiently, summarizing patterns in \(toneLabel)."
            case .optimizeForFastestTierGain:
                return "Given the existing non‑poker play, suggest a few realistic ways to focus on faster tier gain using programs, properties, and games they already use. Keep it \(toneLabel) and non‑prescriptive."
            case .showRatedVsActualGaps:
                return "Analyze gaps between rated and actual average bet in table sessions. Summarize where gaps appear and their rough size, in \(toneLabel), staying factual."
            case .whereUnderRated:
                return "From non‑poker sessions, look for places where rated average bet is consistently below actual. Gently describe any properties or games that look under‑rated, using \(toneLabel)."
            case .trendGapByProperty:
                return "Describe how the rating gap between actual and rated bet in table play has trended by property over time (better, worse, similar), in \(toneLabel)."
            case .trendGapByGame:
                return "Describe how the rating gap between actual and rated bet in table play has trended by game over time, focusing on patterns in \(toneLabel)."
            case .ratingInsightsConfidence:
                return "Assess how strong or weak the table rating insights are based on sample size and consistency. Explain confidence levels briefly in \(toneLabel)."
            case .moodVsPlay:
                return "Correlate recorded moods with how sessions went (length, net, volatility, tiers) for the selected game set. Use \(toneLabel) and focus on gentle self‑awareness."
            case .whenTiltedOrOff:
                return "Look for situations where the player reports feeling 'off' or 'tilted' and describe patterns in games, properties, or session characteristics, using \(toneLabel) and soft language."
            case .gentleBreakMoments:
                return "Suggest a few circumstances from the selected game set where a soft 'take a break' nudge could have helped (very long sessions, repeated negative moods), in gentle \(toneLabel)."
            case .highVolatilitySessions:
                return "Identify sessions that look high‑volatility (large swings, big buy‑ins or adds, long durations) and describe them with calm variance/risk framing in \(toneLabel)."
            case .riskVolatilityProfile:
                return "Using the selected game set, describe the player's typical risk and volatility profile in simple terms, using \(toneLabel) and avoiding betting advice."
            case .stopLossAndBreakNudges:
                return "Based on the selected game set, suggest a few gentle time‑ or loss‑based moments where a stop‑loss or break reminder could make sense, in \(toneLabel)."
            case .tapPointsEarningLately:
                return "Using recent engagement patterns (sessions logged, streaks, consistency), describe how they appear to be earning engagement‑style rewards such as TapPoints, in \(toneLabel)."
            case .nextBadgeOrLevel:
                return "Given how often and how consistently the player engages with the app, suggest a few realistic next‑badge or level‑style milestones, emphasizing healthy, track‑focused behavior in \(toneLabel)."
            case .consistencyTapPointsIdeas:
                return "Recommend simple ways to earn more engagement rewards through consistency (logging sessions promptly, maintaining streaks), using \(toneLabel) and avoiding any push to gamble more."
            case .bestFittingRewards:
                return "Based on travel and play patterns, suggest reward or perk styles that would likely fit them best (e.g., travel or status perks), keeping the focus on engagement and experience in \(toneLabel)."
            case .pokerProfitabilityOverview:
                return "Using only poker sessions, summarize overall poker profitability, win/loss counts, and any clear patterns by property or game, in \(toneLabel)."
            case .pokerWinrateByGame:
                return "From poker sessions only, compare results by poker game type (e.g., cash vs tournaments, game variants) and highlight where results look stronger or weaker, in \(toneLabel)."
            case .pokerROITrends:
                return "Using only poker sessions, describe how poker ROI and net results have trended over time, calling out any clear upswings or downswings, in \(toneLabel)."
            case .pokerSessionPatterns:
                return "From poker sessions only, describe patterns in session length, stakes, and outcomes, and what that might suggest about pacing and game selection, using \(toneLabel)."
            case .pokerRiskProfile:
                return "Using just poker sessions, explain the player's risk and volatility profile in poker (swings, buy‑ins, adds) in simple terms, in \(toneLabel), without giving betting strategy."
            }
        }
    }
    
    @State private var isLoading = false
    @State private var fullAnswer: String?
    @State private var displayedAnswer: String = ""
    @State private var errorMessage: String?
    
    @State private var selectedQuestion: TierTapAIQuestion = .whereEarnTiersFastest
    @State private var selectedAnalyticsCategory: SessionGameCategory = .table

    private var hasProAccess: Bool {
        subscriptionStore.isPro || settingsStore.isSubscriptionOverrideActive
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                VStack(spacing: 20) {
                    VStack(spacing: 16) {
                        HStack {
                            Text("AI Analysis")
                                .font(.title2.bold())
                                .foregroundColor(.white)
                            Spacer()
                            HStack(spacing: 8) {
                                GameTypePillAI(
                                    title: "Table",
                                    isSelected: selectedAnalyticsCategory == .table
                                ) {
                                    selectedAnalyticsCategory = .table
                                    if !TierTapAIQuestion.tableQuestions.contains(selectedQuestion) {
                                        selectedQuestion = TierTapAIQuestion.tableQuestions.first ?? .whereEarnTiersFastest
                                    }
                                }
                                GameTypePillAI(
                                    title: "Poker",
                                    isSelected: selectedAnalyticsCategory == .poker
                                ) {
                                    selectedAnalyticsCategory = .poker
                                    if !TierTapAIQuestion.pokerQuestions.contains(selectedQuestion) {
                                        selectedQuestion = TierTapAIQuestion.pokerQuestions.first ?? .pokerProfitabilityOverview
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Question")
                                .font(.caption.bold())
                                .foregroundColor(.white.opacity(0.8))
                            Menu {
                                ForEach(questionsForCurrentCategory, id: \.self) { question in
                                    Button(question.title) {
                                        selectedQuestion = question
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(selectedQuestion.title)
                                        .font(.body)
                                        .foregroundColor(.white)
                                        .multilineTextAlignment(.leading)
                                    Spacer()
                                    Image(systemName: "chevron.up.chevron.down")
                                        .foregroundColor(.white.opacity(0.7))
                                }
                                .padding()
                                .background(Color.black.opacity(0.25))
                                .cornerRadius(12)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        if isLoading {
                            ProgressView("Asking TierTap AI…")
                                .tint(.white)
                        }
                        
                        if fullAnswer != nil {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Answer")
                                    .font(.caption.bold())
                                    .foregroundColor(.white.opacity(0.8))
                                ScrollView {
                                    Text(displayedAnswer)
                                        .font(.body)
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding()
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                .background(Color.black.opacity(0.35))
                                .cornerRadius(12)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        } else if let errorMessage = errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        } else if !hasProAccess {
                            Text("AI Analysis is part of TierTap Pro. Subscribe on the Settings tab to unlock Ask TierTap.")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        } else {
                            Text("Ask TierTap as often as you like with your TierTap Pro subscription.")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    
                    Button {
                        Task { await callAI() }
                    } label: {
                        HStack(spacing: 8) {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "sparkles")
                                Text("Ask TierTap")
                                    .fontWeight(.semibold)
                            }
                        }
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white)
                        .cornerRadius(16)
                        .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
                    }
                    .disabled(isLoading)
                }
                .padding()
            }
            .navigationTitle("AI Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(.green)
                }
            }
        }
    }
    
    /// Small pill toggle used within the AI sheet.
    private struct GameTypePillAI: View {
        let title: String
        let isSelected: Bool
        let action: () -> Void
        
        var body: some View {
            Button(action: action) {
                Text(title)
                    .font(.caption.bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(isSelected ? Color.green : Color(.systemGray6).opacity(0.25))
                    .foregroundColor(isSelected ? .black : .white)
                    .clipShape(Capsule())
            }
        }
    }
    
    /// Currently available questions given the selected game category.
    private var questionsForCurrentCategory: [TierTapAIQuestion] {
        switch selectedAnalyticsCategory {
        case .table:
            return TierTapAIQuestion.tableQuestions
        case .poker:
            return TierTapAIQuestion.pokerQuestions
        }
    }
    
    private func callAI() async {
        guard SupabaseConfig.isConfigured, let client = supabase else {
            await MainActor.run {
                errorMessage = "Supabase is not configured. Add your project keys to SupabaseKeys.plist."
            }
            return
        }
        
        // Enforce daily AI usage limit only for non‑Pro users.
        if !hasProAccess && !settingsStore.canUseAI() {
            await MainActor.run {
                errorMessage = "You have reached the daily limit of 5 AI calls on the free version of TierTap. Upgrade to the PRO version to unlock unlimited AI analysis."
            }
            return
        }
        
        let allSessions = sessionStore.sessions
        
        // Filter sessions by selected AI category.
        let closedSessions: [Session] = allSessions.filter { session in
            guard session.winLoss != nil else { return false }
            switch selectedAnalyticsCategory {
            case .table:
                return session.gameCategory != .poker
            case .poker:
                return session.gameCategory == .poker
            }
        }
        
        if closedSessions.isEmpty {
            await MainActor.run {
                errorMessage = selectedAnalyticsCategory == .poker
                ? "You do not have any completed poker sessions yet. Switch to Table or log some poker sessions first."
                : "You do not have any completed table sessions yet for AI to analyze."
            }
            return
        }
        
        let sortedRecent = closedSessions.sorted { $0.startTime > $1.startTime }
        let recentSessions = Array(sortedRecent.prefix(20))
        
        let total = closedSessions.count
        let wins = closedSessions.filter { ($0.winLoss ?? 0) > 0 }.count
        let losses = closedSessions.filter { ($0.winLoss ?? 0) < 0 }.count
        let breakeven = closedSessions.filter { ($0.winLoss ?? 0) == 0 }.count
        let net = closedSessions.compactMap { $0.winLoss }.reduce(0, +)
        let avgPerSession: Double? = total > 0 ? Double(net) / Double(total) : nil
        let winRate: Double? = total > 0 ? Double(wins) / Double(total) : nil
        
        let rorResult = RiskOfRuinMath.compute(
            sessions: closedSessions,
            bankroll: settingsStore.bankroll,
            unitSize: settingsStore.unitSize,
            targetAveragePerSession: settingsStore.targetAveragePerSession,
            currentBetAmount: nil
        )
        
        let currency = settingsStore.currencySymbol
        let netString: String = {
            if net == 0 { return "break-even" }
            let sign = net > 0 ? "+" : "-"
            return "\(sign)\(currency)\(abs(net))"
        }()
        let avgString: String = {
            guard let avg = avgPerSession else { return "n/a" }
            let rounded = Int(round(abs(avg)))
            let sign = avg > 0 ? "+" : (avg < 0 ? "-" : "")
            return "\(sign)\(currency)\(rounded) per session"
        }()
        let winRateString: String = {
            guard let wr = winRate else { return "n/a" }
            return String(format: "%.0f%%", wr * 100)
        }()
        let rorPercentString: String = {
            let pct = rorResult.riskOfRuin * 100
            if rorResult.sessionCount == 0 { return "n/a" }
            if pct >= 99.5 { return "~100%" }
            if pct <= 0.5 { return "<1%" }
            return String(format: "%.1f%%", pct)
        }()
        
        let df = DateFormatter()
        df.dateStyle = .short
        
        let recentLines: String = recentSessions.map { session in
            let wl = session.winLoss ?? 0
            let wlSign = wl > 0 ? "+" : (wl < 0 ? "-" : "")
            let wlText = wl == 0 ? "even" : "\(wlSign)\(currency)\(abs(wl))"
            let points = session.tierPointsEarned ?? 0
            let mood = session.sessionMood?.label ?? "none"
            let hours = String(format: "%.1f hrs", session.hoursPlayed)
            let ratedBet = session.avgBetRated.map { "\(currency)\($0)" } ?? "n/a"
            let actualBet = session.avgBetActual.map { "\(currency)\($0)" } ?? "n/a"
            let ratingGapText: String = {
                if let rated = session.avgBetRated, let actual = session.avgBetActual {
                    let diff = rated - actual
                    let sign = diff > 0 ? "+" : (diff < 0 ? "-" : "")
                    return "\(sign)\(currency)\(abs(diff))"
                } else {
                    return "n/a"
                }
            }()
            let dateText = df.string(from: session.startTime)
            return "\(dateText): \(session.casino) — \(session.game), \(wlText), \(points) pts, mood: \(mood), \(hours), rated avg bet: \(ratedBet), actual avg bet: \(actualBet), rating gap: \(ratingGapText)"
        }.joined(separator: "\n")
        
        let statsBlock = """
        Settings: bankroll \(currency)\(settingsStore.bankroll), unit \(currency)\(settingsStore.unitSize)
        Summary: sessions \(total), W \(wins), L \(losses), even \(breakeven), net \(netString), avg \(avgString), win rate \(winRateString), est. risk of ruin \(rorPercentString)
        """
        
        let toneInstruction = settingsStore.aiTone.promptLabel
        let questionPrompt = selectedQuestion.instruction(toneLabel: toneInstruction)
        let gameLabel = selectedAnalyticsCategory == .poker ? "poker" : "non‑poker table"
        
        let prompt = """
        You are an analytics assistant for TierTap.
        Question: \"\(selectedQuestion.title)\"
        Style: \(toneInstruction). Keep answers concise, grounded in data, and specific to this player's \(gameLabel) history.
        Task: \(questionPrompt)
        Data summary:
        \(statsBlock)
        Recent \(gameLabel) sessions (most recent first):
        \(recentLines)
        """
        
        await MainActor.run {
            isLoading = true
            errorMessage = nil
            fullAnswer = nil
            displayedAnswer = ""
        }
        
        struct GeminiRequest: Encodable {
            struct Part: Encodable { let text: String }
            struct Content: Encodable {
                let role: String
                let parts: [Part]
            }
            let contents: [Content]
        }
        struct GeminiPart: Decodable {
            let text: String?
        }
        struct GeminiContent: Decodable {
            let parts: [GeminiPart]?
        }
        struct GeminiCandidate: Decodable {
            let content: GeminiContent?
        }
        struct GeminiRouterResponse: Decodable {
            let candidates: [GeminiCandidate]?
        }
        
        do {
            // Record usage before calling the Gemini router so we never exceed the limit for free users.
            if !subscriptionStore.isPro && !settingsStore.isSubscriptionOverrideActive {
                await MainActor.run {
                    settingsStore.registerAICall()
                }
            }
            let body = GeminiRequest(
                contents: [
                    .init(role: "user", parts: [.init(text: prompt)])
                ]
            )
            let response: GeminiRouterResponse = try await GeminiRouterThrottle.shared.executeWithRetries {
                try await client.functions.invoke(
                    "gemini-router",
                    options: FunctionInvokeOptions(body: body)
                )
            }
            let text = response.candidates?
                .first?
                .content?
                .parts?
                .compactMap { $0.text }
                .joined(separator: "\n")
                ?? "No text response from Gemini."
            await MainActor.run {
                fullAnswer = text
                isLoading = false
            }
            await typeOut(text)
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
    
    private func typeOut(_ text: String) async {
        await MainActor.run {
            displayedAnswer = ""
        }
        for character in text {
            try? await Task.sleep(nanoseconds: 25_000_000)
            await MainActor.run {
                displayedAnswer.append(character)
            }
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

    /// Indices of points that should show a value label so labels don't overlap (evenly spaced, max 8).
    private var valueLabelIndices: Set<Int> {
        let n = points.count
        let maxLabels = 8
        if n <= maxLabels { return Set(0..<n) }
        return Set((0..<maxLabels).map { i in (i * (n - 1)) / max(1, maxLabels - 1) })
    }

    var body: some View {
        GeometryReader { geo in
            let maxVal = max(points.max() ?? 1, 1)
            let minVal = min(points.min() ?? 0, 0)
            let span = max(maxVal - minVal, 1)

            let stepX = points.count > 1 ? geo.size.width / CGFloat(points.count - 1) : 0
            let showLabelForIndex = valueLabelIndices

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
                    let showLabel = showValueLabels && showLabelForIndex.contains(idx)

                    VStack(spacing: 2) {
                        Circle()
                            .fill(Color.white.opacity(0.9))
                            .frame(width: 4, height: 4)
                        if showLabel {
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

struct SessionMoodBarChartCard: View {
    let moodCounts: [(mood: SessionMood, count: Int)]
    let gradient: LinearGradient
    var dateRangeText: String? = nil
    var locationFilterText: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Session moods", systemImage: "face.smiling.fill")
                .font(.headline)
                .foregroundColor(.white)

            if moodCounts.isEmpty {
                Text("No session moods recorded yet. Enable \"Prompt for session mood\" in Settings → Sessions and end a session to record how each session felt.")
                    .font(.caption)
                    .foregroundColor(.gray)
            } else {
                let maxCount = max(moodCounts.map { Double($0.count) }.max() ?? 1, 1)
                ForEach(moodCounts, id: \.mood) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(row.mood.label)
                                .font(.caption)
                                .foregroundColor(.white)
                            Spacer()
                            Text("\(row.count)")
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

struct TierPointsByLoyaltyProgramBars: View {
    let sessions: [Session]
    let gradient: LinearGradient
    var dateRangeText: String? = nil
    var locationFilterText: String? = nil

    // Simple mapping from casino name keywords to loyalty programs.
    private let loyaltyProgramRules: [(keyword: String, program: String)] = [
        ("MGM", "MGM Rewards"),
        ("Bellagio", "MGM Rewards"),
        ("Aria", "MGM Rewards"),
        ("Cosmopolitan", "Identity Rewards"),
        ("Caesars", "Caesars Rewards"),
        ("Harrah", "Caesars Rewards"),
        ("Paris", "Caesars Rewards"),
        ("Wynn", "Wynn Rewards"),
        ("Encore", "Wynn Rewards"),
        ("Venetian", "Grazie Rewards"),
        ("Palazzo", "Grazie Rewards"),
        ("Palms", "Club Serrano"),
        ("Boyd", "B Connected")
    ]

    private func loyaltyProgram(for casino: String) -> String {
        for rule in loyaltyProgramRules {
            if casino.localizedCaseInsensitiveContains(rule.keyword) {
                return rule.program
            }
        }
        return "Other loyalty programs"
    }

    private var totalsByProgram: [(program: String, points: Int)] {
        let rows: [(String, Int)] = sessions.compactMap { session in
            guard let points = session.tierPointsEarned, points > 0 else { return nil }
            let program = loyaltyProgram(for: session.casino)
            return (program, points)
        }

        let grouped = Dictionary(grouping: rows, by: { $0.0 })
        return grouped
            .map { key, values in
                let total = values.reduce(0) { $0 + $1.1 }
                return (program: key, points: total)
            }
            .sorted { $0.points > $1.points }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Tier Points by Loyalty Program", systemImage: "star.circle.fill")
                .font(.headline)
                .foregroundColor(.white)

            if totalsByProgram.isEmpty {
                Text("No tier point data yet.")
                    .font(.caption)
                    .foregroundColor(.gray)
            } else {
                let maxPoints = max(totalsByProgram.map { Double($0.points) }.max() ?? 1, 1)
                ForEach(totalsByProgram.prefix(5), id: \.program) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(row.program)
                                .font(.caption)
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Spacer()
                            Text("\(row.points) pts")
                                .font(.caption2.bold())
                                .foregroundColor(.gray)
                        }
                        GeometryReader { geo in
                            let width = max(2, geo.size.width * CGFloat(Double(row.points) / maxPoints))
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

    let betCaptureDiffByDate: [(date: Date, diff: Int)] = {
        let withBothBets: [(date: Date, diff: Int)] = closedSessions.compactMap { session -> (date: Date, diff: Int)? in
            guard let actual = session.avgBetActual,
                  let rated = session.avgBetRated else { return nil }
            return (date: session.startTime, diff: rated - actual)
        }
        return withBothBets.sorted(by: { lhs, rhs in
            lhs.date < rhs.date
        })
    }()

    let betCaptureGoodBadCounts: (good: Int, bad: Int) = {
        let diffs = betCaptureDiffByDate.map { $0.diff }
        let good = diffs.filter { $0 >= 0 }.count
        let bad = diffs.filter { $0 < 0 }.count
        return (good, bad)
    }()

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

    // Treat this share as poker-focused when all sessions are explicitly marked as poker.
    let isPokerAnalytics: Bool = {
        guard !closedSessions.isEmpty else { return false }
        return closedSessions.allSatisfy { $0.gameCategory == .poker }
    }()

    if selection.includeBetCaptureDiff && !betCaptureDiffByDate.isEmpty {
        let card = BetCaptureDiffLineChartCard(
            series: betCaptureDiffByDate,
            goodBadCounts: betCaptureGoodBadCounts,
            gradient: gradient,
            dateRangeText: dateRangeText,
            locationFilterText: locationFilterText
        )
        if let image = renderAnalyticsCard(card) {
            images.append(image)
        }
    }

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
        if isPokerAnalytics {
            let card = PokerPerformanceSummaryCard(
                sessions: closedSessions,
                gradient: gradient,
                currencySymbol: currencySymbol,
                dateRangeText: dateRangeText,
                locationFilterText: locationFilterText
            )
            if let image = renderAnalyticsCard(card) {
                images.append(image)
            }
        } else {
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
    }

    if selection.includeTierByLoyaltyProgram {
        if isPokerAnalytics {
            let card = PokerROITrendChartCard(
                sessions: closedSessions,
                gradient: gradient,
                currencySymbol: currencySymbol,
                dateRangeText: dateRangeText,
                locationFilterText: locationFilterText
            )
            if let image = renderAnalyticsCard(card) {
                images.append(image)
            }
        } else {
            let card = TierPointsByLoyaltyProgramBars(
                sessions: closedSessions,
                gradient: gradient,
                dateRangeText: dateRangeText,
                locationFilterText: locationFilterText
            )
            if let image = renderAnalyticsCard(card) {
                images.append(image)
            }
        }
    }

    let moodCountsForShare: [(mood: SessionMood, count: Int)] = {
        let withMood = closedSessions.filter { $0.sessionMood != nil }
        let grouped = Dictionary(grouping: withMood, by: { $0.sessionMood! }).mapValues { $0.count }
        return SessionMood.allCases
            .compactMap { mood in (grouped[mood]).map { (mood: mood, count: $0) } }
            .filter { $0.count > 0 }
            .sorted { $0.count > $1.count }
    }()
    if selection.includeSessionMoods && !moodCountsForShare.isEmpty {
        let card = SessionMoodBarChartCard(
            moodCounts: moodCountsForShare,
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

    @State private var includeBetCaptureDiff = true
    @State private var includeVenn = true
    @State private var includeWinLoss = true
    @State private var includeTierProgress = true
    @State private var includeGameBreakdown = true
    @State private var includeTierByLoyaltyProgram = true
    @State private var includeSessionMoods = true

    private var hasTierData: Bool {
        !closedSessions
            .filter { ($0.tierPointsEarned ?? 0) != 0 }
            .isEmpty
    }

    private var hasMoodData: Bool {
        !closedSessions.filter { $0.sessionMood != nil }.isEmpty
    }

    private var canShare: Bool {
        includeBetCaptureDiff
        || includeVenn
        || includeWinLoss
        || (includeTierProgress && hasTierData)
        || includeGameBreakdown
        || (includeTierByLoyaltyProgram && hasTierData)
        || (includeSessionMoods && hasMoodData)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                List {
                    Section(header: Text("Include in share").foregroundColor(.white)) {
                        HStack {
                            Button {
                                includeBetCaptureDiff = true
                                includeVenn = true
                                includeWinLoss = true
                                includeTierProgress = true
                                includeGameBreakdown = true
                                includeTierByLoyaltyProgram = true
                                includeSessionMoods = true
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
                                includeBetCaptureDiff = false
                                includeVenn = false
                                includeWinLoss = false
                                includeTierProgress = false
                                includeGameBreakdown = false
                                includeTierByLoyaltyProgram = false
                                includeSessionMoods = false
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

                        Toggle("Bet Rating vs Actual", isOn: $includeBetCaptureDiff)
                        Toggle("Win vs. Tier Gain (Venn)", isOn: $includeVenn)
                        Toggle("Win/Loss Distribution", isOn: $includeWinLoss)
                        Toggle("Tier Progress Over Time", isOn: $includeTierProgress)
                            .disabled(!hasTierData)
                        Toggle("Sessions by Game", isOn: $includeGameBreakdown)
                        Toggle("Tier Points by Loyalty Program", isOn: $includeTierByLoyaltyProgram)
                            .disabled(!hasTierData)
                        Toggle("Session moods", isOn: $includeSessionMoods)
                            .disabled(!hasMoodData)
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
                        if settingsStore.enableCasinoFeedback {
                            CelebrationPlayer.shared.playQuickChime()
                        }
                        let selection = AnalyticsShareSelection(
                            includeBetCaptureDiff: includeBetCaptureDiff,
                            includeVenn: includeVenn,
                            includeWinLoss: includeWinLoss,
                            includeTierProgress: includeTierProgress,
                            includeGameBreakdown: includeGameBreakdown,
                            includeTierByLoyaltyProgram: includeTierByLoyaltyProgram,
                            includeSessionMoods: includeSessionMoods
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
