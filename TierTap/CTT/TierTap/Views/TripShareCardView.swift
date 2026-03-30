import SwiftUI
import UIKit

/// Padding and inner width shared by the card and map snapshot so bitmaps match the layout slot.
private enum TripShareLayoutMetrics {
    /// 420pt card with 28pt side padding → 364pt content width (baseline for scaling photo/map heights).
    static let referenceContentWidth: CGFloat = 364

    static func horizontalPadding(cardWidth: CGFloat) -> CGFloat {
        min(28, max(16, cardWidth * 0.065))
    }

    static func contentWidth(cardWidth: CGFloat) -> CGFloat {
        cardWidth - 2 * horizontalPadding(cardWidth: cardWidth)
    }
}

/// Fixed-layout summary for `ImageRenderer` / sharing.
struct TripShareCardView: View {
    let trip: Trip
    let sessions: [Session]
    /// Trip photos in gallery order (first is shown as the hero strip; rest as thumbnails).
    var tripPhotos: [UIImage] = []
    /// Map snapshot of flight legs (great-circle routes), when legs have coordinates.
    var flightRouteImage: UIImage?
    /// Horizontal layout width (points). Use ``TripShareImageBuilder/cardWidthPoints`` so the PNG fits phone share previews.
    var cardWidth: CGFloat

    @EnvironmentObject var settingsStore: SettingsStore

