import SwiftUI
import UIKit

/// Calendar bucket for grouping past trips as `yyyy.MM`.
private struct TripYearMonth: Hashable, Comparable {
    let year: Int
    let month: Int

    static func < (lhs: TripYearMonth, rhs: TripYearMonth) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        return lhs.month < rhs.month
    }

    var dottedLabel: String {
        String(format: "%04d.%02d", year, month)
    }
}

private enum TripListTopFolder: Hashable {
    case upcoming
    case current
    case historical
}

struct TripsView: View {
    @EnvironmentObject var tripStore: TripStore
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var authStore: AuthStore
    @EnvironmentObject var subscriptionStore: SubscriptionStore

    @State private var showNewTripEditor = false
    @State private var tripToEdit: Trip?
    @State private var listShareImageItem: ShareableImageItem?
    @State private var tripPendingDelete: Trip?
    @State private var showTripMagicWand = false
    @State private var tripForAddSessions: Trip?
    /// Empty set → every top section is expanded.
    @State private var collapsedTopFolders: Set<TripListTopFolder> = []
    /// Empty set → every historical month bucket is expanded.
    @State private var collapsedHistoricalMonths: Set<TripYearMonth> = []

    private var currentTrips: [Trip] {
        tripStore.trips.filter { $0.timelineStatus() == .current }
            .sorted { $0.endDate < $1.endDate }
    }

    private var upcomingTrips: [Trip] {
        tripStore.trips.filter { $0.timelineStatus() == .upcoming }
            .sorted { $0.startDate < $1.startDate }
    }

    private var historicalTrips: [Trip] {
        tripStore.trips.filter { $0.isHistorical() }.sorted { $0.endDate > $1.endDate }
    }

