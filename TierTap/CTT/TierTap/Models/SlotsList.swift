import Foundation

/// Curated slot titles for check-in and pickers (table-games-style flow, slots-only list).
struct SlotsList {
    static let pinned = [
        "Penny slots",
        "Video slots",
        "Wheel of Fortune",
        "Buffalo",
        "Lightning Link",
        "88 Fortunes",
        "Cleopatra",
        "Megabucks"
    ]
    static let others = [
        "5 Dragons",
        "7s / classic reels",
        "Aristocrat (other)",
        "Big Fish / fishing theme",
        "Bonus wheel / feature games",
        "Cashman / Cash Express",
        "Dragon Link",
        "Dancing Drums",
        "Fu Dao Le",
        "Game of Thrones",
        "High-limit slots",
        "Invaders from Planet Moolah",
        "Jin Ji Bao / Asian themes",
        "Keno (video)",
        "Lock It Link",
        "Mega Moolah",
        "Monopoly slots",
        "Quick Hit",
        "Rakin’ Bacon",
        "Smokin’ Hot Stuff",
        "Tarzan",
        "The Walking Dead",
        "Triple Fortune Dragon",
        "Ultimate Fire Link",
        "Video poker (bar top)",
        "Other slot"
    ]
    static var all: [String] { pinned + others.sorted() }
}
