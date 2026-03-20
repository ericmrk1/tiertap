import SwiftUI
import Supabase

// MARK: - Clustering (date + casino grouping)

private enum TripMagicWandClustering {
    static func normalizedCasino(_ session: Session) -> String {
        session.casino.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func heuristicClusters(sessions: [Session], maxGapHours: Double = 96) -> [[Session]] {
        let sorted = sessions.sorted { $0.startTime < $1.startTime }
        var byCasino: [String: [Session]] = [:]
        for s in sorted {
            byCasino[normalizedCasino(s), default: []].append(s)
        }

        var clusters: [[Session]] = []
        for (_, group) in byCasino {
            let g = group.sorted { $0.startTime < $1.startTime }
            var current: [Session] = []
            var clusterEnd: Date?
            let maxGap = maxGapHours * 3600

            for s in g {
                let end = s.endTime ?? s.startTime
                if current.isEmpty {
                    current = [s]
                    clusterEnd = end
                } else if let ce = clusterEnd, s.startTime.timeIntervalSince(ce) <= maxGap {
                    current.append(s)
                    clusterEnd = max(ce, end)
                } else {
                    clusters.append(current)
                    current = [s]
                    clusterEnd = end
                }
            }
            if !current.isEmpty { clusters.append(current) }
        }

        return clusters.sorted {
            ($0.first?.startTime ?? .distantPast) < ($1.first?.startTime ?? .distantPast)
        }
    }
}

// MARK: - Editable draft

struct EditableProposedTrip: Identifiable {
    var id: UUID = UUID()
    var isIncluded: Bool = true
    var title: String
    var primaryLocationName: String
    /// Matches `Trip.primarySubtitle` (map picker / region lines).
    var primarySubtitle: String = ""
    var primaryLatitude: Double? = nil
    var primaryLongitude: Double? = nil
    var startDate: Date
    var endDate: Date
    var notes: String
    var sessionIDs: [UUID]

    /// Same splitting rules as `Trip.primaryLocationSubtitleLines`.
    var locationSubtitleLines: [String] {
        let s = primarySubtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return [] }
        if s.contains(" · ") {
            return s.split(separator: " · ")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        let commaParts = s.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if commaParts.count >= 2 {
            return commaParts
        }
        return [s]
    }

    func timelineStatus(now: Date = Date(), calendar: Calendar = .current) -> TripTimelineStatus {
        let s = min(startDate, endDate)
        let e = max(startDate, endDate)
        let stub = Trip(
            title: title,
            startDate: s,
            endDate: e,
            primaryLocationName: primaryLocationName,
            primarySubtitle: primarySubtitle,
            primaryLatitude: primaryLatitude,
            primaryLongitude: primaryLongitude,
            sessionIDs: sessionIDs,
            notes: notes
        )
        return stub.timelineStatus(relativeTo: now, calendar: calendar)
    }
}

// MARK: - Sheet

struct TripMagicWandView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var tripStore: TripStore
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var authStore: AuthStore
    @EnvironmentObject var subscriptionStore: SubscriptionStore

    @State private var phase: Phase = .intro
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var proposedTrips: [EditableProposedTrip] = []
    @State private var showPaywall = false
    @State private var mapPickTargetId: UUID?

    private enum Phase {
        case intro
        case review
    }

    /// Same rule as other AI surfaces: Pro, developer subscription override, or free-tier daily quota.
    private var canRequestTripSuggestions: Bool {
        subscriptionStore.isPro
            || settingsStore.isSubscriptionOverrideActive
            || settingsStore.canUseAI()
    }

    private var assignedSessionIDs: Set<UUID> {
        Set(tripStore.trips.flatMap(\.sessionIDs))
    }

    private var unassignedSessions: [Session] {
        sessionStore.sessions.filter { $0.isComplete && !assignedSessionIDs.contains($0.id) }
    }

