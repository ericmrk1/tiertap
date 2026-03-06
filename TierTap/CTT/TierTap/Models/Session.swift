import Foundation

struct BuyInEvent: Identifiable, Codable, Hashable {
    var id = UUID()
    var amount: Int
    var timestamp: Date
}

struct Session: Identifiable, Codable, Equatable {
    var id = UUID()
    var game: String
    var casino: String
    var startTime: Date
    var endTime: Date?
    var startingTierPoints: Int
    var endingTierPoints: Int?
    var buyInEvents: [BuyInEvent] = []
    var cashOut: Int?
    var avgBetActual: Int?
    var avgBetRated: Int?
    var isLive: Bool = false

    var totalBuyIn: Int { buyInEvents.reduce(0) { $0 + $1.amount } }

    var duration: TimeInterval {
        (endTime ?? Date()).timeIntervalSince(startTime)
    }
    var hoursPlayed: Double { duration / 3600.0 }

    var winLoss: Int? {
        guard let c = cashOut else { return nil }
        return c - totalBuyIn
    }
    var tierPointsEarned: Int? {
        guard let e = endingTierPoints else { return nil }
        return e - startingTierPoints
    }
    var tiersPerHour: Double? {
        guard let e = tierPointsEarned, hoursPlayed > 0 else { return nil }
        return Double(e) / hoursPlayed
    }
    var tiersPerHundredRatedBetHour: Double? {
        guard let r = avgBetRated, r >= 100,
              let e = tierPointsEarned, hoursPlayed > 0 else { return nil }
        return (Double(e) / (Double(r) * hoursPlayed)) * 100.0
    }

    static func durationString(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600, m = (Int(t) % 3600) / 60, s = Int(t) % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
