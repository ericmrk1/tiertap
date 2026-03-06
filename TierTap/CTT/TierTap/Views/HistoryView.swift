import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSession: Session?
    @State private var sessionToEdit: Session?
    @State private var sessionToDelete: Session?
    @State private var searchText: String = ""
    @State private var selectedDate: Date?
    @State private var isCalendarExpanded: Bool = false
    @State private var isShareSelectorPresented: Bool = false
    @State private var isShareSheetPresented: Bool = false
    @State private var shareText: String = ""
    @State private var shareSummaryToPresent: String?
    #if os(iOS)
    @State private var shareFileURL: URL?
    #endif

    private var showDeleteAlert: Binding<Bool> {
        Binding(
            get: { sessionToDelete != nil },
            set: { if !$0 { sessionToDelete = nil } }
        )
    }

    private var filteredSessions: [Session] {
        var sessions = store.sessions

        if let filter = settingsStore.selectedLocationFilter, !filter.isEmpty {
            sessions = sessions.filter { $0.casino == filter }
        }

        if let selectedDate {
            sessions = sessions.filter { Calendar.current.isDate($0.startTime, inSameDayAs: selectedDate) }
        }

        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSearch.isEmpty {
            sessions = sessions.filter { session in
                session.casino.localizedCaseInsensitiveContains(trimmedSearch) ||
                session.game.localizedCaseInsensitiveContains(trimmedSearch)
            }
        }

        return sessions
    }

    private var availableCasinos: [String] {
        Array(Set(store.sessions.map { $0.casino })).sorted()
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 52))
                .foregroundColor(.gray)
            Text("No Sessions Yet")
                .font(.title3)
                .foregroundColor(.gray)
            Text("Complete a session to see your history.")
                .font(.subheadline)
                .foregroundColor(.gray.opacity(0.7))
        }
    }

    private var calendarSection: some View {
        DisclosureGroup(isExpanded: $isCalendarExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                SessionCalendarView(sessions: store.sessions, selectedDate: $selectedDate)
                HStack {
                    Button("Clear Date Filter") { selectedDate = nil }
                        .font(.caption)
                        .foregroundColor(.blue.opacity(0.9))
                    Spacer()
                }
            }
            .padding(.top, 4)
        } label: {
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Session Calendar")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                    if let selectedDate {
                        Text(selectedDate, style: .date)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    } else {
                        Text("Tap to pick a date")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                Spacer()
                Image(systemName: isCalendarExpanded ? "chevron.up" : "chevron.down")
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.25))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.white.opacity(0.7))
            TextField("Search by casino or game", text: $searchText)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .foregroundColor(.white)
        }
        .padding(10)
        .background(Color.black.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal)
    }

    @ViewBuilder
    private var locationFilterBar: some View {
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
                        locationFilterButton(title: "All", isSelected: settingsStore.selectedLocationFilter == nil || settingsStore.selectedLocationFilter?.isEmpty == true) {
                            settingsStore.selectedLocationFilter = nil
                        }
                        ForEach(availableCasinos, id: \.self) { casino in
                            locationFilterButton(title: casino, isSelected: settingsStore.selectedLocationFilter == casino) {
                                settingsStore.selectedLocationFilter = casino
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private func locationFilterButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? Color.green : Color(.systemGray6).opacity(0.25))
                .foregroundColor(isSelected ? .black : .white)
                .cornerRadius(8)
        }
    }

    @ViewBuilder
    private var sessionListContent: some View {
        if filteredSessions.isEmpty {
            VStack(spacing: 8) {
                Text("No sessions match your filters.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                Text("Try adjusting the search, date, or location filters.")
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
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.green)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { sessionToDelete = session } label: {
                                Label("Delete", systemImage: "trash")
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
        VStack(spacing: 8) {
            calendarSection
            searchBar
            locationFilterBar
            sessionListContent
        }
    }

    #if os(iOS)
    private func writeShareTextToFile(_ text: String) -> URL? {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMddHHmmss"
        let timestamp = df.string(from: Date())
        let name = "TierTap\(timestamp).txt"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        guard let data = text.data(using: .utf8) else { return nil }
        try? data.write(to: url)
        return url
    }
    #endif

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
            .navigationTitle("Session History")
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
                    if !filteredSessions.isEmpty {
                        Button {
                            isShareSelectorPresented = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.green)
                        }
                        .accessibilityLabel("Share sessions")
                    }
                }
            }
            .sheet(item: $selectedSession) { SessionDetailView(session: $0) }
            .sheet(item: $sessionToEdit) { s in
                EditSessionView(session: s)
                    .environmentObject(store)
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
                Text("This session will be permanently removed. This cannot be undone.")
            }
            .sheet(isPresented: $isShareSelectorPresented) {
                SessionShareSelectionView(sessions: filteredSessions) { selected in
                    guard !selected.isEmpty else { return }
                    shareSummaryToPresent = SessionShareFormatter.combinedMessage(for: selected)
                }
                .environmentObject(settingsStore)
            }
            .onChange(of: isShareSelectorPresented) { newValue in
                if !newValue, let summary = shareSummaryToPresent {
                    shareText = summary
                    #if os(iOS)
                    shareFileURL = writeShareTextToFile(summary)
                    if shareFileURL != nil {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            isShareSheetPresented = true
                        }
                    }
                    #endif
                }
            }
            .sheet(isPresented: $isShareSheetPresented) {
                #if os(iOS)
                if let url = shareFileURL {
                    ShareSheet(items: [url])
                } else {
                    EmptyView()
                }
                #endif
            }
            .onChange(of: isShareSheetPresented) { newValue in
                if !newValue {
                    #if os(iOS)
                    if let url = shareFileURL {
                        try? FileManager.default.removeItem(at: url)
                    }
                    shareFileURL = nil
                    #endif
                    shareText = ""
                    shareSummaryToPresent = nil
                }
            }
        }
    }
}

struct SessionRow: View {
    let session: Session
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(session.casino).font(.headline).foregroundColor(.white)
                if session.requiresMoreInfo {
                    Text("Incomplete")
                        .font(.caption2.bold())
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.25))
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
                    Text(wl >= 0 ? "+$\(wl)" : "-$\(abs(wl))")
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
    let onShare: ([Session]) -> Void

    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSessionIDs: Set<UUID> = []

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
                        Text("No sessions available to share.")
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
                                        Text("Select All Sessions")
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
                                        Text("Clear All")
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color(.systemGray6).opacity(0.2))
                        }

                        Section(header: Text("Choose sessions to share").foregroundColor(.gray)) {
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
            .navigationTitle("Share Sessions")
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
                        let chosen = sortedSessions.filter { selectedSessionIDs.contains($0.id) }
                        guard !chosen.isEmpty else { return }
                        onShare(chosen)
                        dismiss()
                    }
                    .foregroundColor(selectedSessionIDs.isEmpty ? .gray : .green)
                    .disabled(selectedSessionIDs.isEmpty)
                }
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

private struct SessionSelectableRow: View {
    let session: Session
    let isSelected: Bool
    let onToggle: () -> Void

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
                            Text(wl >= 0 ? "+$\(wl)" : "-$\(abs(wl))")
                                .font(.caption.bold())
                                .foregroundColor(wl >= 0 ? .green : .red)
                        }
                    }
                    HStack(spacing: 6) {
                        Text(session.game)
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text("•")
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

