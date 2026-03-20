import Foundation

/// Row in the flight-leg airline picker (IATA = 2-letter ticketing code where applicable, ICAO = 3-letter airline designator).
struct AirlinePicklistEntry: Identifiable, Hashable {
    let id: String
    let name: String
    let iata: String
    let icao: String

    init(name: String, iata: String, icao: String) {
        self.name = name
        self.iata = iata
        self.icao = icao
        self.id = "\(iata)|\(icao)|\(name)"
    }

    /// Written to `TripFlightLeg.airline` when the user selects from the list.
    var storedDisplayValue: String {
        "\(name) (\(iata) · \(icao))"
    }
}

enum AirlineCatalog {
    static let all: [AirlinePicklistEntry] = {
        raw.map { AirlinePicklistEntry(name: $0.0, iata: $0.1, icao: $0.2) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }()

    /// Type-ahead / search: **name**, **IATA**, or **ICAO** (case-insensitive, substring).
    static func matching(_ query: String, limit: Int = 12) -> [AirlinePicklistEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return Array(
            all.filter {
                $0.name.localizedCaseInsensitiveContains(q)
                    || $0.iata.localizedCaseInsensitiveContains(q)
                    || $0.icao.localizedCaseInsensitiveContains(q)
            }
            .prefix(limit)
        )
    }

    /// (Display name, IATA, ICAO) — curated set of major and regional carriers.
    private static let raw: [(String, String, String)] = [
        ("Aegean Airlines", "A3", "AEE"),
        ("Aer Lingus", "EI", "EIN"),
        ("Aeroméxico", "AM", "AMX"),
        ("Air Canada", "AC", "ACA"),
        ("Air China", "CA", "CCA"),
        ("Air France", "AF", "AFR"),
        ("Air India", "AI", "AIC"),
        ("Air New Zealand", "NZ", "ANZ"),
        ("Air Tahiti Nui", "TN", "THT"),
        ("Alaska Airlines", "AS", "ASA"),
        ("Alitalia", "AZ", "AZA"),
        ("All Nippon Airways", "NH", "ANA"),
        ("American Airlines", "AA", "AAL"),
        ("Austrian Airlines", "OS", "AUA"),
        ("Avianca", "AV", "AVA"),
        ("British Airways", "BA", "BAW"),
        ("Brussels Airlines", "SN", "BEL"),
        ("Cathay Pacific", "CX", "CPA"),
        ("China Airlines", "CI", "CAL"),
        ("China Eastern Airlines", "MU", "CES"),
        ("China Southern Airlines", "CZ", "CSN"),
        ("Copa Airlines", "CM", "CMP"),
        ("Delta Air Lines", "DL", "DAL"),
        ("Egyptair", "MS", "MSR"),
        ("El Al", "LY", "ELY"),
        ("Emirates", "EK", "UAE"),
        ("Ethiopian Airlines", "ET", "ETH"),
        ("Etihad Airways", "EY", "ETD"),
        ("EVA Air", "BR", "EVA"),
        ("Finnair", "AY", "FIN"),
        ("Frontier Airlines", "F9", "FFT"),
        ("Gol", "G3", "GLO"),
        ("Hainan Airlines", "HU", "CHH"),
        ("Hawaiian Airlines", "HA", "HAL"),
        ("Iberia", "IB", "IBE"),
        ("Icelandair", "FI", "ICE"),
        ("Japan Airlines", "JL", "JAL"),
        ("JetBlue Airways", "B6", "JBU"),
        ("Kenya Airways", "KQ", "KQA"),
        ("KLM", "KL", "KLM"),
        ("Korean Air", "KE", "KAL"),
        ("LATAM Airlines", "LA", "LAN"),
        ("Lufthansa", "LH", "DLH"),
        ("Malaysia Airlines", "MH", "MAS"),
        ("Middle East Airlines", "ME", "MEA"),
        ("Norwegian", "DY", "NOZ"),
        ("Pakistan International Airlines", "PK", "PIA"),
        ("Philippine Airlines", "PR", "PAL"),
        ("Qantas", "QF", "QFA"),
        ("Qatar Airways", "QR", "QTR"),
        ("Royal Air Maroc", "AT", "RAM"),
        ("Royal Jordanian", "RJ", "RJA"),
        ("Ryanair", "FR", "RYR"),
        ("SAS Scandinavian Airlines", "SK", "SAS"),
        ("Saudia", "SV", "SVA"),
        ("Singapore Airlines", "SQ", "SIA"),
        ("South African Airways", "SA", "SAA"),
        ("Southwest Airlines", "WN", "SWA"),
        ("Spirit Airlines", "NK", "NKS"),
        ("SWISS", "LX", "SWR"),
        ("TAP Air Portugal", "TP", "TAP"),
        ("Thai Airways International", "TG", "THA"),
        ("Turkish Airlines", "TK", "THY"),
        ("United Airlines", "UA", "UAL"),
        ("Virgin Atlantic", "VS", "VIR"),
        ("Vietnam Airlines", "VN", "HVN"),
        ("Volaris", "Y4", "VOI"),
        ("Vueling", "VY", "VLG"),
        ("WestJet", "WS", "WJA"),
        ("ZIPAIR", "ZG", "TZP"),
    ]
}
