import SwiftUI

private enum FlightAirportEndpoint: Hashable {
    case origin(UUID)
    case destination(UUID)
}

struct TripEditorView: View {
    @EnvironmentObject var tripStore: TripStore
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss

    private let existingId: UUID?

    @State private var draft: Trip
    @State private var showPrimaryPlacePicker = false
    @State private var lodgingMapPick: LodgingMapPick?
    @State private var flightEndpointPick: FlightEndpointPick?
    @FocusState private var airlineFieldLegId: UUID?
    @FocusState private var flightAirportField: FlightAirportEndpoint?
    @State private var validationMessage: String?
    @State private var didApplyNewTripSessionDefault = false
    /// Leg IDs that are **collapsed** in the editor (omitted = expanded).
    @State private var collapsedFlightLegIds: Set<UUID> = []
    /// Narrows which completed sessions appear in the list (inclusive calendar days).
    @State private var sessionListFilterStart: Date
    @State private var sessionListFilterEnd: Date

    init(trip: Trip? = nil) {
        existingId = trip?.id
        let initialTrip: Trip
        if let t = trip {
            _draft = State(initialValue: t)
            initialTrip = t
        } else {
            let now = Date()
            let end = Calendar.current.date(byAdding: .day, value: 3, to: now) ?? now.addingTimeInterval(86_400 * 3)
            let blank = Trip(startDate: now, endDate: end)
            _draft = State(initialValue: blank)
            initialTrip = blank
        }
        let a = min(initialTrip.startDate, initialTrip.endDate)
        let b = max(initialTrip.startDate, initialTrip.endDate)
        _sessionListFilterStart = State(initialValue: a)
        _sessionListFilterEnd = State(initialValue: b)
    }

    private var completedSessions: [Session] {
        sessionStore.sessions
            .filter { $0.isComplete }
            .sorted { $0.startTime > $1.startTime }
    }

    /// Completed sessions whose time span overlaps the **list filter** window (inclusive days).
    private var completedSessionsInFilter: [Session] {
        let cal = Calendar.current
        let lo = cal.startOfDay(for: min(sessionListFilterStart, sessionListFilterEnd))
        guard let hiExclusive = cal.date(
            byAdding: .day,
            value: 1,
            to: cal.startOfDay(for: max(sessionListFilterStart, sessionListFilterEnd))
        ) else {
            return completedSessions
        }
        return completedSessions.filter { s in
            let sessionStart = s.startTime
            let sessionEnd = s.endTime ?? s.startTime
            return sessionStart < hiExclusive && sessionEnd >= lo
        }
    }

