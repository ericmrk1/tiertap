import Foundation

struct GamesList {
    static let pinned = [
        "Blackjack","Craps","Baccarat",
        "Roulette","Pai Gow (Tiles)","Pai Gow Poker"
    ]
    static let others = [
        "Three Card Poker","Four Card Poker","Ultimate Texas Hold'em",
        "Mississippi Stud","Let It Ride","Caribbean Stud","Casino War",
        "Big Six / Money Wheel","Sic Bo","Dragon Tiger","Spanish 21",
        "Double Attack Blackjack","Super Fun 21","EZ Baccarat",
        "Dragon Bonus Baccarat","Fortune Pai Gow","Crazy 4 Poker",
        "High Card Flush","Casino Hold'em","Heads Up Hold'em",
        "Texas Hold'em Bonus","3-5-7 Poker","Blackjack Switch",
        "Free Bet Blackjack","Lucky Ladies Blackjack","Pontoon",
        "Red Dog","Andar Bahar","Teen Patti","Double Exposure Blackjack",
        "Fan Tan","Criss Cross Poker","Oasis Poker"
    ]
    static var all: [String] { pinned + others.sorted() }
}
