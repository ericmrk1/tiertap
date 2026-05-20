import SwiftUI

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
    /// Single choice below Filters; legacy sessions without stored verification count as verified.
    @State private var historyTierPointsFilter: SessionTierPointsVerification = .verified
    @State private var showTaxPrep = false
    @State private var showPhotoFeed = false
    @State private var isToolsMenuPresented = false

    private var showDeleteAlert: Binding<Bool> {
        Binding(
            get: { sessionToDelete != nil },
            set: { if !$0 { sessionToDelete = nil } }
        )
    }

    /// Sessions for the scrolling list: date, location, game, search, and **tier-points segment**.
    private var filteredSessions: [Session] {
        sessionsApplyingHistoryFilters(includeTierPointsVerification: true)
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

        return sessions
    }

    private var availableCasinos: [String] {
        Array(Set(store.sessions.map { $0.casino })).sorted()
    }

    private var availableGames: [String] {
        Array(Set(store.sessions.map { $0.game })).sorted()
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

    private var historyToolsMenu: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                isToolsMenuPresented = false
                isDeleteSelectorPresented = true
            } label: {
                Label {
                    Text("Delete Sessions")
                } icon: {
                    Image(systemName: "trash")
                }
                .foregroundStyle(.green)
            }
            .buttonStyle(.plain)
            .disabled(store.sessions.isEmpty)

            Button {
                isToolsMenuPresented = false
                showTaxPrep = true
            } label: {
                Label {
                    Text("Tax Prep")
                } icon: {
                    Image(systemName: "doc.text.magnifyingglass")
                }
                .foregroundStyle(.green)
            }
            .buttonStyle(.plain)

            Button {
                isToolsMenuPresented = false
                showPhotoFeed = true
            } label: {
                Label {
                    Text("Photo Feed")
                } icon: {
                    Image(systemName: "photo.on.rectangle.angled")
                }
                .foregroundStyle(.green)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .frame(minWidth: 220, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .modifier(HistoryToolsMenuPresentation())
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
            historyStickyFilterBubble
            historyTierPointsVerificationSegment
            sessionListContent
                .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        }
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
            }
            .navigationDestination(isPresented: $showTaxPrep) {
                HistoryTaxPrepView()
                    .environmentObject(store)
                    .environmentObject(settingsStore)
                    .environmentObject(subscriptionStore)
                    .environmentObject(authStore)
            }
            .navigationDestination(isPresented: $showPhotoFeed) {
                HistoryPhotoFeedView()
                    .environmentObject(store)
                    .environmentObject(settingsStore)
                    .environmentObject(rewardWalletStore)
                    .environmentObject(subscriptionStore)
                    .environmentObject(authStore)
            }
            .navigationDestination(isPresented: $isDeleteSelectorPresented) {
                SessionDeleteSelectionView(sessions: store.sessions) { selectedSessionIDs in
                    store.deleteSessions(withIDs: selectedSessionIDs)
                }
                .environmentObject(settingsStore)
            }
            .localizedNavigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 14) {
                        Button {
                            isToolsMenuPresented = true
                        } label: {
                            Image(systemName: "wrench.and.screwdriver")
                                .font(.body.weight(.semibold))
                                .foregroundColor(.green)
                                .accessibilityLabel("Tools")
                        }
                        .popover(isPresented: $isToolsMenuPresented, arrowEdge: .top) {
                            historyToolsMenu
                        }

                        Button("Cancel") {
                            dismiss()
                        }
                        .foregroundColor(.green)
                    }
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
        }
    }
}

private struct HistoryToolsMenuPresentation: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content.presentationCompactAdaptation(.popover)
        } else {
            content
                .presentationDetents([.height(180)])
                .presentationDragIndicator(.hidden)
        }
    }
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

