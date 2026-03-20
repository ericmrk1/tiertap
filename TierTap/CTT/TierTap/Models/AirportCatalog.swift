import CoreLocation
import Foundation

/// Airport row for flight origin/destination pickers. **Selecting from the catalog stores** ``AirportPicklistEntry/storageCode`` on the leg (IATA when present, otherwise ICAO / primary id from OurAirports).
struct AirportPicklistEntry: Identifiable, Hashable {
    /// Stable row id from OurAirports (not necessarily IATA).
    let id: String
    /// Three-letter IATA when available; otherwise empty.
    let iata: String
    /// ICAO or best-effort location code from OurAirports (`gps_code` / `ident`).
    let icao: String
    let name: String
    let city: String
    /// ISO 3166-1 alpha-2 (OurAirports `iso_country`).
    let country: String
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Value persisted on `TripFlightLeg` origin/destination name fields.
    var storageCode: String {
        let t = iata.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? icao : t
    }

    var picklistTitle: String { "\(storageCode) — \(name)" }
    var picklistSubtitle: String {
        let i = iata.isEmpty ? "—" : iata
        let cc = country.isEmpty ? "—" : country
        return "\(city) · \(cc) · IATA \(i) · ICAO \(icao)"
    }
}

enum AirportCatalog {
    /// Matches index folding / `matching(_:)` normalization so precomputed strings stay in sync.
    private static let searchLocale = Locale(identifier: "en_US_POSIX")

    /// Serializes decode + index creation (never call `sync` on this queue from work already running on it).
    private static let buildQueue = DispatchQueue(label: "com.tiertap.airportcatalog.build", qos: .utility)
    private static let stateLock = NSLock()
    private static var cachedIndex: SearchIndex?

    /// Parsed from bundled `Airports.json`. Cheap after the first index build.
    static var all: [AirportPicklistEntry] {
        index().entries
    }

    /// Kick off decode + index build in the background at launch.
    static func preloadAtLaunch() {
        buildQueue.async {
            stateLock.lock()
            let missing = cachedIndex == nil
            stateLock.unlock()
            guard missing else { return }
            let decoded = decodeBundledAirports()
            let idx = SearchIndex(entries: decoded, locale: searchLocale)
            stateLock.lock()
            if cachedIndex == nil { cachedIndex = idx }
            stateLock.unlock()
        }
    }

    /// Type-ahead: city, name, IATA, or ICAO (diacritic-insensitive substring). Sorted like before; **thread-safe**; heavy work uses the precomputed index (safe off the main thread).
    static func matching(_ query: String, limit: Int = 12) -> [AirportPicklistEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let qFold = q.folding(options: .diacriticInsensitive, locale: searchLocale)
        let ql = qFold.lowercased()
        let qu = q.uppercased()
        return index().matching(ql: ql, qu: qu, limit: limit)
    }

    private static func index() -> SearchIndex {
        stateLock.lock()
        if let idx = cachedIndex {
            stateLock.unlock()
            return idx
        }
        stateLock.unlock()
        return buildQueue.sync {
            stateLock.lock()
            if let idx = cachedIndex {
                stateLock.unlock()
                return idx
            }
            stateLock.unlock()
            let decoded = decodeBundledAirports()
            let made = SearchIndex(entries: decoded, locale: searchLocale)
            stateLock.lock()
            if cachedIndex == nil { cachedIndex = made }
            let out = cachedIndex!
            stateLock.unlock()
            return out
        }
    }

    /// Lower sorts earlier in picklists: US first, then CAN/UK/AUS/NZ/IRL, Caribbean, then other English-heavy markets, then the rest.
    fileprivate static func englishSpeakingCountrySortTier(_ iso: String) -> Int {
        let c = iso.uppercased()
        switch c {
        case "US": return 0
        case "CA", "GB", "AU", "NZ", "IE": return 1
        case "JM", "BZ", "BS", "BB", "TT", "AG", "KN", "DM", "LC", "VC", "GD", "GY":
            return 2
        case "SG", "ZA", "IN", "PH", "PK", "NG", "KE", "GH", "UG", "RW", "ZW", "LR", "MW", "SZ", "BW", "NA":
            return 3
        case "FJ", "WS", "TO", "VU", "SB", "KI", "MH", "FM", "PW", "NR", "CK":
            return 3
        default:
            return 10
        }
    }

