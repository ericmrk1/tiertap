import SwiftUI
import UIKit

/// Which local image to use as the background when sharing a session as a photo with metrics overlaid.
enum SessionSharePhotoBase: Equatable, Hashable {
    case sessionChip
    case comp(UUID)
}

private enum HistoryPanelTab: String, CaseIterable {
    case sessions
    case tools
}

/// Tax prep geography: fixed US list + international; session matching uses the last ", XX" token when `XX` is two letters.
private enum TaxPrepGeography {
    static let allStatesLabel = "All States"
    static let internationalLabel = "International"

    /// USPS abbreviations for the 50 U.S. states (D.C. not included).
    static let usStateNamesByCode: [String: String] = [
        "AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas", "CA": "California",
        "CO": "Colorado", "CT": "Connecticut", "DE": "Delaware", "FL": "Florida", "GA": "Georgia",
        "HI": "Hawaii", "ID": "Idaho", "IL": "Illinois", "IN": "Indiana", "IA": "Iowa",
        "KS": "Kansas", "KY": "Kentucky", "LA": "Louisiana", "ME": "Maine", "MD": "Maryland",
        "MA": "Massachusetts", "MI": "Michigan", "MN": "Minnesota", "MS": "Mississippi", "MO": "Missouri",
        "MT": "Montana", "NE": "Nebraska", "NV": "Nevada", "NH": "New Hampshire", "NJ": "New Jersey",
        "NM": "New Mexico", "NY": "New York", "NC": "North Carolina", "ND": "North Dakota", "OH": "Ohio",
        "OK": "Oklahoma", "OR": "Oregon", "PA": "Pennsylvania", "RI": "Rhode Island", "SC": "South Carolina",
        "SD": "South Dakota", "TN": "Tennessee", "TX": "Texas", "UT": "Utah", "VT": "Vermont",
        "VA": "Virginia", "WA": "Washington", "WV": "West Virginia", "WI": "Wisconsin", "WY": "Wyoming"
    ]

    static let usStateCodeSet: Set<String> = Set(usStateNamesByCode.keys)

    static var sortedUSStatePickerRows: [(code: String, name: String)] {
        usStateNamesByCode
            .map { (code: $0.key, name: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// Places three subviews as equal squares in one row using the full proposed width (iOS 16+ `Layout`).
private struct ThreeEqualSquaresRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let count = subviews.count
        guard count > 0 else { return .zero }
        let totalSpacing = spacing * CGFloat(max(0, count - 1))
        let width: CGFloat
        if let w = proposal.width, w.isFinite, w < .greatestFiniteMagnitude {
            width = w
        } else {
            let idealSum = subviews.reduce(CGFloat(0)) { $0 + $1.sizeThatFits(.unspecified).width }
            width = idealSum + totalSpacing
        }
        let side = max(0, (width - totalSpacing) / CGFloat(count))
        return CGSize(width: width, height: side)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let count = subviews.count
        guard count > 0 else { return }
        let totalSpacing = spacing * CGFloat(max(0, count - 1))
        let side = max(0, (bounds.width - totalSpacing) / CGFloat(count))
        var x = bounds.minX
        for index in subviews.indices {
            subviews[index].place(
                at: CGPoint(x: x, y: bounds.minY),
                proposal: ProposedViewSize(width: side, height: side)
            )
            x += side + spacing
        }
    }
}

struct HistoryView: View {
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var rewardWalletStore: RewardWalletStore
    @EnvironmentObject var authStore: AuthStore
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSession: Session?
    @State private var sessionToEdit: Session?
    @State private var sessionToDelete: Session?
    @State private var isDeleteSelectorPresented: Bool = false
    @State private var searchText: String = ""
    /// Collapsed by default; header stays fixed above the scrolling list.
    @State private var isFilterPanelExpanded: Bool = false
    @State private var useDateRangeFilter: Bool = false
    @State private var filterStartDate: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date().addingTimeInterval(-30 * 24 * 60 * 60)
    @State private var filterEndDate: Date = Date()
    @State private var selectedHistoryGames: Set<String> = []
    @State private var selectedHistoryLocations: Set<String> = []
    @State private var isHistoryDateSectionExpanded: Bool = false
    @State private var isHistoryGameSectionExpanded: Bool = false
    @State private var isHistoryLocationSectionExpanded: Bool = false
    @State private var isShareSelectorPresented: Bool = false
    @State private var isShareSheetPresented: Bool = false
    @State private var shareItems: [Any] = []
    @State private var pendingShareItems: [Any]?
    /// Single choice below Filters; legacy sessions without stored verification count as verified.
    @State private var historyTierPointsFilter: SessionTierPointsVerification = .verified
    @State private var selectedHistoryTab: HistoryPanelTab = .sessions
    @State private var isTaxPrepFlowActive = false
    @State private var selectedTaxYear: Int = Calendar.current.component(.year, from: Date())
    @State private var selectedTaxState: String = TaxPrepGeography.allStatesLabel
    @State private var isTaxPrepGenerating = false
    @State private var taxPrepProgress: Double = 0
    @State private var taxPrepStatusMessage: String?
    @State private var taxPrepComingSoonVisible: Bool = false

    private var showDeleteAlert: Binding<Bool> {
        Binding(
            get: { sessionToDelete != nil },
            set: { if !$0 { sessionToDelete = nil } }
        )
    }

    /// Sessions for the scrolling list: date, location, game, search, **tier-points segment**, and tax-prep filters when active.
    private var filteredSessions: [Session] {
        sessionsApplyingHistoryFilters(includeTierPointsVerification: true)
    }

    /// Same as `filteredSessions` but without the tier-points filter — used for Tools and share so the tier segment (only on the Sessions tab) does not gray out actions while sessions still exist.
    private var sessionsMatchingHistoryBulkFilters: [Session] {
        sessionsApplyingHistoryFilters(includeTierPointsVerification: false)
    }

    private func sessionsApplyingHistoryFilters(includeTierPointsVerification: Bool) -> [Session] {
        var sessions = store.sessions

        if useDateRangeFilter {
            let lo = min(filterStartDate, filterEndDate)
            let hi = max(filterStartDate, filterEndDate)
            sessions = sessions.filter { $0.startTime >= lo && $0.startTime <= hi }
        }

        if !selectedHistoryLocations.isEmpty {
            sessions = sessions.filter { selectedHistoryLocations.contains($0.casino) }
        }

        if !selectedHistoryGames.isEmpty {
            sessions = sessions.filter { selectedHistoryGames.contains($0.game) }
        }

        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSearch.isEmpty {
            sessions = sessions.filter { session in
                session.casino.localizedCaseInsensitiveContains(trimmedSearch) ||
                session.game.localizedCaseInsensitiveContains(trimmedSearch)
            }
        }

        if includeTierPointsVerification {
            sessions = sessions.filter { $0.effectiveTierPointsVerification == historyTierPointsFilter }
        }

        if isTaxPrepFlowActive {
            sessions = sessions.filter { session in
                let yStart = Calendar.current.component(.year, from: session.startTime)
                if yStart == selectedTaxYear { return true }
                if let end = session.endTime {
                    return Calendar.current.component(.year, from: end) == selectedTaxYear
                }
                return false
            }
            if selectedTaxState != TaxPrepGeography.allStatesLabel {
                sessions = sessions.filter { sessionMatchesTaxStateFilter($0) }
            }
        }

        return sessions
    }

    private var availableCasinos: [String] {
        Array(Set(store.sessions.map { $0.casino })).sorted()
    }

    private var availableGames: [String] {
        Array(Set(store.sessions.map { $0.game })).sorted()
    }

    /// Every calendar year that appears on any session (start or end time).
    private var sessionTaxYears: [Int] {
        var years = Set<Int>()
        for s in store.sessions {
            years.insert(Calendar.current.component(.year, from: s.startTime))
            if let end = s.endTime {
                years.insert(Calendar.current.component(.year, from: end))
            }
        }
        return years.sorted(by: >)
    }

    /// Stable token so we can re-clamp the tax year when session dates change without relying on `Session` equality.
    private var sessionTaxYearChangeToken: String {
        "\(store.sessions.count)-\(sessionTaxYears.map(String.init).joined(separator: ","))"
    }

    private var historyFiltersActive: Bool {
        useDateRangeFilter || !selectedHistoryGames.isEmpty || !selectedHistoryLocations.isEmpty ||
            !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func clearHistoryFilters() {
        useDateRangeFilter = false
        filterStartDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date().addingTimeInterval(-30 * 24 * 60 * 60)
        filterEndDate = Date()
        selectedHistoryGames.removeAll()
        selectedHistoryLocations.removeAll()
        searchText = ""
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 52))
                .foregroundColor(.gray)
            L10nText("No Sessions Yet")
                .font(.title3)
                .foregroundColor(.gray)
            L10nText("Complete a session to see your history.")
                .font(.subheadline)
                .foregroundColor(.gray.opacity(0.7))
        }
    }

