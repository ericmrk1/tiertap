import Foundation

/// Curated slot titles for check-in and pickers (table-games-style flow, slots-only list).
struct SlotsList {
    static let pinned = [
        "Penny slots",
        "Video slots",
        "Wheel of Fortune",
        "Megabucks"
    ]
    static let others = [
        "5 Dragons",
        "Bonus wheel / feature games",
        "Cashman / Cash Express",
        "Triple Fortune Dragon",
        "Ultimate Fire Link",
        "Video poker (bar top)",
        "Other slot"
    ]
    static var all: [String] { pinned + others.sorted() }
}