    /// Historical trips grouped by **trip end** calendar month, newest `yyyy.MM` first.
    private var historicalTripsByYearMonth: [(TripYearMonth, [Trip])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: historicalTrips) { trip -> TripYearMonth in
            let d = trip.endDate
            let y = cal.component(.year, from: d)
            let m = cal.component(.month, from: d)
            return TripYearMonth(year: y, month: m)
        }
        return grouped.keys.sorted(by: >).map { key in
            let trips = grouped[key] ?? []
            return (key, trips.sorted { $0.endDate > $1.endDate })
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                settingsStore.primaryGradient.ignoresSafeArea()

                if tripStore.trips.isEmpty {
                    emptyState
                } else {
                    tripList
                }

                addTripFloatingButton
            }
            .navigationTitle("Trips")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showTripMagicWand = true
                    } label: {
                        Image(systemName: "wand.and.sparkles")
                            .imageScale(.medium)
                    }
                    .foregroundColor(.white)
                    .accessibilityLabel("Suggest trips with AI")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    accountToolbarButton
                }
            }
            .adaptiveSheet(isPresented: $showNewTripEditor) {
                TripEditorView()
                    .environmentObject(tripStore)
                    .environmentObject(sessionStore)
                    .environmentObject(settingsStore)
            }
            .adaptiveSheet(isPresented: $showTripMagicWand) {
                TripMagicWandView()
                    .environmentObject(tripStore)
                    .environmentObject(sessionStore)
                    .environmentObject(settingsStore)
                    .environmentObject(authStore)
                    .environmentObject(subscriptionStore)
            }
            .adaptiveSheet(item: $tripToEdit) { trip in
                TripEditorView(trip: trip)
                    .environmentObject(tripStore)
                    .environmentObject(sessionStore)
                    .environmentObject(settingsStore)
            }
            .adaptiveSheet(item: $tripForAddSessions) { trip in
                TripLinkSessionsSheet(tripId: trip.id)
                    .environmentObject(tripStore)
                    .environmentObject(sessionStore)
                    .environmentObject(settingsStore)
            }
            .adaptiveSheet(item: $listShareImageItem) { item in
                ShareSheet(items: [item.image])
            }
            .confirmationDialog(
                "Delete this trip?",
                isPresented: Binding(
                    get: { tripPendingDelete != nil },
                    set: { if !$0 { tripPendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let t = tripPendingDelete {
                        tripStore.delete(t)
                    }
                    tripPendingDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    tripPendingDelete = nil
                }
            } message: {
                if let t = tripPendingDelete {
                    Text("“\(t.displayTitle)” will be removed. Trip photos stored on this device will be deleted.")
                }
            }
        }
    }

    private var addTripFloatingButton: some View {
        Button {
            showNewTripEditor = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .bold))
                .frame(width: 56, height: 56)
                .background(Color.green).foregroundColor(.black)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.green.opacity(0.9), lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New trip")
        .padding(.trailing, 10)
        .padding(.bottom, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "suitcase.fill")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.9))
            Text("No trips yet")
                .font(.title2.bold())
                .foregroundColor(.white)
            Text("Track getaways, stays, flights, and the sessions that happened on each trip. Tap + to create one, or the sparkle wand to draft trips from your sessions with AI.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 36)
    }

    private var tripList: some View {
        List {
            if !upcomingTrips.isEmpty {
                Section {
                    if !collapsedTopFolders.contains(.upcoming) {
                        ForEach(upcomingTrips) { trip in
                            tripRowWithSwipes(trip)
                        }
                    }
                } header: {
                    topFolderSectionHeader(.upcoming, title: "Upcoming", systemImage: "calendar.badge.clock")
                }
            }

            if !currentTrips.isEmpty {
                Section {
                    if !collapsedTopFolders.contains(.current) {
                        ForEach(currentTrips) { trip in
                            tripRowWithSwipes(trip)
                        }
                    }
                } header: {
                    topFolderSectionHeader(.current, title: "Current", systemImage: "location.fill")
                }
            }

            if !historicalTrips.isEmpty {
                Section {
                    if !collapsedTopFolders.contains(.historical) {
                        ForEach(historicalTripsByYearMonth, id: \.0) { ym, trips in
                            Section {
                                if !collapsedHistoricalMonths.contains(ym) {
                                    ForEach(trips) { trip in
                                        tripRowWithSwipes(trip)
                                            .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
                                    }
                                }
                            } header: {
                                historicalMonthBubbleHeader(ym)
                            }
                        }
                    }
                } header: {
                    topFolderSectionHeader(.historical, title: "Historical", systemImage: "archivebox.fill")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .colorScheme(.dark)
        .environment(\.defaultMinListRowHeight, 12)
        .padding(.horizontal, 3)
        .padding(.top, 3)
        .padding(.bottom, 36)
    }

    private func topFolderSectionHeader(_ folder: TripListTopFolder, title: String, systemImage: String) -> some View {
        let expanded = !collapsedTopFolders.contains(folder)
        return Button {
            if collapsedTopFolders.contains(folder) {
                collapsedTopFolders.remove(folder)
            } else {
                collapsedTopFolders.insert(folder)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.white.opacity(0.72))
                    .frame(width: 7, alignment: .center)
                Image(systemName: systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.green.opacity(0.95))
                Text(title)
                    .font(.headline.bold())
                    .foregroundColor(.white)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) trips")
        .accessibilityHint(expanded ? "Collapse section" : "Expand section")
        .textCase(nil)
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowInsets(EdgeInsets(top: 4, leading: 2, bottom: 2, trailing: 2))
        .listRowBackground(Color.clear)
    }

    private func historicalMonthBubbleHeader(_ ym: TripYearMonth) -> some View {
        let expanded = !collapsedHistoricalMonths.contains(ym)
        return Button {
            if collapsedHistoricalMonths.contains(ym) {
                collapsedHistoricalMonths.remove(ym)
            } else {
                collapsedHistoricalMonths.insert(ym)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.white.opacity(0.72))
                    .frame(width: 6, alignment: .center)
                Text(ym.dottedLabel)
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white)
                    .monospacedDigit()
                Spacer(minLength: 4)
                Image(systemName: "calendar")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.white.opacity(0.55))
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.42))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Trips ending \(ym.dottedLabel.replacingOccurrences(of: ".", with: " "))")
        .accessibilityHint(expanded ? "Collapse month" : "Expand month")
        .listRowInsets(EdgeInsets(top: 3, leading: 3, bottom: 1, trailing: 3))
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private func tripRowWithSwipes(_ trip: Trip) -> some View {
        NavigationLink {
            TripDetailView(tripId: trip.id)
                .environmentObject(tripStore)
                .environmentObject(sessionStore)
                .environmentObject(settingsStore)
        } label: {
            tripRowLabel(trip)
        }
        .listRowBackground(Color.white.opacity(0.06))
        .listRowInsets(EdgeInsets(top: 3, leading: 5, bottom: 3, trailing: 5))
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                tripToEdit = trip
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.green)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if trip.timelineStatus() == .current {
                Button {
                    tripForAddSessions = trip
                } label: {
                    Label("Add sessions", systemImage: "plus.circle.fill")
                }
                .tint(.green)
            }
            Button(role: .destructive) {
                tripPendingDelete = trip
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button {
                shareTrip(trip)
            } label: {
                Label("Share summary image", systemImage: "square.and.arrow.up")
            }
        }
    }

    private func tripRowLabel(_ trip: Trip) -> some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 3) {
                Text(trip.displayTitle)
                    .font(.headline)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                Text(tripDateRangeText(trip))
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                if !trip.primaryLocationName.isEmpty {
                    Text(trip.primaryLocationName)
                        .font(.caption2)
                        .foregroundColor(.green.opacity(0.95))
                        .lineLimit(1)
                }
                HStack(spacing: 5) {
                    Label("\(trip.sessionIDs.count) sessions", systemImage: "dice.fill")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.65))
                    if !trip.flights.legs.isEmpty {
                        Label(tripFlightSummaryLabel(trip), systemImage: "airplane")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.65))
                    }
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(.green.opacity(0.5))
        }
        .padding(.vertical, 4)
    }

    private func tripDateRangeText(_ trip: Trip) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return "\(df.string(from: trip.startDate)) – \(df.string(from: trip.endDate))"
    }

    /// e.g. "1 round-trip flight", "3 direct flights"
    private func tripFlightSummaryLabel(_ trip: Trip) -> String {
        let n = trip.flights.legs.count
        let kind = trip.flights.pattern == .roundTrip ? "round-trip" : "direct"
        if n == 1 {
            return "1 \(kind) flight"
        }
        return "\(n) \(kind) flights"
    }

    private func linkedSessions(for trip: Trip) -> [Session] {
        let idSet = Set(trip.sessionIDs)
        return sessionStore.sessions
            .filter { idSet.contains($0.id) }
            .sorted { ($0.endTime ?? $0.startTime) > ($1.endTime ?? $1.startTime) }
    }

    private func shareTrip(_ trip: Trip) {
        let coverName = trip.photoFilenames.first
        var cover: UIImage?
        if let n = coverName {
            cover = tripStore.loadPhoto(tripId: trip.id, filename: n)
        }
        Task { @MainActor in
            if let image = await TripShareImageBuilder.render(
                trip: trip,
                sessions: linkedSessions(for: trip),
                coverImage: cover,
                settingsStore: settingsStore
            ) {
                listShareImageItem = ShareableImageItem(image: image)
            }
        }
    }

    private var accountToolbarButton: some View {
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