    /// If a map pin is near a catalog airport or the map title clearly matches, return ``AirportPicklistEntry/storageCode`` for storage.
    static func iataForMapSelection(coordinate: CLLocationCoordinate2D, mapName: String?) -> String? {
        let entries = index().entries
        let loc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let radiusM: CLLocationDistance = 9000
        let nearby = entries.filter { loc.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) <= radiusM }
        if nearby.count == 1, let only = nearby.first { return only.storageCode }
        if let closest = entries.min(by: {
            loc.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
                < loc.distance(from: CLLocation(latitude: $1.latitude, longitude: $1.longitude))
        }) {
            let d = loc.distance(from: CLLocation(latitude: closest.latitude, longitude: closest.longitude))
            if d <= radiusM { return closest.storageCode }
        }
        guard let mn = mapName?.trimmingCharacters(in: .whitespacesAndNewlines), !mn.isEmpty else { return nil }
        let lower = mn.lowercased()
        for a in entries where !a.iata.isEmpty {
            if lower.contains(a.iata.lowercased()) { return a.storageCode }
        }
        let nameHits = entries.filter { mn.localizedCaseInsensitiveContains($0.name) }
        if let pick = nameHits.min(by: { a, b in
            let ta = englishSpeakingCountrySortTier(a.country)
            let tb = englishSpeakingCountrySortTier(b.country)
            if ta != tb { return ta < tb }
            if a.name.count != b.name.count { return a.name.count < b.name.count }
            return a.iata < b.iata
        }) {
            return pick.storageCode
        }
        return nil
    }

    private struct AirportRecord: Decodable {
        let id: String
        let iata: String
        let icao: String
        let name: String
        let city: String
        var country: String?
        let latitude: Double
        let longitude: Double
    }

    private static func decodeBundledAirports() -> [AirportPicklistEntry] {
        guard let url = Bundle.main.url(forResource: "Airports", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let recs = try? JSONDecoder().decode([AirportRecord].self, from: data)
        else {
            assertionFailure("Airports.json missing from app bundle or invalid")
            return []
        }
        return recs.map {
            AirportPicklistEntry(
                id: $0.id,
                iata: $0.iata,
                icao: $0.icao,
                name: $0.name,
                city: $0.city,
                country: ($0.country ?? "").uppercased(),
                latitude: $0.latitude,
                longitude: $0.longitude
            )
        }
    }

    /// Pre-folded strings + one-pass top-`limit` matching without sorting the full hit list.
    private final class SearchIndex {
        let entries: [AirportPicklistEntry]
        private let cityFold: [String]
        private let nameFold: [String]
        private let iataU: [String]
        private let iataL: [String]
        private let icaoU: [String]
        private let tier: [Int]

        init(entries: [AirportPicklistEntry], locale: Locale) {
            self.entries = entries
            let n = entries.count
            var cityFold = [String]()
            var nameFold = [String]()
            var iataU = [String]()
            var iataL = [String]()
            var icaoU = [String]()
            var tier = [Int]()
            cityFold.reserveCapacity(n)
            nameFold.reserveCapacity(n)
            iataU.reserveCapacity(n)
            iataL.reserveCapacity(n)
            icaoU.reserveCapacity(n)
            tier.reserveCapacity(n)
            for e in entries {
                cityFold.append(e.city.folding(options: .diacriticInsensitive, locale: locale).lowercased())
                nameFold.append(e.name.folding(options: .diacriticInsensitive, locale: locale).lowercased())
                let iu = e.iata.uppercased()
                iataU.append(iu)
                iataL.append(e.iata.lowercased())
                icaoU.append(e.icao.uppercased())
                tier.append(AirportCatalog.englishSpeakingCountrySortTier(e.country))
            }
            self.cityFold = cityFold
            self.nameFold = nameFold
            self.iataU = iataU
            self.iataL = iataL
            self.icaoU = icaoU
            self.tier = tier
        }

        private typealias SortKey = (Int, Int, Int, String, String)

        func matching(ql: String, qu: String, limit: Int) -> [AirportPicklistEntry] {
            let n = entries.count
            let lim = max(1, min(limit, 64))
            var buf: [(Int, SortKey)] = []
            buf.reserveCapacity(lim)

            for i in 0..<n {
                if !rowMatches(i: i, ql: ql, qu: qu) { continue }
                let k = sortKey(at: i, ql: ql, qu: qu)
                buf.append((i, k))
                if buf.count > lim, let worst = buf.enumerated().max(by: { $0.element.1 < $1.element.1 })?.offset {
                    buf.remove(at: worst)
                }
            }
            buf.sort { $0.1 < $1.1 }
            return buf.map { entries[$0.0] }
        }

        private func rowMatches(i: Int, ql: String, qu: String) -> Bool {
            if cityFold[i].range(of: ql, options: .literal) != nil { return true }
            if nameFold[i].range(of: ql, options: .literal) != nil { return true }
            if !iataU[i].isEmpty, iataU[i].contains(qu) { return true }
            if icaoU[i].contains(qu) { return true }
            return false
        }

        private func sortKey(at i: Int, ql: String, qu: String) -> SortKey {
            let te = tier[i]
            let cf = cityFold[i]
            let nf = nameFold[i]
            let iu = iataU[i]
            let icu = icaoU[i]
            let il = iataL[i]

            let relevance: Int
            if !iu.isEmpty, iu == qu {
                relevance = 0
            } else if !il.isEmpty, il.hasPrefix(ql) {
                relevance = 1
            } else if icu == qu || (qu.count >= 3 && icu.hasSuffix(qu)) {
                relevance = 2
            } else if icu.contains(qu) {
                relevance = 3
            } else if cf == ql {
                relevance = 4
            } else if cf.hasPrefix(ql) {
                relevance = 5
            } else if nf.hasPrefix(ql) {
                relevance = 6
            } else {
                relevance = 7
            }

            let cityRank: Int
            if cf == ql {
                cityRank = 0
            } else if cf.hasPrefix(ql) {
                cityRank = 1
            } else {
                cityRank = 2
            }

            let codeTie = iu.isEmpty ? icaoU[i] : iu
            return (te, relevance, cityRank, cf, codeTie)
        }
    }
}
