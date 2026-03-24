import ActivityKit
import Foundation

struct TimerActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var startTime: Date
        var casino: String
        var game: String
        var totalBuyIn: Int
        var startingTierPoints: Int
        var rewardsProgramName: String?
    }
    var sessionID: String
}
