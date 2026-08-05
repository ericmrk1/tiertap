import Foundation
import CoreLocation

enum TripLodgingKind: String, Codable, CaseIterable, Hashable {
    case hotel
    case home
    case other

    var label: String {
        switch self {
        case .hotel: return "Hotel"
        case .home: return "Home / stay"
        case .other: return "Other"
        }
    }
}

struct TripLodgingPlace: Identifiable, Codable, Hashable {
    var id: UUID
    var kind: TripLodgingKind
    var name: String
    var subtitle: String
    var latitude: Double?
    var longitude: Double?
    /// Check-in / stay start; if `nil`, callers should treat as the parent trip’s `startDate`.
    var stayStartDate: Date?
    /// Check-out / last night; if `nil`, callers should treat as the parent trip’s `endDate`.
    var stayEndDate: Date?

    init(
        id: UUID = UUID(),
        kind: TripLodgingKind,
        name: String,
        subtitle: String = "",
        latitude: Double? = nil,
        longitude: Double? = nil,
        stayStartDate: Date? = nil,
        stayEndDate: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.subtitle = subtitle
        self.latitude = latitude
        self.longitude = longitude
        self.stayStartDate = stayStartDate
        self.stayEndDate = stayEndDate
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    func effectiveStayStart(trip: Trip) -> Date {
        stayStartDate ?? trip.startDate
    }

    func effectiveStayEnd(trip: Trip) -> Date {
        stayEndDate ?? trip.endDate
    }

    /// Medium-style date range using effective stay bounds for `trip`.
    func stayRangeLabel(trip: Trip) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        let s = effectiveStayStart(trip: trip)
        let e = effectiveStayEnd(trip: trip)
        return "\(df.string(from: s)) – \(df.string(from: e))"
    }
}

enum TripFlightPattern: String, Codable, CaseIterable, Hashable {
    case direct
    case roundTrip

    var label: String {
        switch self {
        case .direct: return "Direct / one-way"
        case .roundTrip: return "Round-trip"
        }
    }
}

struct TripFlightLeg: Identifiable, Codable, Hashable {
    var id: UUID
    var airline: String
    var flightNumber: String
    var seat: String
    var originName: String
    var destinationName: String
    var originLatitude: Double?
    var originLongitude: Double?
    var destinationLatitude: Double?
    var destinationLongitude: Double?
    /// Optional user-entered departure for this leg.
    var departureDate: Date?

    init(
        id: UUID = UUID(),
        airline: String = "",
        flightNumber: String = "",
        seat: String = "",
        originName: String = "",
        destinationName: String = "",
        originLatitude: Double? = nil,
        originLongitude: Double? = nil,
        destinationLatitude: Double? = nil,
        destinationLongitude: Double? = nil,
        departureDate: Date? = nil
    ) {
        self.id = id
        self.airline = airline
        self.flightNumber = flightNumber
        self.seat = seat
        self.originName = originName
        self.destinationName = destinationName
        self.originLatitude = originLatitude
        self.originLongitude = originLongitude
        self.destinationLatitude = destinationLatitude
        self.destinationLongitude = destinationLongitude
        self.departureDate = departureDate
    }

    var originCoordinate: CLLocationCoordinate2D? {
        guard let lat = originLatitude, let lon = originLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var destinationCoordinate: CLLocationCoordinate2D? {
        guard let lat = destinationLatitude, let lon = destinationLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var hasRoute: Bool {
        originCoordinate != nil && destinationCoordinate != nil
    }
}

struct TripFlightBundle: Codable, Hashable {
    var pattern: TripFlightPattern
    var legs: [TripFlightLeg]

    init(pattern: TripFlightPattern = .direct, legs: [TripFlightLeg] = []) {
        self.pattern = pattern
        self.legs = legs
    }
}

struct Trip: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var startDate: Date
    var endDate: Date
    var primaryLocationName: String
    var primarySubtitle: String
    var primaryLatitude: Double?
    var primaryLongitude: Double?
    var sessionIDs: [UUID]
    var lodgings: [TripLodgingPlace]
    var flights: TripFlightBundle
    /// Stored relative file names inside the per-trip photo folder (`tripId/filename`).
    var photoFilenames: [String]
    var notes: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "",
        startDate: Date,
        endDate: Date,
        primaryLocationName: String = "",
        primarySubtitle: String = "",
        primaryLatitude: Double? = nil,
        primaryLongitude: Double? = nil,
        sessionIDs: [UUID] = [],
        lodgings: [TripLodgingPlace] = [],
        flights: TripFlightBundle = TripFlightBundle(),
        photoFilenames: [String] = [],
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.primaryLocationName = primaryLocationName
        self.primarySubtitle = primarySubtitle
        self.primaryLatitude = primaryLatitude
        self.primaryLongitude = primaryLongitude
        self.sessionIDs = sessionIDs
        self.lodgings = lodgings
        self.flights = flights
        self.photoFilenames = photoFilenames
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var displayTitle: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty { return trimmedTitle }
        let loc = primaryLocationName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !loc.isEmpty { return loc }
        return "Trip"
    }
}

enum TripTimelineStatus: Equatable {
    /// Trip end (calendar day) is before today.
    case past
    /// Today falls on or between trip start and end (inclusive calendar days), and the trip is not past.
    case current
    /// First trip day is after today (trip not started).
    case upcoming

    /// Short badge label for trip headers and UI.
    var badgeLabel: String {
        switch self {
        case .past: return "Past trip"
        case .current: return "Current trip"
        case .upcoming: return "Upcoming trip"
        }
    }
}

extension Trip {
    /// Lines derived from `primarySubtitle` (` · ` from the map picker; legacy comma separation).
    var primaryLocationSubtitleLines: [String] {
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

    /// End date before the start of “today” in the current calendar → historical.
    func isHistorical(relativeTo now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let endDay = calendar.startOfDay(for: endDate)
        let todayStart = calendar.startOfDay(for: now)
        return endDay < todayStart
    }

    /// Past vs current vs upcoming relative to **today** and this trip’s **start/end** dates (inclusive calendar days).
    func timelineStatus(relativeTo now: Date = Date(), calendar: Calendar = .current) -> TripTimelineStatus {
        if isHistorical(relativeTo: now, calendar: calendar) { return .past }
        let todayStart = calendar.startOfDay(for: now)
        let tripStartDay = calendar.startOfDay(for: min(startDate, endDate))
        if tripStartDay > todayStart { return .upcoming }
        return .current
    }

    static func timelineSectionKey(for trip: Trip, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: trip.endDate)
    }

    /// Completed sessions whose time span overlaps the trip window, treating trip dates as **inclusive** full calendar days.
    static func eligibleSessionIDs(
        startDate: Date,
        endDate: Date,
        sessions: [Session],
        calendar: Calendar = .current
    ) -> Set<UUID> {
        let tripStartDay = calendar.startOfDay(for: min(startDate, endDate))
        guard let dayAfterLastTripDay = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: max(startDate, endDate))
        ) else {
            return []
        }

        var ids = Set<UUID>()
        for s in sessions where s.isComplete {
            let sessionStart = s.startTime
            let sessionEnd = s.endTime ?? s.startTime
            if sessionStart < dayAfterLastTripDay && sessionEnd >= tripStartDay {
                ids.insert(s.id)
            }
        }
        return ids
    }
}