    private var upcomingTripCount: Int {
        tripStore.trips.filter { $0.timelineStatus() == .upcoming }.count
    }

    private var currentTripCount: Int {
        tripStore.trips.filter { $0.timelineStatus() == .current }.count
    }

    private var historicalTripCount: Int {
        tripStore.trips.filter { $0.isHistorical() }.count
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = Calendar.current.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let isoDateTime: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let displayDateRangeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()

                Group {
                    switch phase {
                    case .intro:
                        introContent
                    case .review:
                        reviewContent
                    }
                }
            }
            .navigationTitle("Suggest trips")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(.white)
                }
                if phase == .review {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Start over") {
                            phase = .intro
                            proposedTrips = []
                            errorMessage = nil
                            mapPickTargetId = nil
                        }
                        .foregroundColor(.white)
                    }
                }
            }
        }
        .adaptiveSheet(isPresented: mapPickSheetBinding) {
            mapPickSheetContent
        }
        .adaptiveSheet(isPresented: $showPaywall) {
            TierTapPaywallView()
                .environmentObject(subscriptionStore)
                .environmentObject(settingsStore)
                .environmentObject(authStore)
        }
    }

    private var mapPickSheetBinding: Binding<Bool> {
        Binding(
            get: { mapPickTargetId != nil },
            set: { if !$0 { mapPickTargetId = nil } }
        )
    }

    @ViewBuilder
    private var mapPickSheetContent: some View {
        if let id = mapPickTargetId {
            MapPlacePickerView(
                navigationTitle: "Trip location",
                name: binding(\.primaryLocationName, draftId: id),
                subtitle: binding(\.primarySubtitle, draftId: id),
                latitude: optionalBinding(\.primaryLatitude, draftId: id),
                longitude: optionalBinding(\.primaryLongitude, draftId: id)
            )
            .environmentObject(settingsStore)
        }
    }

    private func binding(_ keyPath: WritableKeyPath<EditableProposedTrip, String>, draftId: UUID) -> Binding<String> {
        Binding(
            get: { proposedTrips.first { $0.id == draftId }?[keyPath: keyPath] ?? "" },
            set: { newVal in
                if let i = proposedTrips.firstIndex(where: { $0.id == draftId }) {
                    proposedTrips[i][keyPath: keyPath] = newVal
                }
            }
        )
    }

    private func optionalBinding(_ keyPath: WritableKeyPath<EditableProposedTrip, Double?>, draftId: UUID) -> Binding<Double?> {
        Binding(
            get: { proposedTrips.first { $0.id == draftId }?[keyPath: keyPath] },
            set: { newVal in
                if let i = proposedTrips.firstIndex(where: { $0.id == draftId }) {
                    proposedTrips[i][keyPath: keyPath] = newVal
                }
            }
        )
    }

    // MARK: - Intro (Trips-style section headers + timeline-aware stats)

    private var introContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                wandSectionHeader("AI trip suggestions", systemImage: "wand.and.sparkles")

                Text("TierTap groups completed sessions that are not already on a trip. Gemini proposes names, dates, location labels, and notes—the same upcoming, current, and historical buckets as the Trips tab.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))

                VStack(alignment: .leading, spacing: 12) {
                    Text("Your library")
                        .font(.caption.bold())
                        .foregroundColor(.white.opacity(0.75))
                    statRow(icon: "calendar.badge.clock", label: "Upcoming trips", value: upcomingTripCount)
                    statRow(icon: "location.fill", label: "Current trips", value: currentTripCount)
                    statRow(icon: "archivebox.fill", label: "Historical trips", value: historicalTripCount)
                    Divider().background(Color.white.opacity(0.2))
                    statRow(icon: "dice.fill", label: "Sessions not on a trip", value: unassignedSessions.count)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.28))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                Button {
                    Task { await generateProposals() }
                } label: {
                    HStack {
                        if isWorking {
                            ProgressView()
                                .tint(.black)
                        }
                        Text(isWorking ? "Working…" : "Generate trip ideas")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(unassignedSessions.isEmpty || isWorking ? Color.gray : Color.green)
                    .foregroundColor(.black)
                    .cornerRadius(12)
                }
                .disabled(unassignedSessions.isEmpty || isWorking || !authStore.isSignedIn)

                if unassignedSessions.isEmpty {
                    Text("No unassigned completed sessions—every session is already linked to a trip, or you have no completed sessions yet.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }

                if !authStore.isSignedIn {
                    Text("Sign in to use AI trip suggestions.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            .padding(20)
            .padding(.bottom, 24)
        }
    }

    private func wandSectionHeader(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundColor(.green.opacity(0.95))
            Text(title)
                .font(.title3.bold())
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statRow(icon: String, label: String, value: Int) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.88))
                .labelStyle(.titleAndIcon)
                .tint(.green.opacity(0.9))
            Spacer()
            Text("\(value)")
                .font(.subheadline.weight(.bold))
                .foregroundColor(.white)
                .monospacedDigit()
        }
    }

    // MARK: - Review (Trip detail / editor card chrome)

    private var reviewContent: some View {
        VStack(spacing: 0) {
            Text("Review each card: toggle, edit, or tap Search map for a proper place pin. Timelines match the Trips tab (upcoming, current, historical).")
                .font(.caption)
                .foregroundColor(.white.opacity(0.82))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 20) {
                    ForEach($proposedTrips) { $trip in
                        proposedTripCard($trip)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 120)
            }

            commitBar
        }
    }

    private func proposedTripCard(_ trip: Binding<EditableProposedTrip>) -> some View {
        let draft = trip.wrappedValue
        let status = draft.timelineStatus()
        let sessions = resolvedSessions(for: draft.sessionIDs)

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                Text(
                    "\(Self.displayDateRangeFormatter.string(from: min(draft.startDate, draft.endDate))) – \(Self.displayDateRangeFormatter.string(from: max(draft.startDate, draft.endDate)))"
                )
                .font(.caption.weight(.semibold))
                .foregroundColor(.green.opacity(0.95))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                Text(status.badgeLabel)
                    .font(.caption.bold())
                    .foregroundColor(.white.opacity(0.65))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.12))
                    .cornerRadius(8)
            }

            Toggle("Include when saving", isOn: trip.isIncluded)
                .tint(.green)
                .foregroundColor(.white)

            editorSectionTitle("Basics")
            TextField("Trip title (optional)", text: trip.title)
                .padding(12)
                .background(Color(.systemGray6).opacity(0.25))
                .cornerRadius(10)
                .foregroundColor(.white)

            datePickerRow(start: trip.startDate, end: trip.endDate)

            editorSectionTitle("Location")
            proposedLocationBlock(draftId: draft.id, trip: trip)

            editorSectionTitle("Notes")
            TextField("Notes", text: trip.notes, axis: .vertical)
                .lineLimit(3...8)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.systemGray6).opacity(0.22))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .foregroundColor(.white.opacity(0.95))

            editorSectionTitle("Sessions")
            sessionsBlock(sessions: sessions, count: draft.sessionIDs.count)
        }
        .padding(14)
        .background(Color.black.opacity(0.28))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func editorSectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .foregroundColor(.white)
    }

    private func datePickerRow(start: Binding<Date>, end: Binding<Date>) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Start")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.85))
                DatePicker("", selection: start, displayedComponents: [.date])
                    .labelsHidden()
                    .tint(.green)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(Color.white.opacity(0.22))
                .frame(width: 1)
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 6) {
                Text("End")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.85))
                DatePicker("", selection: end, displayedComponents: [.date])
                    .labelsHidden()
                    .tint(.green)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Color(.systemGray6).opacity(0.25))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func proposedLocationBlock(draftId: UUID, trip: Binding<EditableProposedTrip>) -> some View {
        let draft = trip.wrappedValue
        let nameSet = !draft.primaryLocationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let lines = draft.locationSubtitleLines

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.title2)
                    .foregroundColor(.green)
                    .frame(width: 36, height: 36)
                    .background(Color.green.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    TextField(nameSet ? "Primary place name" : "City or venue (or use Search map)", text: trip.primaryLocationName)
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.white)

                    if !lines.isEmpty {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.white.opacity(0.92))
                        }
                    }
                }
                Spacer(minLength: 0)
            }

            Button {
                mapPickTargetId = draftId
            } label: {
                Label("Search map", systemImage: "map")
                    .font(.subheadline.bold())
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.green)
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color.black.opacity(0.22))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private func sessionsBlock(sessions: [Session], count: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("\(count) session\(count == 1 ? "" : "s")", systemImage: "dice.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.88))
                .tint(.green.opacity(0.85))

            if sessions.isEmpty {
                Text("Session list unavailable (IDs may be invalid).")
                    .font(.caption)
                    .foregroundColor(.orange.opacity(0.9))
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(sessions.prefix(6)) { s in
                        HStack {
                            Text(s.casino)
                                .font(.caption.weight(.medium))
                                .foregroundColor(.white.opacity(0.9))
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(s.game)
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.55))
                                .lineLimit(1)
                        }
                    }
                    if sessions.count > 6 {
                        Text("+\(sessions.count - 6) more")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6).opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private var commitBar: some View {
        VStack(spacing: 0) {
            Button {
                commitSelectedTrips()
            } label: {
                Text("Add \(selectedTripCount) trip\(selectedTripCount == 1 ? "" : "s")")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(selectedTripCount == 0 ? Color.gray : Color.green)
                    .foregroundColor(.black)
                    .cornerRadius(12)
            }
            .disabled(selectedTripCount == 0)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.black.opacity(0.5))
    }

    private var selectedTripCount: Int {
        proposedTrips.filter { $0.isIncluded && !$0.sessionIDs.isEmpty }.count
    }

    private func resolvedSessions(for ids: [UUID]) -> [Session] {
        let set = Set(ids)
        return sessionStore.sessions
            .filter { set.contains($0.id) }
            .sorted { $0.startTime < $1.startTime }
    }

    // MARK: - Generate / commit

    private func generateProposals() async {
        errorMessage = nil

        guard authStore.isSignedIn else {
            errorMessage = "Please sign in to continue."
            return
        }
        guard SupabaseConfig.isConfigured, let client = supabase else {
            errorMessage = "AI is not configured for this build."
            return
        }
        guard !unassignedSessions.isEmpty else { return }

        if !canRequestTripSuggestions {
            await MainActor.run { showPaywall = true }
            return
        }

        await MainActor.run { isWorking = true }

        let allowedIDs = Set(unassignedSessions.map(\.id))
        let clusters = TripMagicWandClustering.heuristicClusters(sessions: unassignedSessions)
        let prompt = Self.buildPrompt(
            existingTrips: tripStore.trips,
            clusters: clusters,
            sessions: unassignedSessions
        )

        struct GeminiRequest: Encodable {
            struct Part: Encodable { let text: String }
            struct Content: Encodable {
                let role: String
                let parts: [Part]
            }
            let contents: [Content]
        }
        struct GeminiPart: Decodable { let text: String? }
        struct GeminiContent: Decodable { let parts: [GeminiPart]? }
        struct GeminiCandidate: Decodable { let content: GeminiContent? }
        struct GeminiRouterResponse: Decodable { let candidates: [GeminiCandidate]? }

        do {
            if !subscriptionStore.isPro && !settingsStore.isSubscriptionOverrideActive {
                await MainActor.run { settingsStore.registerAICall() }
            }

            let body = GeminiRequest(
                contents: [.init(role: "user", parts: [.init(text: prompt)])]
            )
            let response: GeminiRouterResponse = try await GeminiRouterThrottle.tripSuggestions.executeWithRetries {
                try await client.functions.invoke(
                    "gemini-router",
                    options: FunctionInvokeOptions(body: body)
                )
            }
            let rawText = response.candidates?
                .first?
                .content?
                .parts?
                .compactMap(\.text)
                .joined(separator: "\n") ?? ""

            let drafts = Self.parseProposals(
                rawText: rawText,
                allowedSessionIDs: allowedIDs,
                calendar: Calendar.current
            )
            var mutable = drafts
            Self.dedupeSessionsAcrossTrips(&mutable)
            let filtered = mutable.filter { !$0.sessionIDs.isEmpty }

            await MainActor.run {
                isWorking = false
                if filtered.isEmpty {
                    errorMessage = "Could not parse trip suggestions. Try again, or check your connection."
                    return
                }
                proposedTrips = filtered
                phase = .review
            }
        } catch {
            await MainActor.run {
                isWorking = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func commitSelectedTrips() {
        let cal = Calendar.current
        for draft in proposedTrips where draft.isIncluded && !draft.sessionIDs.isEmpty {
            let startDay = cal.startOfDay(for: min(draft.startDate, draft.endDate))
            let endDay = cal.startOfDay(for: max(draft.startDate, draft.endDate))
            let trip = Trip(
                title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
                startDate: startDay,
                endDate: endDay,
                primaryLocationName: draft.primaryLocationName.trimmingCharacters(in: .whitespacesAndNewlines),
                primarySubtitle: draft.primarySubtitle.trimmingCharacters(in: .whitespacesAndNewlines),
                primaryLatitude: draft.primaryLatitude,
                primaryLongitude: draft.primaryLongitude,
                sessionIDs: draft.sessionIDs,
                notes: draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            tripStore.add(trip)
        }
        dismiss()
    }

    // MARK: - Prompt + parsing

    private static func buildPrompt(existingTrips: [Trip], clusters: [[Session]], sessions: [Session]) -> String {
        let tripLines = existingTrips.map { t -> String in
            let a = dayFormatter.string(from: t.startDate)
            let b = dayFormatter.string(from: t.endDate)
            let segment: String
            switch t.timelineStatus() {
            case .upcoming: segment = "upcoming"
            case .current: segment = "current"
            case .past: segment = "historical"
            }
            return "- [\(segment)] \(t.displayTitle): \(a) … \(b), \(t.sessionIDs.count) sessions, location: \(t.primaryLocationName.isEmpty ? "—" : t.primaryLocationName)"
        }
        .joined(separator: "\n")

        let clusterPayload = clusters.map { group in
            group.map(\.id.uuidString)
        }
        let clusterJSON = (try? String(data: JSONSerialization.data(withJSONObject: clusterPayload, options: []), encoding: .utf8)) ?? "[]"

        struct SessionLine: Encodable {
            let id: String
            let casino: String
            let game: String
            let start: String
            let end: String?
            let winLoss: Int?
            let hours: Double
        }

        let sessionLines: [SessionLine] = sessions.map { s in
            let start = isoDateTime.string(from: s.startTime)
            let endStr = s.endTime.map { isoDateTime.string(from: $0) }
            return SessionLine(
                id: s.id.uuidString,
                casino: s.casino,
                game: s.game,
                start: start,
                end: endStr,
                winLoss: s.winLoss,
                hours: s.hoursPlayed
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let sessionsJSON = (try? String(data: encoder.encode(sessionLines), encoding: .utf8)) ?? "[]"

        return """
        You help organize a player's casino trip history into Trip records.

        Output ONLY a single JSON object (no markdown fences, no prose) with this exact shape:
        {"trips":[{"title":"short trip name","primaryLocationName":"city or main venue label","startDate":"yyyy-MM-dd","endDate":"yyyy-MM-dd","sessionIds":["uuid",…],"notes":"2–4 sentences of helpful context: what this getaway looked like (games, venues, pacing). Mention approximate P&L only if session data makes it obvious. Do not say you are an AI."}]}

        Rules:
        - sessionIds MUST be copied exactly from the UNASSIGNED_SESSIONS list below. Never invent UUIDs.
        - Every unassigned session id should appear in exactly one trip when possible. Merge sessions that clearly belong to the same trip (same trip window, same metro / area) even if HEURISTIC_CLUSTERS split them.
        - startDate and endDate are calendar dates covering from the earliest session start day through the latest session end day (inclusive) for those sessions.
        - If HEURISTIC_CLUSTERS suggests separate visits to the same city weeks apart, keep them as separate trips.
        - Omit trips with zero sessions. Keep titles concise (e.g. "Vegas long weekend", "Borgata overnight").
        - EXISTING_TRIPS entries are tagged [upcoming], [current], or [historical] so you can mirror the user's naming style.

        EXISTING_TRIPS (already saved; sessions below are not on these trips):
        \(tripLines.isEmpty ? "(none)" : tripLines)

        HEURISTIC_CLUSTERS (arrays of session UUIDs grouped by same venue + close dates — refine / merge sensibly):
        \(clusterJSON)

        UNASSIGNED_SESSIONS (authoritative metadata JSON):
        \(sessionsJSON)
        """
    }

    private static func parseProposals(
        rawText: String,
        allowedSessionIDs: Set<UUID>,
        calendar: Calendar
    ) -> [EditableProposedTrip] {
        guard let data = extractJSONData(from: rawText) else { return [] }

        struct Payload: Decodable {
            struct Item: Decodable {
                let title: String?
                let primaryLocationName: String?
                let startDate: String
                let endDate: String
                let sessionIds: [String]
                let notes: String?
            }
            let trips: [Item]
        }

        let decoded: Payload
        do {
            decoded = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            return []
        }

        var results: [EditableProposedTrip] = []
        for item in decoded.trips {
            var ids: [UUID] = []
            for s in item.sessionIds {
                guard let u = UUID(uuidString: s), allowedSessionIDs.contains(u) else { continue }
                ids.append(u)
            }
            ids = Array(Set(ids))

            guard let start = dayFormatter.date(from: item.startDate),
                  let end = dayFormatter.date(from: item.endDate) else { continue }

            let startDay = calendar.startOfDay(for: start)
            let endDay = calendar.startOfDay(for: end)
            let title = (item.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let loc = (item.primaryLocationName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let notes = (item.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            results.append(
                EditableProposedTrip(
                    title: title,
                    primaryLocationName: loc,
                    primarySubtitle: "",
                    primaryLatitude: nil,
                    primaryLongitude: nil,
                    startDate: startDay,
                    endDate: endDay,
                    notes: notes,
                    sessionIDs: ids
                )
            )
        }
        return results
    }

    private static func dedupeSessionsAcrossTrips(_ trips: inout [EditableProposedTrip]) {
        var claimed = Set<UUID>()
        for i in trips.indices {
            var next: [UUID] = []
            for sid in trips[i].sessionIDs where !claimed.contains(sid) {
                claimed.insert(sid)
                next.append(sid)
            }
            trips[i].sessionIDs = next
        }
    }

    private static func extractJSONData(from text: String) -> Data? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fenceStart = s.range(of: "```json"),
           let fenceEnd = s.range(of: "```", range: fenceStart.upperBound..<s.endIndex) {
            s = String(s[fenceStart.upperBound..<fenceEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let fenceStart = s.range(of: "```"),
                  let fenceEnd = s.range(of: "```", range: fenceStart.upperBound..<s.endIndex) {
            s = String(s[fenceStart.upperBound..<fenceEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let start = s.firstIndex(of: "{"),
              let end = s.lastIndex(of: "}") else { return nil }
        let slice = s[start...end]
        return String(slice).data(using: .utf8)
    }
}