    private var dateRangeText: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return "\(f.string(from: trip.startDate)) – \(f.string(from: trip.endDate))"
    }

    private var coverImage: UIImage? { tripPhotos.first }

    /// Linked-session comp rollup (same notion as per-session totals in Session detail).
    private var tripCompTotal: Int {
        sessions.reduce(0) { $0 + $1.totalComp }
    }

    private var tripCompDollarsCredits: Int {
        sessions.reduce(0) { $0 + $1.totalCompDollarsCredits }
    }

    private var tripCompFoodBeverage: Int {
        sessions.reduce(0) { acc, s in
            acc + s.compEvents.filter { $0.kind == .foodBeverage }.reduce(0) { $0 + $1.amount }
        }
    }

    private var additionalTripPhotos: [UIImage] {
        Array(tripPhotos.dropFirst().prefix(8))
    }

    /// Up to two rows of four thumbnails so images stay legible on narrow cards.
    private var additionalTripPhotoRows: [[UIImage]] {
        let extras = additionalTripPhotos
        guard !extras.isEmpty else { return [] }
        let perRow = 4
        return stride(from: 0, to: extras.count, by: perRow).map { start in
            Array(extras[start..<min(start + perRow, extras.count)])
        }
    }

    private var sessionLines: [String] {
        sessions.prefix(8).map { s in
            let result: String
            let sym = settingsStore.currencySymbol
            if let ev = s.expectedValue {
                result = ev >= 0 ? "EV +\(sym)\(ev)" : "EV -\(sym)\(abs(ev))"
            } else if let w = s.winLoss {
                result = w >= 0 ? "+\(sym)\(w)" : "-\(sym)\(abs(w))"
            } else {
                result = "—"
            }
            return "\(s.casino) · \(s.game) · \(result)"
        }
    }

    /// Linked sessions with comps, oldest → newest by session start (for a readable comp list).
    private var sessionsChronological: [Session] {
        sessions.sorted { $0.startTime < $1.startTime }
    }

    /// Flat list of (session, comp) for share card detail rows.
    private var compRowsChronological: [(session: Session, comp: CompEvent)] {
        sessionsChronological.flatMap { s in
            s.compEvents.sorted { $0.timestamp < $1.timestamp }.map { (s, $0) }
        }
    }

    private var compRowsForShare: [(session: Session, comp: CompEvent)] {
        Array(compRowsChronological.prefix(14))
    }

    private var compRowsOverflowCount: Int {
        let n = compRowsChronological.count
        return n > 14 ? n - 14 : 0
    }

    /// Sum of per-session EV where cash-out (and thus EV) is known.
    private var tripExpectedValueSum: Int? {
        let values = sessions.compactMap(\.expectedValue)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }

    private func compKindLabel(_ c: CompEvent) -> String {
        if c.kind == .foodBeverage, let fb = c.foodBeverageKindDisplayLabel {
            return "\(c.kind.title) · \(fb)"
        }
        return c.kind.title
    }

    /// Sessions with a mood, oldest → newest (for trend / sparkline).
    private var moodsChronological: [SessionMood] {
        sessions
            .filter { $0.sessionMood != nil }
            .sorted { ($0.endTime ?? $0.startTime) < ($1.endTime ?? $1.startTime) }
            .compactMap(\.sessionMood)
    }

    private var tripMoodCounts: [(mood: SessionMood, count: Int)] {
        let grouped = Dictionary(grouping: moodsChronological, by: { $0 }).mapValues { $0.count }
        return SessionMood.allCases
            .compactMap { mood in (grouped[mood]).map { (mood: mood, count: $0) } }
            .filter { $0.count > 0 }
            .sorted { $0.count > $1.count }
    }

    /// Ordinal 0 (rough) … 8 (epic) for averaging and trend.
    private func moodOrdinal(_ mood: SessionMood) -> Int {
        guard let idx = SessionMood.allCases.firstIndex(of: mood) else { return 0 }
        return SessionMood.allCases.count - 1 - idx
    }

    /// First-half vs second-half average mood (chronological sessions with mood).
    private var moodTrendLabelAndColor: (text: String, color: Color)? {
        let moods = moodsChronological
        guard moods.count >= 2 else { return nil }
        let ordinals = moods.map { moodOrdinal($0) }
        let n = ordinals.count
        let mid = n / 2
        let firstAvg = Double(ordinals[0..<mid].reduce(0, +)) / Double(max(mid, 1))
        let secondAvg = Double(ordinals[mid..<n].reduce(0, +)) / Double(n - mid)
        let delta = secondAvg - firstAvg
        if delta > 1.0 {
            return ("Trend: improving", Color.green.opacity(0.95))
        }
        if delta < -1.0 {
            return ("Trend: cooling off", Color.orange.opacity(0.95))
        }
        return ("Trend: steady", Color.white.opacity(0.65))
    }

    private var tripMoodMaxCount: Double {
        max(tripMoodCounts.map { Double($0.count) }.max() ?? 1, 1)
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
                        L10nText("TierTap Trip")
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
                        .frame(width: contentInnerWidth, height: photoStripHeight)
                        .clipped()
                        .cornerRadius(14)
                }

                if let route = flightRouteImage {
                    Image(uiImage: route)
                        .resizable()
                        .scaledToFill()
                        .frame(width: contentInnerWidth, height: photoStripHeight)
                        .clipped()
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.cyan.opacity(0.35), lineWidth: 1)
                        )
                }

                if !trip.lodgings.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        L10nText("Stay")
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
                            L10nText("Flights")
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

                if !additionalTripPhotos.isEmpty {
                    let thumbSpacing: CGFloat = 8
                    let thumbH = max(76, min(photoStripHeight * 0.58, 118) * (contentInnerWidth / TripShareLayoutMetrics.referenceContentWidth))
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Photos (\(tripPhotos.count))")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white.opacity(0.78))
                        VStack(alignment: .leading, spacing: thumbSpacing) {
                            ForEach(Array(additionalTripPhotoRows.enumerated()), id: \.offset) { _, row in
                                let cols = row.count
                                let thumbW = (contentInnerWidth - thumbSpacing * CGFloat(cols - 1)) / CGFloat(cols)
                                HStack(spacing: thumbSpacing) {
                                    ForEach(Array(row.enumerated()), id: \.offset) { _, ui in
                                        Image(uiImage: ui)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: thumbW, height: thumbH)
                                            .clipped()
                                            .cornerRadius(10)
                                    }
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Sessions (\(sessions.count))")
                        .font(.headline)
                        .foregroundColor(.white)
                    if sessions.isEmpty {
                        L10nText("No sessions linked.")
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

                if let tripEV = tripExpectedValueSum {
                    VStack(alignment: .leading, spacing: 4) {
                        L10nText("Trip EV")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text("\(tripEV >= 0 ? "+" : "-")\(settingsStore.currencySymbol)\(abs(tripEV).formatted(.number.grouping(.automatic)))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(tripEV >= 0 ? Color.green.opacity(0.95) : Color.red.opacity(0.95))
                    }
                }

                if tripCompTotal > 0 || !compRowsChronological.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        LocalizedLabel(title: "Comps (trip)", systemImage: "gift.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                        if tripCompTotal > 0 {
                            Text("Total comps \(settingsStore.currencySymbol)\(tripCompTotal.formatted(.number.grouping(.automatic)))")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.green.opacity(0.95))
                            if tripCompDollarsCredits > 0 {
                                Text("• \(CompKind.dollarsCredits.title): \(settingsStore.currencySymbol)\(tripCompDollarsCredits.formatted(.number.grouping(.automatic)))")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.88))
                            }
                            if tripCompFoodBeverage > 0 {
                                Text("• \(CompKind.foodBeverage.title): \(settingsStore.currencySymbol)\(tripCompFoodBeverage.formatted(.number.grouping(.automatic)))")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.88))
                            }
                        }
                        if !compRowsChronological.isEmpty {
                            L10nText("Items")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.white.opacity(0.78))
                                .padding(.top, tripCompTotal > 0 ? 4 : 0)
                            ForEach(compRowsForShare, id: \.comp.id) { row in
                                HStack(alignment: .top, spacing: 10) {
                                    CompEventPhotoThumbnail(compEventID: row.comp.id, side: 44, showPlaceholderWhenMissing: true)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(compKindLabel(row.comp)) · \(settingsStore.currencySymbol)\(row.comp.amount.formatted(.number.grouping(.automatic)))")
                                            .font(.caption.weight(.semibold))
                                            .foregroundColor(.white.opacity(0.95))
                                        Text("\(row.session.casino) · \(row.session.game)")
                                            .font(.caption2)
                                            .foregroundColor(.white.opacity(0.72))
                                        Text(row.comp.timestamp, style: .time)
                                            .font(.caption2)
                                            .foregroundColor(.white.opacity(0.55))
                                    }
                                    Spacer(minLength: 0)
                                }
                            }
                            if compRowsOverflowCount > 0 {
                                Text("…and \(compRowsOverflowCount) more")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                    }
                }

                if !tripMoodCounts.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        LocalizedLabel(title: "Session moods", systemImage: "face.smiling.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                        if moodsChronological.count >= 2 {
                            TripShareMoodSparkline(
                                moods: moodsChronological,
                                lineGradient: settingsStore.primaryGradient
                            )
                                .frame(width: contentInnerWidth, height: 40)
                            if let trend = moodTrendLabelAndColor {
                                Text(trend.text)
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(trend.color)
                            }
                        }
                        ForEach(tripMoodCounts.prefix(6), id: \.mood) { row in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(row.mood.label)
                                        .font(.caption2)
                                        .foregroundColor(.white.opacity(0.92))
                                    Spacer()
                                    Text("\(row.count)×")
                                        .font(.caption2.bold())
                                        .foregroundColor(.white.opacity(0.55))
                                }
                                GeometryReader { geo in
                                    let barW = max(2, geo.size.width * CGFloat(Double(row.count) / tripMoodMaxCount))
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.white.opacity(0.12))
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(settingsStore.primaryGradient)
                                            .frame(width: barW)
                                    }
                                }
                                .frame(height: 8)
                            }
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

                L10nText("Shared from TierTap")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(cardHorizontalPadding)
        }
        .frame(width: cardWidth)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var cardHorizontalPadding: CGFloat {
        TripShareLayoutMetrics.horizontalPadding(cardWidth: cardWidth)
    }

    private var contentInnerWidth: CGFloat {
        TripShareLayoutMetrics.contentWidth(cardWidth: cardWidth)
    }

    /// Height for cover / route strips, scaled to **content** width (avoids unconstrained bitmaps).
    private var photoStripHeight: CGFloat {
        let base: CGFloat = flightRouteImage != nil && coverImage != nil ? 170 : 220
        let w = contentInnerWidth
        let scale = w / TripShareLayoutMetrics.referenceContentWidth
        return (base * scale).rounded(.down)
    }
}