    private var eligibleSessionIDs: Set<UUID> {
        Trip.eligibleSessionIDs(
            startDate: draft.startDate,
            endDate: draft.endDate,
            sessions: sessionStore.sessions
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let msg = validationMessage {
                            Text(msg)
                                .font(.caption)
                                .foregroundColor(.orange)
                                .padding(.horizontal)
                        }

                        sectionTitle("Basics")
                        TextField("Trip title (optional)", text: $draft.title)
                            .padding(12)
                            .background(Color(.systemGray6).opacity(0.25))
                            .cornerRadius(10)
                            .foregroundColor(.white)

                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Start")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.85))
                                DatePicker("", selection: $draft.startDate, displayedComponents: [.date])
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
                                DatePicker("", selection: $draft.endDate, displayedComponents: [.date])
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

                        sectionTitle("Location")
                        primaryLocationBubble

                        sectionTitle("Accommodations")
                        accommodationsBubble

                        sectionTitle("Sessions on this trip")
                        Text("Sessions that overlap your trip dates (inclusive) are selected automatically. Scroll to review the list and tap any row to add or remove it.")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.75))
                        if completedSessions.isEmpty {
                            Text("No completed sessions yet.")
                                .font(.caption)
                                .foregroundColor(.gray)
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Filter list by session dates")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.white.opacity(0.88))
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("From")
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.85))
                                        DatePicker("", selection: $sessionListFilterStart, displayedComponents: [.date])
                                            .labelsHidden()
                                            .tint(.green)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    Rectangle()
                                        .fill(Color.white.opacity(0.22))
                                        .frame(width: 1)
                                        .padding(.vertical, 4)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Through")
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.85))
                                        DatePicker("", selection: $sessionListFilterEnd, displayedComponents: [.date])
                                            .labelsHidden()
                                            .tint(.green)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(12)
                                .background(Color(.systemGray6).opacity(0.22))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                                Button {
                                    let a = min(draft.startDate, draft.endDate)
                                    let b = max(draft.startDate, draft.endDate)
                                    sessionListFilterStart = a
                                    sessionListFilterEnd = b
                                } label: {
                                    Text("Use trip dates for filter")
                                        .font(.caption.bold())
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.green)

                                if completedSessionsInFilter.isEmpty {
                                    Text("No sessions overlap this filter range. Adjust the dates above.")
                                        .font(.caption)
                                        .foregroundColor(.orange.opacity(0.9))
                                } else {
                                    LazyVStack(spacing: 8) {
                                        ForEach(completedSessionsInFilter) { session in
                                            sessionToggleRow(session)
                                        }
                                    }
                                    .padding(10)
                                    .background(Color.black.opacity(0.28))
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                    )
                                }
                            }
                        }

                        sectionTitle("Flights")
                        Picker("Trip type", selection: $draft.flights.pattern) {
                            ForEach(TripFlightPattern.allCases, id: \.self) { p in
                                Text(p.label).tag(p)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text("Airline: start typing to match name, IATA, or ICAO. Origin and destination: type city, name, or code — picking from the list saves the IATA code; Map also saves IATA when the place matches the airport catalog.")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.72))
                            .fixedSize(horizontal: false, vertical: true)

                        ForEach(Array(draft.flights.legs.enumerated()), id: \.element.id) { idx, leg in
                            DisclosureGroup(
                                isExpanded: Binding(
                                    get: { !collapsedFlightLegIds.contains(leg.id) },
                                    set: { expanded in
                                        if expanded {
                                            collapsedFlightLegIds.remove(leg.id)
                                        } else {
                                            collapsedFlightLegIds.insert(leg.id)
                                        }
                                    }
                                )
                            ) {
                                flightLegEditorContent(idx: idx, legId: leg.id)
                            } label: {
                                flightLegSummaryRow(idx: idx)
                            }
                            .tint(.green)
                            .padding(12)
                            .background(Color.black.opacity(0.25))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        Button {
                            var t = draft
                            t.flights.legs.append(TripFlightLeg())
                            draft = t
                        } label: {
                            Label("Add flight leg", systemImage: "airplane")
                                .font(.subheadline.bold())
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.white.opacity(0.2))
                                .cornerRadius(10)
                        }
                        .buttonStyle(.plain)

                        sectionTitle("Notes")
                        TextField("Trip notes", text: $draft.notes, axis: .vertical)
                            .lineLimit(3...6)
                            .padding(12)
                            .background(Color(.systemGray6).opacity(0.25))
                            .cornerRadius(10)
                            .foregroundColor(.white)
                    }
                    .padding(16)
                }
            }
            .navigationTitle(existingId == nil ? "New trip" : "Edit trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.green)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .foregroundColor(.green)
                }
            }
            .adaptiveSheet(isPresented: $showPrimaryPlacePicker) {
                MapPlacePickerView(
                    navigationTitle: "Trip location",
                    defaultLandmarkQuery: "casino",
                    showsCurrentLocationButton: true,
                    name: $draft.primaryLocationName,
                    subtitle: $draft.primarySubtitle,
                    latitude: $draft.primaryLatitude,
                    longitude: $draft.primaryLongitude
                )
                .environmentObject(settingsStore)
            }
            .adaptiveSheet(item: $lodgingMapPick) { pick in
                lodgingMapSheet(for: pick)
            }
            .adaptiveSheet(item: $flightEndpointPick) { pick in
                flightEndpointSheet(legId: pick.legId, isOrigin: pick.isOrigin)
            }
            .onAppear {
                applyInitialEligibleSessionsIfNeeded()
            }
            .onChange(of: sessionListFilterStart) { newStart in
                if newStart > sessionListFilterEnd {
                    sessionListFilterEnd = newStart
                }
            }
            .onChange(of: sessionListFilterEnd) { newEnd in
                if newEnd < sessionListFilterStart {
                    sessionListFilterStart = newEnd
                }
            }
            .onChange(of: draft.startDate) { _ in
                mergeEligibleSessionsIntoSelection()
            }
            .onChange(of: draft.endDate) { _ in
                mergeEligibleSessionsIntoSelection()
            }
        }
    }

    /// New trips: default selection to all date-eligible sessions once (not on every `onAppear`).
    private func applyInitialEligibleSessionsIfNeeded() {
        guard existingId == nil, !didApplyNewTripSessionDefault else { return }
        didApplyNewTripSessionDefault = true
        draft.sessionIDs = Array(eligibleSessionIDs)
    }

    /// When dates change, ensure every session that overlaps the new window stays selected (add only).
    private func mergeEligibleSessionsIntoSelection() {
        draft.sessionIDs = Array(Set(draft.sessionIDs).union(eligibleSessionIDs))
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .foregroundColor(.white)
    }

    private func locationDetailLabel(lineCount: Int, index: Int) -> String? {
        switch (lineCount, index) {
        case (3, 0): return "City"
        case (3, 1): return "State / province"
        case (3, 2): return "Country"
        case (2, 0): return "City"
        case (2, 1): return "State / province"
        default: return nil
        }
    }

    private var primaryLocationBubble: some View {
        let nameSet = !draft.primaryLocationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let lines = draft.primaryLocationSubtitleLines
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.title2)
                    .foregroundColor(.green)
                    .frame(width: 36, height: 36)
                    .background(Color.green.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    if nameSet {
                        Text(draft.primaryLocationName)
                            .font(.headline.weight(.semibold))
                            .foregroundColor(.white)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if lines.isEmpty {
                        Text(nameSet ? "Add map search to fill in city, region, and country." : "No place selected yet.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.65))
                    } else {
                        ForEach(Array(lines.enumerated()), id: \.offset) { pair in
                            VStack(alignment: .leading, spacing: 2) {
                                if let lab = locationDetailLabel(lineCount: lines.count, index: pair.offset) {
                                    Text(lab)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundColor(.white.opacity(0.55))
                                        .textCase(.uppercase)
                                }
                                Text(pair.element)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.white.opacity(0.92))
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }

            Button {
                showPrimaryPlacePicker = true
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
        .background(Color.black.opacity(0.28))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var accommodationsBubble: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Hotels, homes, and other stays. Each can have its own dates; new ones default to this trip’s dates.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)

            ForEach(draft.lodgings) { place in
                lodgingRow(place: place)
            }

            HStack(spacing: 16) {
                Button {
                    let new = TripLodgingPlace(
                        kind: .hotel,
                        name: "",
                        stayStartDate: draft.startDate,
                        stayEndDate: draft.endDate
                    )
                    draft.lodgings.append(new)
                    lodgingMapPick = LodgingMapPick(lodgingId: new.id)
                } label: {
                    Label("Add hotel", systemImage: "bed.double.fill")
                        .font(.caption.bold())
                }
                .foregroundColor(.green)
                Button {
                    let new = TripLodgingPlace(
                        kind: .home,
                        name: "",
                        stayStartDate: draft.startDate,
                        stayEndDate: draft.endDate
                    )
                    draft.lodgings.append(new)
                    lodgingMapPick = LodgingMapPick(lodgingId: new.id)
                } label: {
                    Label("Add home", systemImage: "house.fill")
                        .font(.caption.bold())
                }
                .foregroundColor(.green)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color.black.opacity(0.28))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func lodgingMapSheet(for pick: LodgingMapPick) -> some View {
        if draft.lodgings.contains(where: { $0.id == pick.lodgingId }) {
            lodgingMapPickerContent(lodgingId: pick.lodgingId)
        } else {
            Text("This stay was removed.")
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
        }
    }

    private func lodgingMapPickerContent(lodgingId: UUID) -> some View {
        let meta = lodgingSearchMeta(for: lodgingId)
        return MapPlacePickerView(
            navigationTitle: meta.title,
            defaultLandmarkQuery: meta.query,
            showsCurrentLocationButton: true,
            name: lodgingNameBinding(lodgingId: lodgingId),
            subtitle: lodgingSubtitleBinding(lodgingId: lodgingId),
            latitude: lodgingLatBinding(lodgingId: lodgingId),
            longitude: lodgingLonBinding(lodgingId: lodgingId)
        )
        .environmentObject(settingsStore)
    }

    private func lodgingSearchMeta(for lodgingId: UUID) -> (title: String, query: String) {
        let kind = draft.lodgings.first(where: { $0.id == lodgingId })?.kind ?? .hotel
        switch kind {
        case .hotel:
            return ("Find a hotel", "hotel")
        case .home:
            return ("Find home or stay", "residential address")
        case .other:
            return ("Find a place", "lodging")
        }
    }

    private func lodgingRow(place: TripLodgingPlace) -> some View {
        let kind = place.kind
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(kind.label)
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                Button(role: .destructive) {
                    draft.lodgings.removeAll { $0.id == place.id }
                } label: {
                    Image(systemName: "trash")
                }
            }
            lodgingStayDatesBubble(lodgingId: place.id)
            TextField("Name", text: bindingLodging(place.id, keyPath: \.name))
                .padding(10)
                .background(Color(.systemGray6).opacity(0.2))
                .cornerRadius(8)
                .foregroundColor(.white)
            Button {
                lodgingMapPick = LodgingMapPick(lodgingId: place.id)
            } label: {
                Label("Search map", systemImage: "mappin.and.ellipse")
                    .font(.caption.bold())
            }
            .buttonStyle(.plain)
            .foregroundColor(.green)
        }
        .padding(12)
        .background(Color.black.opacity(0.25))
        .cornerRadius(12)
    }

    private func lodgingStayDatesBubble(lodgingId: UUID) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Stay from")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.85))
                DatePicker("", selection: lodgingStayStartBinding(lodgingId: lodgingId), displayedComponents: [.date])
                    .labelsHidden()
                    .tint(.green)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(Color.white.opacity(0.22))
                .frame(width: 1)
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 6) {
                Text("Stay through")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.85))
                DatePicker("", selection: lodgingStayEndBinding(lodgingId: lodgingId), displayedComponents: [.date])
                    .labelsHidden()
                    .tint(.green)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color(.systemGray6).opacity(0.2))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private func lodgingStayStartBinding(lodgingId: UUID) -> Binding<Date> {
        Binding(
            get: {
                guard let p = draft.lodgings.first(where: { $0.id == lodgingId }) else { return draft.startDate }
                return p.stayStartDate ?? draft.startDate
            },
            set: { v in
                if let idx = draft.lodgings.firstIndex(where: { $0.id == lodgingId }) {
                    draft.lodgings[idx].stayStartDate = v
                }
            }
        )
    }

    private func lodgingStayEndBinding(lodgingId: UUID) -> Binding<Date> {
        Binding(
            get: {
                guard let p = draft.lodgings.first(where: { $0.id == lodgingId }) else { return draft.endDate }
                return p.stayEndDate ?? draft.endDate
            },
            set: { v in
                if let idx = draft.lodgings.firstIndex(where: { $0.id == lodgingId }) {
                    draft.lodgings[idx].stayEndDate = v
                }
            }
        )
    }

    private func bindingLodging(_ lodgingId: UUID, keyPath: WritableKeyPath<TripLodgingPlace, String>) -> Binding<String> {
        Binding(
            get: { draft.lodgings.first(where: { $0.id == lodgingId })?[keyPath: keyPath] ?? "" },
            set: { newVal in
                if let idx = draft.lodgings.firstIndex(where: { $0.id == lodgingId }) {
                    var p = draft.lodgings[idx]
                    p[keyPath: keyPath] = newVal
                    draft.lodgings[idx] = p
                }
            }
        )
    }

    private func lodgingNameBinding(lodgingId: UUID) -> Binding<String> {
        Binding(
            get: { draft.lodgings.first(where: { $0.id == lodgingId })?.name ?? "" },
            set: { v in
                if let idx = draft.lodgings.firstIndex(where: { $0.id == lodgingId }) {
                    var p = draft.lodgings[idx]
                    p.name = v
                    draft.lodgings[idx] = p
                }
            }
        )
    }

    private func lodgingSubtitleBinding(lodgingId: UUID) -> Binding<String> {
        Binding(
            get: { draft.lodgings.first(where: { $0.id == lodgingId })?.subtitle ?? "" },
            set: { v in
                if let idx = draft.lodgings.firstIndex(where: { $0.id == lodgingId }) {
                    var p = draft.lodgings[idx]
                    p.subtitle = v
                    draft.lodgings[idx] = p
                }
            }
        )
    }

    private func lodgingLatBinding(lodgingId: UUID) -> Binding<Double?> {
        Binding(
            get: { draft.lodgings.first(where: { $0.id == lodgingId })?.latitude },
            set: { v in
                if let idx = draft.lodgings.firstIndex(where: { $0.id == lodgingId }) {
                    var p = draft.lodgings[idx]
                    p.latitude = v
                    draft.lodgings[idx] = p
                }
            }
        )
    }

    private func lodgingLonBinding(lodgingId: UUID) -> Binding<Double?> {
        Binding(
            get: { draft.lodgings.first(where: { $0.id == lodgingId })?.longitude },
            set: { v in
                if let idx = draft.lodgings.firstIndex(where: { $0.id == lodgingId }) {
                    var p = draft.lodgings[idx]
                    p.longitude = v
                    draft.lodgings[idx] = p
                }
            }
        )
    }

    private func sessionToggleRow(_ session: Session) -> some View {
        let on = draft.sessionIDs.contains(session.id)
        let inRange = eligibleSessionIDs.contains(session.id)
        return Button {
            if on {
                draft.sessionIDs.removeAll { $0 == session.id }
            } else {
                draft.sessionIDs.append(session.id)
            }
        } label: {
            HStack {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(on ? .green : .gray)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.casino).foregroundColor(.white).font(.subheadline.bold())
                    Text("\(session.game) · \(session.startTime.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                Spacer()
                if inRange {
                    Text("In range")
                        .font(.caption2.bold())
                        .foregroundColor(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.85))
                        .cornerRadius(8)
                }
            }
            .padding(10)
            .background(Color(.systemGray6).opacity(inRange ? 0.22 : 0.15))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    private func legIndex(for id: UUID) -> Int? {
        draft.flights.legs.firstIndex { $0.id == id }
    }

    private func applyAirportCatalogPick(legId: UUID, isOrigin: Bool, entry: AirportPicklistEntry) {
        guard let idx = legIndex(for: legId) else { return }
        var t = draft
        if isOrigin {
            t.flights.legs[idx].originName = entry.storageCode
            t.flights.legs[idx].originLatitude = entry.latitude
            t.flights.legs[idx].originLongitude = entry.longitude
        } else {
            t.flights.legs[idx].destinationName = entry.storageCode
            t.flights.legs[idx].destinationLatitude = entry.latitude
            t.flights.legs[idx].destinationLongitude = entry.longitude
        }
        draft = t
        flightAirportField = nil
    }

    private func airportTypeahead(legId: UUID, idx: Int, isOrigin: Bool) -> some View {
        let q = isOrigin
            ? draft.flights.legs[idx].originName
            : draft.flights.legs[idx].destinationName
        let endpoint: FlightAirportEndpoint = isOrigin ? .origin(legId) : .destination(legId)
        let isFocused = flightAirportField == endpoint
        return AirportTypeaheadDropdown(
            query: q,
            isFocused: isFocused
        ) { entry in
            applyAirportCatalogPick(legId: legId, isOrigin: isOrigin, entry: entry)
        }
    }

    private func applyPickedAirline(legId: UUID, entry: AirlinePicklistEntry) {
        guard let idx = legIndex(for: legId) else { return }
        var t = draft
        t.flights.legs[idx].airline = entry.storedDisplayValue
        draft = t
    }

    @ViewBuilder
    private func airlineTypeaheadSuggestions(legId: UUID, idx: Int) -> some View {
        let query = draft.flights.legs[idx].airline
        let matches = AirlineCatalog.matching(query, limit: 10)
        if airlineFieldLegId == legId, !matches.isEmpty {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(matches.enumerated()), id: \.offset) { idx, entry in
                        Button {
                            applyPickedAirline(legId: legId, entry: entry)
                            airlineFieldLegId = nil
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.white)
                                Text("IATA \(entry.iata) · ICAO \(entry.icao)")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.65))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if idx < matches.count - 1 {
                            Divider()
                                .background(Color.white.opacity(0.12))
                        }
                    }
                }
            }
            .frame(maxHeight: 200)
            .background(Color.black.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .padding(.top, 6)
        }
    }

    private func flightLegSummaryRow(idx: Int) -> some View {
        let leg = draft.flights.legs[idx]
        let o = leg.originName.trimmingCharacters(in: .whitespacesAndNewlines)
        let d = leg.destinationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let origin = o.isEmpty ? "—" : o
        let dest = d.isEmpty ? "—" : d
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Leg \(idx + 1)")
                .font(.subheadline.weight(.bold))
                .foregroundColor(.white)
            Image(systemName: "airplane")
                .font(.caption.weight(.semibold))
                .foregroundColor(.green.opacity(0.9))
            Text("\(origin) → \(dest)")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)
            Spacer(minLength: 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Leg \(idx + 1), from \(origin) to \(dest)")
    }

    private func flightLegEditorContent(idx: Int, legId: UUID) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Leg \(idx + 1)")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white.opacity(0.9))
                Spacer()
                Button(role: .destructive) {
                    var t = draft
                    t.flights.legs.removeAll { $0.id == legId }
                    draft = t
                    collapsedFlightLegIds.remove(legId)
                } label: {
                    Image(systemName: "trash")
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                TextField("Airline — type name, IATA, or ICAO", text: bindingLeg(idx, \.airline))
                    .padding(10)
                    .background(Color(.systemGray6).opacity(0.2))
                    .cornerRadius(8)
                    .foregroundColor(.white)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($airlineFieldLegId, equals: legId)
                airlineTypeaheadSuggestions(legId: legId, idx: idx)
            }
            TextField("Flight number", text: bindingLeg(idx, \.flightNumber))
                .padding(10)
                .background(Color(.systemGray6).opacity(0.2))
                .cornerRadius(8)
                .foregroundColor(.white)
            TextField("Seat", text: bindingLeg(idx, \.seat))
                .padding(10)
                .background(Color(.systemGray6).opacity(0.2))
                .cornerRadius(8)
                .foregroundColor(.white)
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Origin").font(.caption2).foregroundColor(.gray)
                    VStack(alignment: .leading, spacing: 0) {
                        TextField("City, airport, or code", text: bindingLeg(idx, \.originName))
                            .padding(8)
                            .background(Color(.systemGray6).opacity(0.18))
                            .cornerRadius(8)
                            .foregroundColor(.white)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($flightAirportField, equals: .origin(legId))
                        airportTypeahead(legId: legId, idx: idx, isOrigin: true)
                    }
                    Button("Map") {
                        flightEndpointPick = FlightEndpointPick(legId: legId, isOrigin: true)
                    }
                        .font(.caption.bold())
                        .foregroundColor(.green)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Destination").font(.caption2).foregroundColor(.gray)
                    VStack(alignment: .leading, spacing: 0) {
                        TextField("City, airport, or code", text: bindingLeg(idx, \.destinationName))
                            .padding(8)
                            .background(Color(.systemGray6).opacity(0.18))
                            .cornerRadius(8)
                            .foregroundColor(.white)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($flightAirportField, equals: .destination(legId))
                        airportTypeahead(legId: legId, idx: idx, isOrigin: false)
                    }
                    Button("Map") {
                        flightEndpointPick = FlightEndpointPick(legId: legId, isOrigin: false)
                    }
                        .font(.caption.bold())
                        .foregroundColor(.green)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if draft.flights.legs[idx].departureDate != nil {
                DatePicker(
                    "Departure",
                    selection: Binding(
                        get: { draft.flights.legs[idx].departureDate ?? Date() },
                        set: { v in var l = draft.flights.legs[idx]; l.departureDate = v; draft.flights.legs[idx] = l }
                    ),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .tint(.green)
                .foregroundColor(.white)
                Button("Clear departure date") {
                    var l = draft.flights.legs[idx]
                    l.departureDate = nil
                    draft.flights.legs[idx] = l
                }
                .font(.caption)
                .foregroundColor(.orange)
            } else {
                Button("Add departure date & time") {
                    var l = draft.flights.legs[idx]
                    l.departureDate = Date()
                    draft.flights.legs[idx] = l
                }
                .font(.caption.bold())
                .foregroundColor(.green)
            }
        }
        .padding(.top, 6)
    }

    private func bindingLeg(_ idx: Int, _ keyPath: WritableKeyPath<TripFlightLeg, String>) -> Binding<String> {
        Binding(
            get: { draft.flights.legs[idx][keyPath: keyPath] },
            set: { newVal in
                var l = draft.flights.legs[idx]
                l[keyPath: keyPath] = newVal
                draft.flights.legs[idx] = l
            }
        )
    }

    private func flightEndpointSheet(legId: UUID, isOrigin: Bool) -> some View {
        let idxOpt = legIndex(for: legId)
        if let idx = idxOpt {
            return AnyView(
                MapPlacePickerView(
                    navigationTitle: isOrigin ? "Origin airport" : "Destination airport",
                    defaultLandmarkQuery: "airport",
                    allowsAirportCodeSearch: true,
                    preferIataAirportCode: true,
                    name: Binding(
                        get: { isOrigin ? draft.flights.legs[idx].originName : draft.flights.legs[idx].destinationName },
                        set: { v in
                            var l = draft.flights.legs[idx]
                            if isOrigin { l.originName = v } else { l.destinationName = v }
                            draft.flights.legs[idx] = l
                        }
                    ),
                    subtitle: Binding.constant(""),
                    latitude: Binding(
                        get: { isOrigin ? draft.flights.legs[idx].originLatitude : draft.flights.legs[idx].destinationLatitude },
                        set: { v in
                            var l = draft.flights.legs[idx]
                            if isOrigin { l.originLatitude = v } else { l.destinationLatitude = v }
                            draft.flights.legs[idx] = l
                        }
                    ),
                    longitude: Binding(
                        get: { isOrigin ? draft.flights.legs[idx].originLongitude : draft.flights.legs[idx].destinationLongitude },
                        set: { v in
                            var l = draft.flights.legs[idx]
                            if isOrigin { l.originLongitude = v } else { l.destinationLongitude = v }
                            draft.flights.legs[idx] = l
                        }
                    )
                )
                .environmentObject(settingsStore)
            )
        }
        return AnyView(
            Text("This flight leg was removed.")
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
        )
    }

    private func save() {
        validationMessage = nil
        if draft.startDate > draft.endDate {
            validationMessage = "End date must be on or after the start date."
            return
        }
        let hasTitle = !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasLoc = !draft.primaryLocationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !hasTitle && !hasLoc {
            validationMessage = "Add a trip title or a primary location."
            return
        }
        draft.lodgings = draft.lodgings.filter {
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        for place in draft.lodgings {
            let s = place.effectiveStayStart(trip: draft)
            let e = place.effectiveStayEnd(trip: draft)
            if s > e {
                validationMessage = "“\(place.name)” stay start must be on or before stay end."
                return
            }
        }
        if existingId != nil {
            tripStore.update(draft)
        } else {
            tripStore.add(draft)
        }
        dismiss()
    }
}

