import SwiftUI

/// Fixed-layout summary for `ImageRenderer` / sharing.
struct TripShareCardView: View {
    let trip: Trip
    let sessions: [Session]
    var coverImage: UIImage?
    /// Map snapshot of flight legs (great-circle routes), when legs have coordinates.
    var flightRouteImage: UIImage?

    @EnvironmentObject var settingsStore: SettingsStore

    private var dateRangeText: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return "\(f.string(from: trip.startDate)) – \(f.string(from: trip.endDate))"
    }

    private var sessionLines: [String] {
        sessions.prefix(8).map { s in
            let wl: String
            if let w = s.winLoss {
                let sym = settingsStore.currencySymbol
                wl = w >= 0 ? "+\(sym)\(w)" : "-\(sym)\(abs(w))"
            } else {
                wl = "—"
            }
            return "\(s.casino) · \(s.game) · \(wl)"
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.09, blue: 0.18),
                    Color(red: 0.12, green: 0.05, blue: 0.22)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("TierTap Trip")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white.opacity(0.75))
                        Text(trip.displayTitle)
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(3)
                            .minimumScaleFactor(0.7)
                    }
                    Spacer()
                }

                Text(dateRangeText)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.green.opacity(0.95))

                if !trip.primaryLocationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label {
                        Text(trip.primaryLocationName)
                            .font(.body.weight(.semibold))
                            .foregroundColor(.white)
                    } icon: {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundColor(.cyan)
                    }
                    if !trip.primarySubtitle.isEmpty {
                        Text(trip.primarySubtitle)
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }

                if let img = coverImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(height: flightRouteImage != nil ? 170 : 220)
                        .clipped()
                        .cornerRadius(14)
                }

                if let route = flightRouteImage {
                    Image(uiImage: route)
                        .resizable()
                        .scaledToFill()
                        .frame(height: coverImage != nil ? 170 : 220)
                        .clipped()
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.cyan.opacity(0.35), lineWidth: 1)
                        )
                }

                if !trip.lodgings.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Stay")
                            .font(.headline)
                            .foregroundColor(.white)
                        ForEach(trip.lodgings) { place in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("• \(place.kind.label): \(place.name)")
                                    .font(.footnote)
                                    .foregroundColor(.white.opacity(0.92))
                                Text(place.stayRangeLabel(trip: trip))
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.78))
                            }
                        }
                    }
                }

                if !trip.flights.legs.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Flights")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text("(\(trip.flights.pattern.label))")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        ForEach(trip.flights.legs) { leg in
                            let line = [
                                leg.airline,
                                leg.flightNumber.isEmpty ? nil : "#\(leg.flightNumber)",
                                leg.seat.isEmpty ? nil : "Seat \(leg.seat)"
                            ].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
                            VStack(alignment: .leading, spacing: 2) {
                                if !line.isEmpty {
                                    Text(line)
                                        .font(.footnote.weight(.semibold))
                                        .foregroundColor(.white.opacity(0.95))
                                }
                                Text("\(leg.originName) → \(leg.destinationName)")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.85))
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Sessions (\(sessions.count))")
                        .font(.headline)
                        .foregroundColor(.white)
                    if sessions.isEmpty {
                        Text("No sessions linked.")
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.7))
                    } else {
                        ForEach(Array(sessionLines.enumerated()), id: \.offset) { _, line in
                            Text("• \(line)")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.88))
                                .lineLimit(2)
                        }
                        if sessions.count > sessionLines.count {
                            Text("…and \(sessions.count - sessionLines.count) more")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                }

                if !trip.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(trip.notes)
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(8)
                }

                Spacer(minLength: 0)

                Text("Shared from TierTap")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(28)
        }
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}

enum TripShareImageBuilder {
    @MainActor
    static func render(
        trip: Trip,
        sessions: [Session],
        coverImage: UIImage?,
        settingsStore: SettingsStore
    ) async -> UIImage? {
        let mapH: CGFloat = coverImage != nil ? 200 : 240
        let routeImage = await TripFlightRouteSnapshot.makeImage(
            legs: trip.flights.legs,
            mapSize: CGSize(width: 420, height: mapH)
        )
        let card = TripShareCardView(
            trip: trip,
            sessions: sessions,
            coverImage: coverImage,
            flightRouteImage: routeImage
        )
        .environmentObject(settingsStore)
        let renderer = ImageRenderer(content: card)
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage
    }
}