/// Chronological mood sparkline (better mood toward the top of the strip).
private struct TripShareMoodSparkline: View {
    let moods: [SessionMood]
    let lineGradient: LinearGradient

    private var maxIdx: CGFloat {
        CGFloat(SessionMood.allCases.count - 1)
    }

    private func yForMood(_ mood: SessionMood, height: CGFloat) -> CGFloat {
        guard let idx = SessionMood.allCases.firstIndex(of: mood) else { return height / 2 }
        let ord = maxIdx - CGFloat(idx)
        let pad: CGFloat = 5
        return pad + (1 - ord / maxIdx) * max(0, height - 2 * pad)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.08))
                Path { path in
                    for (i, m) in moods.enumerated() {
                        let x = CGFloat(i) / CGFloat(moods.count - 1) * w
                        let y = yForMood(m, height: h)
                        if i == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(lineGradient, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                ForEach(Array(moods.enumerated()), id: \.offset) { i, m in
                    let x = CGFloat(i) / CGFloat(moods.count - 1) * w
                    let y = yForMood(m, height: h)
                    Circle()
                        .fill(Color.white.opacity(0.95))
                        .frame(width: 6, height: 6)
                        .position(x: x, y: y)
                }
            }
        }
    }
}

enum TripShareImageBuilder {
    /// Card width in points: slightly narrower than the screen so share-sheet and Messages previews don’t clip sides.
    @MainActor
    static var cardWidthPoints: CGFloat {
        let w = UIScreen.main.bounds.width
        let margin: CGFloat = 36
        let capped = min(420, w - margin)
        return max(300, capped).rounded(.down)
    }

    @MainActor
    static func render(
        trip: Trip,
        sessions: [Session],
        tripPhotos: [UIImage],
        settingsStore: SettingsStore
    ) async -> UIImage? {
        let width = cardWidthPoints
        let innerW = TripShareLayoutMetrics.contentWidth(cardWidth: width)
        let mapBaseH: CGFloat = !tripPhotos.isEmpty ? 200 : 240
        let mapH = mapBaseH * (innerW / TripShareLayoutMetrics.referenceContentWidth)
        let routeImage = await TripFlightRouteSnapshot.makeImage(
            legs: trip.flights.legs,
            mapSize: CGSize(width: innerW, height: mapH.rounded(.down))
        )
        let card = TripShareCardView(
            trip: trip,
            sessions: sessions,
            tripPhotos: tripPhotos,
            flightRouteImage: routeImage,
            cardWidth: width
        )
        .environmentObject(settingsStore)
        let renderer = ImageRenderer(content: card)
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage
    }
}