    private var historyStickyFilterBubble: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isFilterPanelExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundColor(.white)
                    VStack(alignment: .leading, spacing: 2) {
                        L10nText("Filters")
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                        Text(historyFiltersActive ? "Showing filtered sessions" : "All sessions")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.72))
                    }
                    Spacer()
                    if historyFiltersActive {
                        L10nText("Active")
                            .font(.caption2.bold())
                            .foregroundColor(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.2))
                            .clipShape(Capsule())
                    }
                    Image(systemName: isFilterPanelExpanded ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            if isFilterPanelExpanded {
                Divider()
                    .background(Color.white.opacity(0.14))
                    .padding(.horizontal, 12)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.white.opacity(0.7))
                        TextField("Search by casino or game", text: $searchText)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .foregroundColor(.white)
                    }
                    .padding(10)
                    .background(Color.black.opacity(0.22))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    historyDateRangeSection

                    if !availableGames.isEmpty {
                        historyGameBubblesSection
                    }

                    if !availableCasinos.isEmpty {
                        historyLocationBubblesSection
                    }

                    HStack {
                        Spacer()
                        FilterPanelPillButton(title: "Clear Filter") {
                            clearHistoryFilters()
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .padding(.top, 10)
            }
        }
        .background(Color.black.opacity(0.28))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var historyTierPointsVerificationSegment: some View {
        VStack(alignment: .leading, spacing: 6) {
            L10nText("Tier points")
                .font(.caption.bold())
                .foregroundColor(.white.opacity(0.85))
            Picker("", selection: $historyTierPointsFilter) {
                Text("Verified").tag(SessionTierPointsVerification.verified)
                Text("Unverified").tag(SessionTierPointsVerification.unverified)
            }
            .pickerStyle(.segmented)
            .tint(.green)
        }
        .padding(.horizontal)
        .padding(.top, 10)
    }

    private var historyTabSegment: some View {
        Picker("", selection: $selectedHistoryTab) {
            Text("Sessions").tag(HistoryPanelTab.sessions)
            Text("Tools").tag(HistoryPanelTab.tools)
        }
        .pickerStyle(.segmented)
        .tint(.green)
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var historyDateRangeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation { isHistoryDateSectionExpanded.toggle() }
            } label: {
                HStack {
                    LocalizedLabel(title: "Date & time range", systemImage: "calendar")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                    Spacer()
                    if useDateRangeFilter {
                        L10nText("On")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                    Image(systemName: isHistoryDateSectionExpanded ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .buttonStyle(.plain)

            if isHistoryDateSectionExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $useDateRangeFilter) {
                        L10nText("Limit to date range")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .tint(.green)

                    if useDateRangeFilter {
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                L10nText("From")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.8))
                                DatePicker(
                                    "",
                                    selection: $filterStartDate.datePortion(),
                                    displayedComponents: .date
                                )
                                .datePickerStyle(.compact)
                                .labelsHidden()
                                .tint(.white)
                                .font(.caption2)
                                DatePicker(
                                    "",
                                    selection: $filterStartDate.timePortion(),
                                    displayedComponents: .hourAndMinute
                                )
                                .datePickerStyle(.compact)
                                .labelsHidden()
                                .tint(.white)
                                .font(.caption2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Rectangle()
                                .fill(Color.white.opacity(0.22))
                                .frame(width: 1)
                                .padding(.vertical, 4)

                            VStack(alignment: .leading, spacing: 4) {
                                L10nText("To")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.8))
                                DatePicker(
                                    "",
                                    selection: $filterEndDate.datePortion(),
                                    displayedComponents: .date
                                )
                                .datePickerStyle(.compact)
                                .labelsHidden()
                                .tint(.white)
                                .font(.caption2)
                                DatePicker(
                                    "",
                                    selection: $filterEndDate.timePortion(),
                                    displayedComponents: .hourAndMinute
                                )
                                .datePickerStyle(.compact)
                                .labelsHidden()
                                .tint(.white)
                                .font(.caption2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

    private var historyGameBubblesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation { isHistoryGameSectionExpanded.toggle() }
            } label: {
                HStack {
                    LocalizedLabel(title: "Games", systemImage: "suit.club.fill")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                    Spacer()
                    if !selectedHistoryGames.isEmpty {
                        Text("\(selectedHistoryGames.count) selected")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                    Image(systemName: isHistoryGameSectionExpanded ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .buttonStyle(.plain)

            if isHistoryGameSectionExpanded {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(availableGames, id: \.self) { game in
                            let isSelected = selectedHistoryGames.contains(game)
                            Button {
                                if isSelected {
                                    selectedHistoryGames.remove(game)
                                } else {
                                    selectedHistoryGames.insert(game)
                                }
                            } label: {
                                Text(game)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(isSelected ? Color.green : Color.white.opacity(0.18))
                                    .foregroundColor(isSelected ? .black : .white)
                                    .cornerRadius(16)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var historyLocationBubblesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation { isHistoryLocationSectionExpanded.toggle() }
            } label: {
                HStack {
                    LocalizedLabel(title: "Locations", systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                    Spacer()
                    if !selectedHistoryLocations.isEmpty {
                        Text("\(selectedHistoryLocations.count) selected")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                    Image(systemName: isHistoryLocationSectionExpanded ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .buttonStyle(.plain)

            if isHistoryLocationSectionExpanded {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(availableCasinos, id: \.self) { location in
                            let isSelected = selectedHistoryLocations.contains(location)
                            Button {
                                if isSelected {
                                    selectedHistoryLocations.remove(location)
                                } else {
                                    selectedHistoryLocations.insert(location)
                                }
                            } label: {
                                Text(location)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(isSelected ? Color.green : Color.white.opacity(0.18))
                                    .foregroundColor(isSelected ? .black : .white)
                                    .cornerRadius(16)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var sessionListContent: some View {
        if filteredSessions.isEmpty {
            VStack(spacing: 8) {
                L10nText("No sessions match your filters.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                L10nText("Try adjusting filters or search.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.top, 24)
            Spacer()
        } else {
            List {
                ForEach(filteredSessions) { session in
                    SessionRow(session: session)
                        .onTapGesture { selectedSession = session }
                        .listRowBackground(Color(.systemGray6).opacity(0.15))
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button { sessionToEdit = session } label: {
                                LocalizedLabel(title: "Edit", systemImage: "pencil")
                            }
                            .tint(.green)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { sessionToDelete = session } label: {
                                LocalizedLabel(title: "Delete", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private var historyContentView: some View {
        VStack(spacing: 0) {
            historyTabSegment
            if selectedHistoryTab == .sessions {
                historyStickyFilterBubble
                historyTierPointsVerificationSegment
                if isTaxPrepFlowActive {
                    taxPrepFilterPanel
                }
                sessionListContent
                    .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            } else {
                historyToolsContent
            }
        }
    }

    private var historyToolsContent: some View {
        VStack(spacing: 16) {
            ThreeEqualSquaresRow(spacing: 6) {
                historyToolButton(
                    title: "Share Sessions",
                    systemImage: "square.and.arrow.up",
                    tint: .green,
                    isDisabled: sessionsMatchingHistoryBulkFilters.isEmpty
                ) {
                    if settingsStore.enableCasinoFeedback {
                        CelebrationPlayer.shared.playQuickChime()
                    }
                    isShareSelectorPresented = true
                }

                historyToolButton(
                    title: "Delete Sessions",
                    systemImage: "trash",
                    tint: .red,
                    isDisabled: store.sessions.isEmpty
                ) {
                    if settingsStore.enableCasinoFeedback {
                        CelebrationPlayer.shared.playQuickChime()
                    }
                    isDeleteSelectorPresented = true
                }

                historyToolButton(
                    title: "Tax Prep",
                    systemImage: "doc.text.magnifyingglass",
                    tint: .white,
                    isDisabled: false
                ) {
                    if settingsStore.enableCasinoFeedback {
                        CelebrationPlayer.shared.playQuickChime()
                    }
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                        taxPrepComingSoonVisible = true
                    }
                }
            }
            .frame(maxWidth: .infinity)

            Spacer()
        }
        .padding(.horizontal, 0)
        .padding(.top, 14)
    }

    private func dismissTaxPrepComingSoonOverlay() {
        withAnimation(.easeOut(duration: 0.28)) {
            taxPrepComingSoonVisible = false
        }
    }

    /// Full-screen dimmed backdrop with a large centered “bubble” for the Tax Prep placeholder.
    private var taxPrepComingSoonOverlay: some View {
        ZStack {
            Color.black.opacity(0.52)
                .ignoresSafeArea()
                .onTapGesture { dismissTaxPrepComingSoonOverlay() }

            VStack(spacing: 18) {
                TimelineView(.animation(minimumInterval: 1 / 30, paused: false)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let pulse = 0.62 + 0.38 * (0.5 + 0.5 * sin(t * 3.8))
                    Text("Feature Coming Soon....")
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(pulse))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.65)
                        .lineLimit(3)
                }

                Text("Tap outside to close")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.72))
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 44)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.34),
                        Color.white.opacity(0.16)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1.5)
            )
            .shadow(color: .black.opacity(0.45), radius: 28, x: 0, y: 14)
            .padding(.horizontal, 22)
        }
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }

    private func historyToolButton(title: String, systemImage: String, tint: Color, isDisabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.title2.weight(.bold))
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.26),
                        Color.white.opacity(0.14)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .foregroundColor(isDisabled ? .gray : tint)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.22), radius: 6, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private var taxPrepFilterPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                L10nText("Tax Prep Filters")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Button("Exit") {
                    isTaxPrepFlowActive = false
                    isTaxPrepGenerating = false
                    taxPrepProgress = 0
                    taxPrepStatusMessage = nil
                }
                .foregroundColor(.green)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    L10nText("Tax Year")
                        .font(.caption.bold())
                        .foregroundColor(.white.opacity(0.85))
                    Picker(selection: $selectedTaxYear) {
                        ForEach(sessionTaxYears, id: \.self) { year in
                            Text(verbatim: String(year)).tag(year)
                        }
                    } label: {
                        Text(verbatim: String(selectedTaxYear))
                            .foregroundColor(.white)
                    }
                    .pickerStyle(.menu)
                    .tint(.white)
                    .accessibilityLabel("Tax Year")
                }

                VStack(alignment: .leading, spacing: 6) {
                    L10nText("State")
                        .font(.caption.bold())
                        .foregroundColor(.white.opacity(0.85))
                    Picker("State", selection: $selectedTaxState) {
                        Text(TaxPrepGeography.allStatesLabel).tag(TaxPrepGeography.allStatesLabel)
                        ForEach(TaxPrepGeography.sortedUSStatePickerRows, id: \.code) { row in
                            Text("\(row.name) (\(row.code))").tag(row.code)
                        }
                        Text(TaxPrepGeography.internationalLabel).tag(TaxPrepGeography.internationalLabel)
                    }
                    .pickerStyle(.menu)
                    .tint(.white)
                }
            }

            Button {
                startTaxPrepGeneration()
            } label: {
                Text("Continue with Tax Prep")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.green.opacity(0.9))
                    .foregroundColor(.black)
                    .cornerRadius(12)
            }
            .disabled(filteredSessions.isEmpty || isTaxPrepGenerating)

            if isTaxPrepGenerating {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: taxPrepProgress)
                        .tint(.green)
                    Text("Generating tax prep document... \(Int(taxPrepProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                }
            }

            if let status = taxPrepStatusMessage {
                Text(status)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.9))
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.26))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .padding(.horizontal)
        .padding(.top, 10)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                if store.sessions.isEmpty {
                    emptyStateView
                } else {
                    historyContentView
                }

                if taxPrepComingSoonVisible {
                    taxPrepComingSoonOverlay
                        .zIndex(2)
                }
            }
            .localizedNavigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.green)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        NotificationCenter.default.post(name: NSNotification.Name("ShowAccountSheet"), object: nil)
                    } label: {
                        HStack(spacing: 6) {
                            if authStore.isSignedIn,
                               let uiImage = authStore.localProfilePhotoImage {
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
                                if authStore.localProfilePhotoImage == nil,
                                   let emojis = authStore.userProfileEmojis,
                                   !emojis.isEmpty {
                                    Text(emojis)
                                        .font(.caption)
                                }
                                Text(authStore.signedInSummary ?? authStore.userEmail ?? "Account")
                                    .lineLimit(1)
                                    .font(.caption)
                            } else {
                                L10nText("Account")
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
            .adaptiveSheet(item: $selectedSession) {
                SessionDetailView(session: $0)
                    .environmentObject(store)
                    .environmentObject(settingsStore)
                    .environmentObject(rewardWalletStore)
                    .environmentObject(subscriptionStore)
                    .environmentObject(authStore)
            }
            .adaptiveSheet(item: $sessionToEdit) { s in
                EditSessionView(session: s)
                    .environmentObject(store)
                    .environmentObject(settingsStore)
                    .environmentObject(subscriptionStore)
                    .environmentObject(authStore)
            }
            .adaptiveSheet(isPresented: $isDeleteSelectorPresented) {
                SessionDeleteSelectionView(sessions: store.sessions) { selectedSessionIDs in
                    store.deleteSessions(withIDs: selectedSessionIDs)
                }
                .environmentObject(settingsStore)
            }
            .alert("Delete Session?", isPresented: showDeleteAlert) {
                Button("Cancel", role: .cancel) { sessionToDelete = nil }
                Button("Delete", role: .destructive) {
                    if let s = sessionToDelete {
                        store.deleteSession(s)
                        sessionToDelete = nil
                    }
                }
            } message: {
                L10nText("This session will be permanently removed. This cannot be undone.")
            }
            .adaptiveSheet(isPresented: $isShareSelectorPresented) {
                SessionShareSelectionView(
                    sessions: sessionsMatchingHistoryBulkFilters,
                    photoOptions: { sessionSharePhotoOptions(for: $0) }
                ) { selected, shareAsPhoto, includeWinLosses, photoBase in
                    guard !selected.isEmpty else { return }
                    pendingShareItems = createShareItems(
                        for: selected,
                        shareAsPhoto: shareAsPhoto,
                        includeWinLosses: includeWinLosses,
                        photoBase: photoBase
                    )
                }
                .environmentObject(settingsStore)
            }
            .onChange(of: isShareSelectorPresented) { newValue in
                if !newValue, let items = pendingShareItems, !items.isEmpty {
                    shareItems = items
                    #if os(iOS)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        isShareSheetPresented = true
                    }
                    #endif
                }
            }
            .adaptiveSheet(isPresented: $isShareSheetPresented) {
                #if os(iOS)
                if !shareItems.isEmpty {
                    ShareSheet(items: shareItems)
                } else {
                    EmptyView()
                }
                #endif
            }
            .onChange(of: isShareSheetPresented) { newValue in
                if !newValue {
                    shareItems = []
                    pendingShareItems = nil
                }
            }
            .onAppear {
                clampTaxYearSelectionIfNeeded()
            }
            .onChange(of: sessionTaxYearChangeToken) { _ in
                clampTaxYearSelectionIfNeeded()
            }
        }
    }

    /// When a specific U.S. state is selected, match sessions whose trailing ", XX" parses to that code. International = non‑U.S. or unknown.
    private func sessionMatchesTaxStateFilter(_ session: Session) -> Bool {
        switch selectedTaxState {
        case TaxPrepGeography.allStatesLabel:
            return true
        case TaxPrepGeography.internationalLabel:
            guard let code = inferredTwoLetterStateCode(for: session) else { return true }
            return !TaxPrepGeography.usStateCodeSet.contains(code)
        default:
            return inferredTwoLetterStateCode(for: session) == selectedTaxState
        }
    }
}

extension HistoryView {
    fileprivate func inferredTwoLetterStateCode(for session: Session) -> String? {
        let casino = session.casino.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !casino.isEmpty else { return nil }
        let parts = casino.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let last = parts.last, !last.isEmpty else { return nil }
        if last.count == 2 {
            return last.uppercased()
        }
        return nil
    }

    fileprivate func clampTaxYearSelectionIfNeeded() {
        let years = sessionTaxYears
        guard !years.isEmpty else { return }
        if !years.contains(selectedTaxYear) {
            selectedTaxYear = years[0]
        }
    }

    fileprivate func startTaxPrepGeneration() {
        guard !filteredSessions.isEmpty else { return }
        isTaxPrepGenerating = true
        taxPrepProgress = 0
        taxPrepStatusMessage = nil

        Task {
            for step in 1...20 {
                try? await Task.sleep(nanoseconds: 90_000_000)
                await MainActor.run {
                    taxPrepProgress = Double(step) / 20.0
                }
            }
            await MainActor.run {
                isTaxPrepGenerating = false
                // Placeholder: actual tax document generation is intentionally left blank.
                taxPrepStatusMessage = "Tax prep document generation is ready to implement."
            }
        }
    }

    /// Labels and sources for shareable photos: session chip image plus any comp receipt images on disk.
    fileprivate func sessionSharePhotoOptions(for session: Session) -> [(label: String, base: SessionSharePhotoBase)] {
        var out: [(String, SessionSharePhotoBase)] = []
        if let fileName = session.chipEstimatorImageFilename,
           let url = ChipEstimatorPhotoStorage.url(for: fileName),
           FileManager.default.fileExists(atPath: url.path) {
            out.append(("Session photo", .sessionChip))
        }
        for ev in session.compEvents {
            guard let url = CompPhotoStorage.url(for: ev.id),
                  FileManager.default.fileExists(atPath: url.path) else { continue }
            let kind = ev.kind.title
            let amt = "\(settingsStore.currencySymbol)\(ev.amount)"
            let time = ev.timestamp.formatted(date: .omitted, time: .shortened)
            out.append(("Comp · \(kind) · \(amt) · \(time)", .comp(ev.id)))
        }
        return out
    }

    private func createShareItems(for sessions: [Session], shareAsPhoto: Bool, includeWinLosses: Bool, photoBase: SessionSharePhotoBase?) -> [Any] {
        #if os(iOS)
        if shareAsPhoto, let image = sharePhoto(for: sessions, includeWinLosses: includeWinLosses, photoBase: photoBase) {
            return [image]
        }
        #endif

        let message = SessionShareFormatter.combinedMessage(
            for: sessions,
            currencySymbol: settingsStore.currencySymbol,
            includeWinLoss: includeWinLosses
        )
        return [message]
    }

    #if os(iOS)
    /// When the user did not pick a specific image, prefer session chip in session order, then first comp photo on disk.
    private func defaultSharePhotoBase(for sessions: [Session]) -> (session: Session, base: SessionSharePhotoBase)? {
        for s in sessions {
            if let fn = s.chipEstimatorImageFilename,
               let url = ChipEstimatorPhotoStorage.url(for: fn),
               FileManager.default.fileExists(atPath: url.path) {
                return (s, .sessionChip)
            }
        }
        for s in sessions {
            for ev in s.compEvents {
                guard let url = CompPhotoStorage.url(for: ev.id),
                      FileManager.default.fileExists(atPath: url.path) else { continue }
                return (s, .comp(ev.id))
            }
        }
        return nil
    }

    private func loadShareBaseImage(session: Session, base: SessionSharePhotoBase) -> UIImage? {
        switch base {
        case .sessionChip:
            guard let fileName = session.chipEstimatorImageFilename,
                  let url = ChipEstimatorPhotoStorage.url(for: fileName) else { return nil }
            return UIImage(contentsOfFile: url.path)
        case .comp(let id):
            guard let url = CompPhotoStorage.url(for: id) else { return nil }
            return UIImage(contentsOfFile: url.path)
        }
    }

    private func sharePhoto(for sessions: [Session], includeWinLosses: Bool, photoBase: SessionSharePhotoBase?) -> UIImage? {
        let session: Session
        let base: SessionSharePhotoBase

        if let picked = photoBase, let s = sessions.first {
            session = s
            base = picked
        } else if let pair = defaultSharePhotoBase(for: sessions) {
            session = pair.session
            base = pair.base
        } else {
            return nil
        }

        guard let baseImage = loadShareBaseImage(session: session, base: base) else {
            return nil
        }

        let scale = baseImage.scale
        let size = baseImage.size
        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = scale
        rendererFormat.opaque = false

        let renderer = UIGraphicsImageRenderer(size: size, format: rendererFormat)

        let image = renderer.image { ctx in
            // Draw base image
            baseImage.draw(in: CGRect(origin: .zero, size: size))

            // Overlay gradient at bottom
            let overlayHeight = size.height * 0.32
            let overlayRect = CGRect(
                x: 0,
                y: size.height - overlayHeight,
                width: size.width,
                height: overlayHeight
            )

            ctx.cgContext.setFillColor(UIColor.black.withAlphaComponent(0.6).cgColor)
            ctx.cgContext.fill(overlayRect)

            // Prepare text
            let inset: CGFloat = size.width * 0.06
            let textRect = overlayRect.insetBy(dx: inset, dy: inset * 0.7)

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .left

            let titleFont = UIFont.boldSystemFont(ofSize: min(size.width, size.height) * 0.065)
            let subtitleFont = UIFont.systemFont(ofSize: min(size.width, size.height) * 0.045, weight: .medium)
            let bodyFont = UIFont.systemFont(ofSize: min(size.width, size.height) * 0.04)

            var lines: [NSAttributedString] = []

            // Line 1: casino / game
            let title = "\(session.casino) · \(session.game)"
            lines.append(NSAttributedString(
                string: title,
                attributes: [
                    .font: titleFont,
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: paragraph
                ]
            ))

            // Line 2: date & duration
            let dateString = SessionShareFormatter.dateFormatter.string(from: session.startTime)
            let durationString = Session.durationString(session.duration)
            let subtitle = "\(dateString) • \(durationString)"
            lines.append(NSAttributedString(
                string: subtitle,
                attributes: [
                    .font: subtitleFont,
                    .foregroundColor: UIColor(white: 0.9, alpha: 1.0),
                    .paragraphStyle: paragraph
                ]
            ))

            // Line 3: primary stats (buy-in / cash / result / tier)
            var statsParts: [String] = []

            if includeWinLosses {
                let buyInText = "\(settingsStore.currencySymbol)\(session.totalBuyIn)"
                statsParts.append("Buy-In \(buyInText)")
                if let cashOut = session.cashOut {
                    let cashOutText = "\(settingsStore.currencySymbol)\(cashOut)"
                    statsParts.append("Cash-Out \(cashOutText)")
                }
                if let wl = session.winLoss {
                    let sign = wl >= 0 ? "+" : "-"
                    let wlText = "\(settingsStore.currencySymbol)\(abs(wl))"
                    statsParts.append("Result \(sign)\(wlText)")
                }
            }

            if let points = session.tierPointsEarned {
                let ptsText = "\(points >= 0 ? "+" : "")\(points) pts"
                statsParts.append(ptsText)
            }

            if let tph = session.tiersPerHour {
                let tphText = String(format: "%.1f pts/hr", tph)
                statsParts.append(tphText)
            }

            if !statsParts.isEmpty {
                let statsLine = statsParts.joined(separator: "   •   ")
                lines.append(NSAttributedString(
                    string: statsLine,
                    attributes: [
                        .font: bodyFont,
                        .foregroundColor: UIColor(white: 0.9, alpha: 1.0),
                        .paragraphStyle: paragraph
                    ]
                ))
            }

            // Line 4: comps + EV on their own row so they are not clipped when the primary stats line is long.
            var compsEvParts: [String] = []
            if !session.compEvents.isEmpty {
                if session.totalComp > 0 {
                    let c = "\(settingsStore.currencySymbol)\(session.totalComp)"
                    compsEvParts.append("Comps \(c)")
                } else {
                    let n = session.compEvents.count
                    compsEvParts.append(n == 1 ? "1 comp" : "\(n) comps")
                }
            }
            if includeWinLosses, session.totalComp > 0, let ev = session.expectedValue {
                let sign = ev >= 0 ? "+" : "-"
                let evText = "\(settingsStore.currencySymbol)\(abs(ev))"
                compsEvParts.append("EV \(sign)\(evText)")
            }

            if !compsEvParts.isEmpty {
                let compsEvLine = compsEvParts.joined(separator: "   •   ")
                lines.append(NSAttributedString(
                    string: compsEvLine,
                    attributes: [
                        .font: bodyFont,
                        .foregroundColor: UIColor(white: 0.9, alpha: 1.0),
                        .paragraphStyle: paragraph
                    ]
                ))
            }

            // Draw lines vertically
            var currentY = textRect.minY
            for (index, line) in lines.enumerated() {
                let lineHeight = (index == 0 ? titleFont.lineHeight : bodyFont.lineHeight) * 1.1
                let lineRect = CGRect(
                    x: textRect.minX,
                    y: currentY,
                    width: textRect.width,
                    height: lineHeight
                )
                line.draw(in: lineRect)
                currentY += lineHeight
            }
        }

        return image
    }
    #endif
}

struct SessionRow: View {
    let session: Session
    @EnvironmentObject var settingsStore: SettingsStore
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(session.casino).font(.headline).foregroundColor(.white)
                if session.requiresMoreInfo {
                    L10nText("Incomplete")
                        .font(.caption2.bold())
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.25))
                        .cornerRadius(4)
                }
                if session.effectiveTierPointsVerification == .unverified {
                    Text("Unverified")
                        .font(.caption2.bold())
                        .foregroundColor(.yellow.opacity(0.95))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.yellow.opacity(0.18))
                        .cornerRadius(4)
                }
                Spacer()
                if let e = session.tierPointsEarned {
                    Text("\(e >= 0 ? "+" : "")\(e) pts")
                        .font(.subheadline.bold())
                        .foregroundColor(e >= 0 ? .green : .orange)
                }
            }
            HStack {
                Text(session.game).font(.subheadline).foregroundColor(.gray)
                Spacer()
                Text(session.startTime, style: .date).font(.caption).foregroundColor(.gray)
            }
            HStack {
                Text(Session.durationString(session.duration))
                    .font(.caption).foregroundColor(.gray)
                Spacer()
                if let t = session.tiersPerHour {
                    Text(String(format: "%.1f pts/hr", t))
                        .font(.caption).foregroundColor(.gray)
                }
                if let wl = session.winLoss {
                    Text(wl >= 0 ? "+\(settingsStore.currencySymbol)\(wl)" : "-\(settingsStore.currencySymbol)\(abs(wl))")
                        .font(.caption.bold())
                        .foregroundColor(wl >= 0 ? .green : .red)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct SessionShareSelectionView: View {
    let sessions: [Session]
    /// Returns labeled share backgrounds for the session (session photo + comp receipt images on disk).
    let photoOptions: (Session) -> [(label: String, base: SessionSharePhotoBase)]
    let onShare: (_ sessions: [Session], _ shareAsPhoto: Bool, _ includeWinLosses: Bool, _ photoBase: SessionSharePhotoBase?) -> Void

    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSessionIDs: Set<UUID> = []
    @State private var shareAsPhoto: Bool = false
    @State private var includeWinLosses: Bool = true
    @State private var showPhotoBasePicker = false
    @State private var photoPickerSession: Session?
    @State private var photoPickerOptions: [(label: String, base: SessionSharePhotoBase)] = []

    private var allSelected: Bool {
        !sessions.isEmpty && selectedSessionIDs.count == sessions.count
    }

    private var sortedSessions: [Session] {
        sessions.sorted { $0.startTime > $1.startTime }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                if sessions.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        L10nText("No sessions available to share.")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                } else {
                    List {
                        Section {
                            HStack {
                                Button {
                                    selectedSessionIDs = Set(sessions.map { $0.id })
                                } label: {
                                    HStack {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                        L10nText("Select All Sessions")
                                            .foregroundColor(.white)
                                    }
                                }

                                Spacer()

                                Button {
                                    selectedSessionIDs.removeAll()
                                } label: {
                                    HStack {
                                        Image(systemName: "xmark.circle")
                                            .foregroundColor(.red)
                                        L10nText("Clear All")
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color(.systemGray6).opacity(0.2))
                        }

                        Section(header: L10nText("Choose sessions to share").foregroundColor(.gray)) {
                            Toggle(isOn: $shareAsPhoto) {
                                L10nText("Photo")
                                    .foregroundColor(.white)
                            }
                            .toggleStyle(SwitchToggleStyle(tint: .green))
                            .listRowBackground(Color(.systemGray6).opacity(0.15))

                            Toggle(isOn: $includeWinLosses) {
                                L10nText("Include win/losses")
                                    .foregroundColor(.white)
                            }
                            .toggleStyle(SwitchToggleStyle(tint: .green))
                            .listRowBackground(Color(.systemGray6).opacity(0.15))

                            ForEach(sortedSessions) { session in
                                SessionSelectableRow(
                                    session: session,
                                    isSelected: selectedSessionIDs.contains(session.id)
                                ) {
                                    toggleSelection(for: session)
                                }
                                .listRowBackground(Color(.systemGray6).opacity(0.15))
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .localizedNavigationTitle("Share Sessions")
            .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.green)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Share") {
                        shareTapped()
                    }
                    .foregroundColor(selectedSessionIDs.isEmpty ? .gray : .green)
                    .disabled(selectedSessionIDs.isEmpty)
                }
            }
            .adaptiveSheet(isPresented: $showPhotoBasePicker) {
                if let s = photoPickerSession {
                    SessionSharePhotoBasePickerSheet(
                        casinoLine: "\(s.casino) · \(s.game)",
                        options: photoPickerOptions
                    ) { base in
                        if settingsStore.enableCasinoFeedback {
                            CelebrationPlayer.shared.playQuickChime()
                        }
                        onShare([s], true, includeWinLosses, base)
                        showPhotoBasePicker = false
                        photoPickerSession = nil
                        photoPickerOptions = []
                        dismiss()
                    }
                    .environmentObject(settingsStore)
                }
            }
            .onChange(of: showPhotoBasePicker) { isShowing in
                if !isShowing {
                    photoPickerSession = nil
                    photoPickerOptions = []
                }
            }
        }
    }

    private func shareTapped() {
        let chosen = sortedSessions.filter { selectedSessionIDs.contains($0.id) }
        guard !chosen.isEmpty else { return }

        if !shareAsPhoto {
            if settingsStore.enableCasinoFeedback {
                CelebrationPlayer.shared.playQuickChime()
            }
            onShare(chosen, false, includeWinLosses, nil)
            dismiss()
            return
        }

        // Photo share: if exactly one session has multiple candidate images, pick which to use first.
        if chosen.count == 1, let session = chosen.first {
            let opts = photoOptions(session)
            if opts.count > 1 {
                photoPickerSession = session
                photoPickerOptions = opts
                showPhotoBasePicker = true
                return
            }
            if settingsStore.enableCasinoFeedback {
                CelebrationPlayer.shared.playQuickChime()
            }
            let singleBase = opts.first?.base
            onShare(chosen, true, includeWinLosses, singleBase)
            dismiss()
            return
        }

        if settingsStore.enableCasinoFeedback {
            CelebrationPlayer.shared.playQuickChime()
        }
        onShare(chosen, true, includeWinLosses, nil)
        dismiss()
    }

    private func toggleSelection(for session: Session) {
        if selectedSessionIDs.contains(session.id) {
            selectedSessionIDs.remove(session.id)
        } else {
            selectedSessionIDs.insert(session.id)
        }
    }
}

/// Lets the user pick session chip vs. comp receipt when more than one image exists for the share overlay.
private struct SessionSharePhotoBasePickerSheet: View {
    let casinoLine: String
    let options: [(label: String, base: SessionSharePhotoBase)]
    let onPick: (SessionSharePhotoBase) -> Void

    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                List {
                    Section {
                        Text(casinoLine)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white.opacity(0.95))
                            .listRowBackground(Color(.systemGray6).opacity(0.12))
                        L10nText("Metrics will be drawn on the image you choose.")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .listRowBackground(Color(.systemGray6).opacity(0.12))
                    }

                    Section(header: L10nText("Background image").foregroundColor(.gray)) {
                        ForEach(Array(options.enumerated()), id: \.offset) { _, item in
                            Button {
                                onPick(item.base)
                            } label: {
                                HStack(alignment: .top) {
                                    Text(item.label)
                                        .foregroundColor(.white)
                                        .multilineTextAlignment(.leading)
                                    Spacer()
                                    Image(systemName: "photo.on.rectangle.angled")
                                        .foregroundColor(.green.opacity(0.85))
                                }
                            }
                            .listRowBackground(Color(.systemGray6).opacity(0.15))
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .localizedNavigationTitle("Choose photo")
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
            }
        }
    }
}

private struct SessionSelectableRow: View {
    let session: Session
    let isSelected: Bool
    let onToggle: () -> Void

    @EnvironmentObject var settingsStore: SettingsStore

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .green : .gray)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(session.casino)
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                        Spacer()
                        if let wl = session.winLoss {
                            Text(wl >= 0 ? "+\(settingsStore.currencySymbol)\(wl)" : "-\(settingsStore.currencySymbol)\(abs(wl))")
                                .font(.caption.bold())
                                .foregroundColor(wl >= 0 ? .green : .red)
                        }
                    }
                    HStack(spacing: 6) {
                        Text(session.game)
                            .font(.caption)
                            .foregroundColor(.gray)
                        L10nText("•")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text(session.startTime, style: .date)
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct SessionDeleteSelectionView: View {
    let sessions: [Session]
    let onDelete: (Set<UUID>) -> Void

    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSessionIDs: Set<UUID> = []
    @State private var showDeleteConfirmationAlert = false

    private var sortedSessions: [Session] {
        sessions.sorted { $0.startTime > $1.startTime }
    }

    private var allSelected: Bool {
        !sortedSessions.isEmpty && selectedSessionIDs.count == sortedSessions.count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                if sortedSessions.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "trash.slash")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        L10nText("No sessions available to delete.")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                } else {
                    List {
                        Section {
                            HStack {
                                Button {
                                    selectedSessionIDs = Set(sortedSessions.map { $0.id })
                                } label: {
                                    HStack {
                                        Image(systemName: allSelected ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(.green)
                                        L10nText("Select All Sessions")
                                            .foregroundColor(.white)
                                    }
                                }

                                Spacer()

                                Button {
                                    selectedSessionIDs.removeAll()
                                } label: {
                                    HStack {
                                        Image(systemName: "xmark.circle")
                                            .foregroundColor(.red)
                                        L10nText("Clear All")
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color(.systemGray6).opacity(0.2))
                        }

                        Section(header: L10nText("Choose sessions to delete").foregroundColor(.gray)) {
                            ForEach(sortedSessions) { session in
                                SessionDeleteSelectableRow(
                                    session: session,
                                    isSelected: selectedSessionIDs.contains(session.id)
                                ) {
                                    toggleSelection(for: session)
                                }
                                .listRowBackground(Color(.systemGray6).opacity(0.15))
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .localizedNavigationTitle("Delete Sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.green)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Delete") {
                        showDeleteConfirmationAlert = true
                    }
                    .foregroundColor(selectedSessionIDs.isEmpty ? .gray : .red)
                    .disabled(selectedSessionIDs.isEmpty)
                }
            }
            .alert("Delete selected sessions?", isPresented: $showDeleteConfirmationAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    guard !selectedSessionIDs.isEmpty else { return }
                    onDelete(selectedSessionIDs)
                    dismiss()
                }
            } message: {
                let count = selectedSessionIDs.count
                Text("You are about to permanently delete \(count) session\(count == 1 ? "" : "s"). This cannot be undone.")
            }
        }
    }

    private func toggleSelection(for session: Session) {
        if selectedSessionIDs.contains(session.id) {
            selectedSessionIDs.remove(session.id)
        } else {
            selectedSessionIDs.insert(session.id)
        }
    }
}

private struct SessionDeleteSelectableRow: View {
    let session: Session
    let isSelected: Bool
    let onToggle: () -> Void

    @EnvironmentObject var settingsStore: SettingsStore

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .green : .gray)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(session.casino)
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                        Spacer()
                        if let wl = session.winLoss {
                            Text(wl >= 0 ? "+\(settingsStore.currencySymbol)\(wl)" : "-\(settingsStore.currencySymbol)\(abs(wl))")
                                .font(.caption.bold())
                                .foregroundColor(wl >= 0 ? .green : .red)
                        }
                    }
                    HStack(spacing: 6) {
                        Text(session.game)
                            .font(.caption)
                            .foregroundColor(.gray)
                        L10nText("•")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text(session.startTime, style: .date)
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

