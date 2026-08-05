import SwiftUI

/// Multi-select picklist of completed sessions to attach to a trip (used from trip detail and trips list).
struct TripLinkSessionsSheet: View {
    let tripId: UUID

    @EnvironmentObject private var tripStore: TripStore
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var selectedIDs: Set<UUID> = []

    private var trip: Trip? {
        tripStore.trips.first { $0.id == tripId }
    }

    private var eligibleIDSet: Set<UUID> {
        guard let t = trip else { return [] }
        return Trip.eligibleSessionIDs(
            startDate: t.startDate,
            endDate: t.endDate,
            sessions: sessionStore.sessions
        )
    }

    private var baseCandidates: [Session] {
        guard let t = trip else { return [] }
        let linked = Set(t.sessionIDs)
        return sessionStore.sessions
            .filter { $0.isComplete && !linked.contains($0.id) }
            .sorted { $0.startTime > $1.startTime }
    }

    private var filteredCandidates: [Session] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return baseCandidates }
        return baseCandidates.filter {
            $0.casino.lowercased().contains(q) || $0.game.lowercased().contains(q)
        }
    }

    private var inTripWindow: [Session] {
        filteredCandidates.filter { eligibleIDSet.contains($0.id) }
    }

    private var otherSessions: [Session] {
        filteredCandidates.filter { !eligibleIDSet.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                if trip == nil {
                    L10nText("This trip is no longer available.")
                        .foregroundColor(.white.opacity(0.9))
                        .padding()
                } else if baseCandidates.isEmpty {
                    emptyAllLinked
                } else if filteredCandidates.isEmpty {
                    emptySearch
                } else {
                    listContent
                }
            }
            .localizedNavigationTitle("Add sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.green)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { applyLink() }
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                        .disabled(selectedIDs.isEmpty)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Casino or game")
    }

    private var emptyAllLinked: some View {
        L10nText("Every completed session is already on this trip, or you have no completed sessions yet.")
            .font(.subheadline)
            .foregroundColor(.white.opacity(0.88))
            .multilineTextAlignment(.center)
            .padding(28)
    }

    private var emptySearch: some View {
        L10nText("No sessions match your search.")
            .font(.subheadline)
            .foregroundColor(.white.opacity(0.85))
    }

    private var listContent: some View {
        List {
            if !inTripWindow.isEmpty {
                Section {
                    ForEach(inTripWindow) { session in
                        sessionPickRow(session)
                    }
                } header: {
                    L10nText("Within trip dates")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.85))
                        .textCase(nil)
                }
            }
            if !otherSessions.isEmpty {
                Section {
                    ForEach(otherSessions) { session in
                        sessionPickRow(session)
                    }
                } header: {
                    L10nText("Other completed sessions")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.78))
                        .textCase(nil)
                } footer: {
                    L10nText("You can still link sessions that fall outside the trip’s start/end dates.")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.55))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .colorScheme(.dark)
    }

    private func sessionPickRow(_ session: Session) -> some View {
        let on = selectedIDs.contains(session.id)
        return Button {
            if on {
                selectedIDs.remove(session.id)
            } else {
                selectedIDs.insert(session.id)
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(on ? .green : .gray)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.casino)
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                    Text(session.game)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.72))
                    Text(session.startTime.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.52))
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.white.opacity(0.06))
    }

    private func applyLink() {
        guard !selectedIDs.isEmpty else { return }
        tripStore.linkSessionIDs(Array(selectedIDs), to: tripId)
        dismiss()
    }
}
