import SwiftUI
import UIKit

/// Which local image to use as the background when sharing a session as a photo with metrics overlaid.
enum SessionSharePhotoBase: Equatable, Hashable {
    case sessionChip
    case comp(UUID)
}

struct HistoryView: View {
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var authStore: AuthStore
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSession: Session?
    @State private var sessionToEdit: Session?
    @State private var sessionToDelete: Session?
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

    private var showDeleteAlert: Binding<Bool> {
        Binding(
            get: { sessionToDelete != nil },
            set: { if !$0 { sessionToDelete = nil } }
        )
    }

    private var filteredSessions: [Session] {
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
                        Text("Filters")
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                        Text(historyFiltersActive ? "Showing filtered sessions" : "All sessions")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.72))
                    }
                    Spacer()
                    if historyFiltersActive {
                        Text("Active")
                            .font(.caption2.bold())
                            .foregroundColor(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.2))
                            .clipShape(Capsule())
                    }
                    Image(systemName: isFilterPanelExpanded ? "chevron.up" : "chevron.down")
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

    private var historyDateRangeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation { isHistoryDateSectionExpanded.toggle() }
            } label: {
                HStack {
                    Label("Date & time range", systemImage: "calendar")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                    Spacer()
                    if useDateRangeFilter {
                        Text("On")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                    Image(systemName: isHistoryDateSectionExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .buttonStyle(.plain)

            if isHistoryDateSectionExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $useDateRangeFilter) {
                        Text("Limit to date range")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .tint(.green)

                    if useDateRangeFilter {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("From")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                            DatePicker(
                                "",
                                selection: $filterStartDate,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .tint(.white)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("To")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                            DatePicker(
                                "",
                                selection: $filterEndDate,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .tint(.white)
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
                    Label("Games", systemImage: "suit.club.fill")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                    Spacer()
                    if !selectedHistoryGames.isEmpty {
                        Text("\(selectedHistoryGames.count) selected")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                    Image(systemName: isHistoryGameSectionExpanded ? "chevron.up" : "chevron.down")
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
                    Label("Locations", systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                    Spacer()
                    if !selectedHistoryLocations.isEmpty {
                        Text("\(selectedHistoryLocations.count) selected")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                    Image(systemName: isHistoryLocationSectionExpanded ? "chevron.up" : "chevron.down")
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
                Text("No sessions match your filters.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                Text("Try adjusting filters or search.")
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
        VStack(spacing: 0) {
            historyStickyFilterBubble
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
                    HStack(spacing: 8) {
                        if !filteredSessions.isEmpty {
                            Button {
                                if settingsStore.enableCasinoFeedback {
                                    CelebrationPlayer.shared.playQuickChime()
                                }
                                isShareSelectorPresented = true
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                                    .foregroundColor(.green)
                            }
                            .accessibilityLabel("Share sessions")
                        }

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
            .adaptiveSheet(item: $selectedSession) { SessionDetailView(session: $0) }
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
                Text("This session will be permanently removed. This cannot be undone.")
            }
            .adaptiveSheet(isPresented: $isShareSelectorPresented) {
                SessionShareSelectionView(
                    sessions: filteredSessions,
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
        }
    }
}

extension HistoryView {
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
                            Toggle(isOn: $shareAsPhoto) {
                                Text("Photo")
                                    .foregroundColor(.white)
                            }
                            .toggleStyle(SwitchToggleStyle(tint: .green))
                            .listRowBackground(Color(.systemGray6).opacity(0.15))

                            Toggle(isOn: $includeWinLosses) {
                                Text("Include win/losses")
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
                        Text("Metrics will be drawn on the image you choose.")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .listRowBackground(Color(.systemGray6).opacity(0.12))
                    }

                    Section(header: Text("Background image").foregroundColor(.gray)) {
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
            .navigationTitle("Choose photo")
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

