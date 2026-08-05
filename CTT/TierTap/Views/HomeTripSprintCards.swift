import SwiftUI

/// Sprint 2: Home trip prep (≤7 days out) and post-trip recap cards.
struct HomeTripSprintSection: View {
    @EnvironmentObject private var tripStore: TripStore
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var settingsStore: SettingsStore

    var onOpenTrips: () -> Void

    @State private var dismissedIds: Set<String> = []
    #if os(iOS)
    @State private var shareImageItem: ShareableImageItem?
    @State private var pendingAutoShareTripId: UUID?
    @State private var showAutoSharePrompt = false
    #endif

    private var cards: [TierTapProductEnhancements.TripHomeCardModel] {
        let prep = TierTapProductEnhancements.tripPrepCandidates(
            trips: tripStore.trips,
            sessions: sessionStore.sessions
        )
        let recap = TierTapProductEnhancements.tripRecapCandidates(
            trips: tripStore.trips,
            sessions: sessionStore.sessions
        )
        return (prep + recap).filter { !dismissedIds.contains($0.id) }
    }

    var body: some View {
        if TierTapProductEnhancements.isSprint2Active, !cards.isEmpty {
            VStack(spacing: 10) {
                ForEach(cards.prefix(2)) { model in
                    tripCard(model)
                }
            }
            #if os(iOS)
            .onAppear { offerPostTripShareIfNeeded() }
            .sheet(item: $shareImageItem) { item in
                ShareSheet(items: [item.image])
            }
            .confirmationDialog(
                "Share your trip recap?",
                isPresented: $showAutoSharePrompt,
                titleVisibility: .visible
            ) {
                Button("Share trip card") {
                    if let id = pendingAutoShareTripId,
                       let trip = tripStore.trips.first(where: { $0.id == id }) {
                        shareTrip(trip)
                    }
                }
                Button("Not now", role: .cancel) {}
            } message: {
                Text("Your trip just wrapped — share a summary image.")
            }
            #endif
        }
    }

    private func tripCard(_ model: TierTapProductEnhancements.TripHomeCardModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onOpenTrips) {
                HStack(alignment: .top) {
                    Image(systemName: model.kind == .prep ? "suitcase.cart.fill" : "flag.checkered")
                        .foregroundColor(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.kind == .prep ? "Trip prep" : "Trip recap")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white.opacity(0.7))
                        Text(model.trip.displayTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(subtitle(for: model))
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.75))
                    }
                    Spacer(minLength: 8)
                    Button {
                        TierTapProductEnhancements.dismissTripCard(model)
                        dismissedIds.insert(model.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.body)
                            .foregroundColor(.white.opacity(0.45))
                    }
                    .buttonStyle(.plain)
                }
            }
            .buttonStyle(.plain)

            if model.kind == .recap {
                HStack(spacing: 12) {
                    metric("Sessions", "\(model.sessionCount)")
                    metric("Tiers", "\(model.tierPoints)")
                    metric("Net", cashText(model.cashNet))
                    if model.hoursPlayed > 0 {
                        metric("Hours", String(format: "%.1f", model.hoursPlayed))
                    }
                }
                #if os(iOS)
                Button {
                    markTripSharePrompted(model.trip.id)
                    shareTrip(model.trip)
                } label: {
                    Label("Share trip recap", systemImage: "square.and.arrow.up")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.85))
                        .foregroundStyle(.white)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
                #endif
            } else {
                Text("Check wallet goals, lodging, and logging before you arrive.")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.72))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6).opacity(0.22))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func subtitle(for model: TierTapProductEnhancements.TripHomeCardModel) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let start = formatter.string(from: model.trip.startDate)
        let end = formatter.string(from: model.trip.endDate)
        if model.kind == .prep {
            let days = model.daysUntilStart ?? 0
            let when: String
            switch days {
            case 0: when = "Starts today"
            case 1: when = "Starts tomorrow"
            default: when = "Starts in \(days) days"
            }
            return "\(when) · \(start) – \(end)"
        }
        let since = model.daysSinceEnd ?? 0
        let when = since == 0 ? "Ended today" : (since == 1 ? "Ended yesterday" : "Ended \(since) days ago")
        return "\(when) · \(start) – \(end)"
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.55))
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cashText(_ value: Int) -> String {
        let sign = value > 0 ? "+" : ""
        return "\(sign)\(settingsStore.currencySymbol)\(value)"
    }

    #if os(iOS)
    private func tripSharePromptKey(_ tripId: UUID) -> String {
        "ctt_trip_share_prompted_\(tripId.uuidString)"
    }

    private func hasPromptedTripShare(_ tripId: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: tripSharePromptKey(tripId))
    }

    private func markTripSharePrompted(_ tripId: UUID) {
        UserDefaults.standard.set(true, forKey: tripSharePromptKey(tripId))
    }

    private func offerPostTripShareIfNeeded() {
        let recap = cards.first(where: { $0.kind == .recap })
        guard let model = recap, !hasPromptedTripShare(model.trip.id) else { return }
        // Only auto-prompt for trips that ended very recently (0–1 day).
        guard (model.daysSinceEnd ?? 99) <= 1 else { return }
        markTripSharePrompted(model.trip.id)
        pendingAutoShareTripId = model.trip.id
        showAutoSharePrompt = true
    }

    private func shareTrip(_ trip: Trip) {
        Task { @MainActor in
            let photos = trip.photoFilenames.compactMap { tripStore.loadPhoto(tripId: trip.id, filename: $0) }
            if let image = await TripShareImageBuilder.render(
                trip: trip,
                sessions: sessionStore.sessions,
                tripPhotos: photos,
                settingsStore: settingsStore
            ) {
                shareImageItem = ShareableImageItem(image: image)
            }
        }
    }
    #endif
}