/// Runs airport matching off the main actor with a short debounce so typing stays responsive.
private struct AirportTypeaheadDropdown: View {
    var query: String
    var isFocused: Bool
    var onPick: (AirportPicklistEntry) -> Void

    @State private var matches: [AirportPicklistEntry] = []

    var body: some View {
        Group {
            if isFocused, !matches.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(matches.enumerated()), id: \.offset) { mIdx, entry in
                            Button {
                                onPick(entry)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.picklistTitle)
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.white)
                                    Text(entry.picklistSubtitle)
                                        .font(.caption2)
                                        .foregroundColor(.white.opacity(0.65))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if mIdx < matches.count - 1 {
                                Divider().background(Color.white.opacity(0.12))
                            }
                        }
                    }
                }
                .frame(maxHeight: 176)
                .background(Color.black.opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
                .padding(.top, 4)
            }
        }
        .task(id: "\(isFocused)-\(query)") {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isFocused, !trimmed.isEmpty else {
                await MainActor.run { matches = [] }
                return
            }
            let q = trimmed
            let delayNs: UInt64 = q.count >= 3 ? 18_000_000 : 42_000_000
            try? await Task.sleep(nanoseconds: delayNs)
            guard !Task.isCancelled else { return }
            let found = await Task.detached(priority: .userInitiated) {
                AirportCatalog.matching(q, limit: 12)
            }.value
            guard !Task.isCancelled else { return }
            await MainActor.run { matches = found }
        }
    }
}

private struct LodgingMapPick: Identifiable {
    var id: UUID { lodgingId }
    let lodgingId: UUID
}

private struct FlightEndpointPick: Identifiable {
    var id: String { "\(legId.uuidString)-\(isOrigin ? "o" : "d")" }
    let legId: UUID
    let isOrigin: Bool
}

