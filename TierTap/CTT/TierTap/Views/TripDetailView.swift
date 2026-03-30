import SwiftUI
import UIKit

struct TripDetailView: View {
    let tripId: UUID

    @EnvironmentObject var tripStore: TripStore
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var showEditor = false
    @State private var showDeleteConfirm = false
    @State private var shareImageItem: ShareableImageItem?
    @State private var selectedSession: Session?
    @State private var legForMap: TripFlightLeg?
    @State private var cameraPicker = false
    @State private var libraryPicker = false
    @State private var pickedImage: UIImage?
    @State private var showAddSessionsSheet = false

    private var trip: Trip? {
        tripStore.trips.first { $0.id == tripId }
    }

    private func linkedSessions(for t: Trip) -> [Session] {
        let idSet = Set(t.sessionIDs)
        return sessionStore.sessions
            .filter { idSet.contains($0.id) }
            .sorted { ($0.endTime ?? $0.startTime) > ($1.endTime ?? $1.startTime) }
    }

    var body: some View {
        Group {
            if let t = trip {
                detailContent(t)
            } else {
                missingTripView
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    if trip != nil {
                        Button {
                            prepareShare()
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .foregroundColor(.white)
                        .accessibilityLabel("Share trip summary")
                        Menu {
                            Button {
                                showEditor = true
                            } label: {
                                LocalizedLabel(title: "Edit trip", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                showDeleteConfirm = true
                            } label: {
                                LocalizedLabel(title: "Delete trip", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .foregroundColor(.white)
                        }
                    }
                }
            }
        }
        .adaptiveSheet(isPresented: $showEditor) {
            if let t = trip {
                TripEditorView(trip: t)
                    .environmentObject(tripStore)
                    .environmentObject(sessionStore)
                    .environmentObject(settingsStore)
            }
        }
        .adaptiveSheet(isPresented: $showAddSessionsSheet) {
            TripLinkSessionsSheet(tripId: tripId)
                .environmentObject(tripStore)
                .environmentObject(sessionStore)
                .environmentObject(settingsStore)
        }
        .adaptiveSheet(item: $selectedSession) { session in
            SessionDetailView(session: session)
                .environmentObject(sessionStore)
                .environmentObject(settingsStore)
        }
        .adaptiveSheet(item: $legForMap) { leg in
            flightMapSheet(leg)
        }
        .adaptiveSheet(item: $shareImageItem) { item in
            ShareSheet(items: [item.image])
        }
        .adaptiveSheet(isPresented: $cameraPicker) {
            ProfilePhotoCaptureView(image: $pickedImage, preferredSourceType: .camera)
        }
        .adaptiveSheet(isPresented: $libraryPicker) {
            ProfilePhotoCaptureView(image: $pickedImage, preferredSourceType: .photoLibrary)
        }
        .confirmationDialog("Delete this trip?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let t = trip {
                    tripStore.delete(t)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: pickedImage) { newVal in
            guard let img = newVal, let t = trip else { return }
            _ = tripStore.addPhoto(img, to: t.id)
            pickedImage = nil
        }
    }

    private var missingTripView: some View {
        ZStack {
            settingsStore.primaryGradient.ignoresSafeArea()
            L10nText("This trip no longer exists.")
                .foregroundColor(.white.opacity(0.9))
        }
        .localizedNavigationTitle("Trip")
        .onAppear { dismiss() }
    }

    private func detailContent(_ t: Trip) -> some View {
        ZStack {
            settingsStore.primaryGradient.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerBlock(t)

                    if !t.lodgings.isEmpty {
                        lodgingsBlock(t)
                    }

                    if !t.flights.legs.isEmpty {
                        flightsBlock(t)
                    }
                                        
                    photosSection(t)

                    sessionsBlock(for: t)

                    if !t.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        notesBlock(t)
                    }
                }
                .padding(16)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle(t.displayTitle)
    }

    private func tripDateMedium(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df.string(from: date)
    }

    private func headerBlock(_ t: Trip) -> some View {
        let hasLoc = !t.primaryLocationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let locLines = t.primaryLocationSubtitleLines
        let datesColumn = VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                L10nText("Start")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.72))
                Text(tripDateMedium(t.startDate))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.green.opacity(0.95))
            }
            VStack(alignment: .leading, spacing: 2) {
                L10nText("End")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.72))
                Text(tripDateMedium(t.endDate))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.green.opacity(0.95))
            }
        }
        let locationColumn = VStack(alignment: .trailing, spacing: 4) {
            Text(t.primaryLocationName)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .fixedSize(horizontal: false, vertical: true)
            if !locLines.isEmpty {
                ForEach(Array(locLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.82))
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        return Group {
            if hasLoc {
                HStack(alignment: .top, spacing: 14) {
                    datesColumn
                    locationColumn
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                datesColumn
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.black.opacity(0.28))
        .cornerRadius(14)
    }

    private func photosSection(_ t: Trip) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                L10nText("Photos")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Button {
                    cameraPicker = true
                } label: {
                    Image(systemName: "camera.fill")
                }
                .foregroundColor(.green)
                Button {
                    libraryPicker = true
                } label: {
                    Image(systemName: "photo.on.rectangle")
                }
                .foregroundColor(.green)
            }

            if t.photoFilenames.isEmpty {
                L10nText("Add photos from your camera or library.")
                    .font(.caption)
                    .foregroundColor(.gray)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(t.photoFilenames, id: \.self) { name in
                            ZStack(alignment: .topTrailing) {
                                if let ui = tripStore.loadPhoto(tripId: t.id, filename: name) {
                                    Image(uiImage: ui)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 120, height: 120)
                                        .clipped()
                                        .cornerRadius(12)
                                } else {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.white.opacity(0.08))
                                        .frame(width: 120, height: 120)
                                        .overlay(
                                            Image(systemName: "photo")
                                                .foregroundColor(.gray)
                                        )
                                }
                                Button {
                                    tripStore.removePhoto(tripId: t.id, filename: name)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .black.opacity(0.55))
                                }
                                .padding(4)
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Color.black.opacity(0.22))
        .cornerRadius(14)
    }

    private func lodgingsBlock(_ t: Trip) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            L10nText("Where you stayed")
                .font(.headline)
                .foregroundColor(.white)
            ForEach(t.lodgings) { place in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(place.kind.label): \(place.name)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                    Text(place.stayRangeLabel(trip: t))
                        .font(.caption)
                        .foregroundColor(.green.opacity(0.95))
                    if !place.subtitle.isEmpty {
                        Text(place.subtitle)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.black.opacity(0.22))
        .cornerRadius(14)
    }

    private func flightLegLabel(_ leg: TripFlightLeg) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text([leg.airline, leg.flightNumber.isEmpty ? nil : "#\(leg.flightNumber)"]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: " "))
                .font(.subheadline.bold())
                .foregroundColor(.white)
                Spacer()
                if leg.hasRoute {
                    Image(systemName: "map")
                        .foregroundColor(.cyan)
                }
            }
            Text("\(leg.originName) → \(leg.destinationName)")
                .font(.caption)
                .foregroundColor(.white.opacity(0.88))
            if !leg.seat.isEmpty {
                Text("Seat \(leg.seat)")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            if !leg.hasRoute {
                L10nText("Add origin & destination on the map in Edit to see the route.")
                    .font(.caption2)
                    .foregroundColor(.orange.opacity(0.9))
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.06))
        .cornerRadius(12)
    }

    private func flightsBlock(_ t: Trip) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                L10nText("Flights")
                    .font(.headline)
                    .foregroundColor(.white)
                Text("(\(t.flights.pattern.label))")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.65))
            }
            ForEach(t.flights.legs) { leg in
                Group {
                    if leg.hasRoute {
                        Button {
                            legForMap = leg
                        } label: {
                            flightLegLabel(leg)
                        }
                        .buttonStyle(.plain)
                    } else {
                        flightLegLabel(leg)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.black.opacity(0.22))
        .cornerRadius(14)
    }

    private func sessionsBlock(for t: Trip) -> some View {
        let rows = linkedSessions(for: t)
        let isCurrent = t.timelineStatus() == .current
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sessions (\(rows.count))")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer(minLength: 8)
                if isCurrent {
                    Button {
                        showAddSessionsSheet = true
                    } label: {
                        LocalizedLabel(title: "Add", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.green)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add sessions to this trip")
                }
            }
            if rows.isEmpty {
                Text(isCurrent
                     ? "No sessions linked yet. Tap Add to pick completed sessions, or edit the trip for full options."
                     : "No sessions linked. Edit the trip to attach sessions.")
                    .font(.caption)
                    .foregroundColor(.gray)
            } else {
                ForEach(rows) { session in
                    Button {
                        selectedSession = session
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.casino)
                                    .font(.subheadline.bold())
                                    .foregroundColor(.white)
                                Text(session.game)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            if session.totalComp > 0, let ev = session.expectedValue {
                                Text(ev >= 0 ? "EV +\(settingsStore.currencySymbol)\(ev)" : "EV -\(settingsStore.currencySymbol)\(abs(ev))")
                                    .font(.caption.bold())
                                    .foregroundColor(ev >= 0 ? .green : .red)
                            } else if let wl = session.winLoss {
                                Text(wl >= 0 ? "+\(settingsStore.currencySymbol)\(wl)" : "-\(settingsStore.currencySymbol)\(abs(wl))")
                                    .font(.caption.bold())
                                    .foregroundColor(wl >= 0 ? .green : .red)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.black.opacity(0.22))
        .cornerRadius(14)
    }

    private func notesBlock(_ t: Trip) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            L10nText("Notes")
                .font(.headline)
                .foregroundColor(.white)
            Text(t.notes)
                .font(.body)
                .foregroundColor(.white.opacity(0.9))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.black.opacity(0.22))
        .cornerRadius(14)
    }

    private func flightMapSheet(_ leg: TripFlightLeg) -> some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                if let o = leg.originCoordinate, let d = leg.destinationCoordinate {
                    FlightRouteMapView(
                        origin: o,
                        destination: d,
                        originLabel: leg.originName,
                        destinationLabel: leg.destinationName
                    )
                    .cornerRadius(16)
                    .padding()
                } else {
                    L10nText("Missing coordinates for this leg.")
                        .foregroundColor(.white)
                }
            }
            .localizedNavigationTitle("Flight route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { legForMap = nil }
                        .foregroundColor(.green)
                }
            }
        }
    }

    private func prepareShare() {
        guard let t = trip else { return }
        let tripPhotos = t.photoFilenames.compactMap { tripStore.loadPhoto(tripId: t.id, filename: $0) }
        Task { @MainActor in
            if let image = await TripShareImageBuilder.render(
                trip: t,
                sessions: linkedSessions(for: t),
                tripPhotos: tripPhotos,
                settingsStore: settingsStore
            ) {
                shareImageItem = ShareableImageItem(image: image)
            }
        }
    }
}
