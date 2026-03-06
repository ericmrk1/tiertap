import Foundation

/// Generic strategy and odds summaries for table games. Content is widely available from many gambling
/// strategy guides, books, and casino resources. Used for the in-app Strategy/Odds popup; rules and
/// paytables vary by casino and may change over time.
struct StrategyDatabase {

    struct Entry {
        let summary: String
    }

    private static let entries: [String: Entry] = [
        "Blackjack": Entry(
            summary: """
            • Object: Beat the dealer (not just get close to 21). Don’t bust, then outscore the dealer or have the dealer bust.
            • Basic strategy: Use a basic strategy chart for your table’s rules (decks, S17/H17, DAS, etc.). Many free charts exist online or in strategy guides.
            • Simple rules: Stand on 17+. Hit 11 or less (or double 10/11 vs weak dealer). Double 10 vs 2–9, 11 vs 2–10 when allowed. Split 8s and Aces. Surrender 16 vs 10 when offered.
            • Avoid 6–5 blackjack; insist on 3–2. House edge with good rules can be under 0.5%.
            """
        ),
        "Craps": Entry(
            summary: """
            • Best bets: Pass (or Don’t Pass) plus full Odds. Odds bet has zero house edge.
            • Pass: Wins on come-out 7 or 11, loses on 2, 3, 12. Then point must repeat before a 7. House edge ~1.41% per bet made.
            • Don’t Pass: Wins on 2 or 3, loses on 7 or 11; 12 is push (in most places). Then 7 before point = you win. Slightly lower house edge than Pass.
            • Always take maximum Odds behind Pass (or lay Odds behind Don’t Pass). Place 6 and 8 are next best if you don’t want line bets (~0.46% per roll).
            • Avoid: Big 6/8, proposition bets, Field (unless 3–1 on both 2 and 12).
            """
        ),
        "Baccarat": Entry(
            summary: """
            • Two main bets: Banker and Player. Banker has a small edge; commission (usually 5%) on Banker wins.
            • Banker is the best bet (house edge ~1.06% with 5% commission). Player is ~1.24%. Tie is a high-house-edge bet.
            • No strategy decisions: drawing rules are fixed. Bet Banker for lowest house edge; avoid Tie and most side bets unless you know the paytable.
            • Card counting has limited value for most players.
            """
        ),
        "Roulette": Entry(
            summary: """
            • American double-zero: house edge 5.26%. European single-zero: 2.70%. All bets have the same edge per dollar wagered (except the basket 0-00-1-2-3 in US).
            • No strategy changes the house edge. Outside bets (red/black, even/odd, dozens) lose slower than inside bets in the long run.
            • Avoid the five-number 0-00-1-2-3 in the US (very high house edge).
            """
        ),
        "Pai Gow (Tiles)": Entry(
            summary: """
            • Traditional Chinese domino game. You receive tiles and set two hands (front and back); both must beat the banker’s two hands to win.
            • House way and optimal setting strategies exist; setting correctly reduces house edge. Strategy tables are available from many sources.
            • Banking when offered can improve expected value (tiles favor the banker). Commission and table rules vary.
            """
        ),
        "Pai Gow Poker": Entry(
            summary: """
            • Seven cards; split into a five-card hand and a two-card hand. High hand must beat low hand. You play vs dealer’s two hands; win both to win, lose both to lose, one each = push.
            • Joker is semi-wild (ace or complete straight/flush). A-2-3-4-5 is the second-highest straight (wheel).
            • Use a simple strategy for setting hands; many one-page guides exist. Banking when the button comes to you has better expected value than not banking. House edge with good play is around 2.5% (dealer bank) or lower when you bank.
            """
        ),
        "Three Card Poker": Entry(
            summary: """
            • Ante: then fold or raise (equal to ante). Dealer needs Queen-high or better to qualify. Raise on Q/6/4 or better; otherwise fold (optimal strategy for standard paytables).
            • Pair Plus is a separate bet on your three cards; paytables vary (straight flush, trips, straight, flush, pair). House edge on Pair Plus is typically 2–7% depending on paytable.
            • Combined Ante+Play house edge with optimal strategy is about 3.4% on the ante; raise strategy matters.
            """
        ),
        "Four Card Poker": Entry(
            summary: """
            • You get five cards, dealer gets six (both make best four-card hands). Ante, then fold or raise (1x–3x ante). No dealer qualification.
            • Strategy: raise with three of a kind or better; with two pair, raise only with aces and kings. House edge is around 3–4% with optimal play. Full strategy charts are available from multiple sources.
            """
        ),
        "Ultimate Texas Hold'em": Entry(
            summary: """
            • Two cards to you, five community cards. You make a five-card hand; play in stages (pre-flop 4x, flop 2x, river 1x or check). Dealer needs a pair or better to qualify.
            • Strategy depends on hand strength and board. Pre-flop: 4x with premium hands (e.g. pair of 10s+, AK). Many hands should check and decide on flop or river.
            • House edge with optimal strategy is roughly 2%–3%. Trips side bet typically has high house edge; check paytable before playing.
            """
        ),
        "Mississippi Stud": Entry(
            summary: """
            • Five cards, three betting rounds (after 2, 4, and 5 cards). Each round: fold or make 1x or 3x bet. Payouts on a scale (e.g. pair of 2s to royal flush).
            • Strategy: play 1x or 3x based on hand strength at each stage. House edge with optimal play is around 4%–5%. Strategy tables are available from many strategy guides.
            """
        ),
        "Let It Ride": Entry(
            summary: """
            • Three cards, three equal bets. Two community cards added; you can “pull back” one bet after first card and one after second. Final hand is best five-card poker hand.
            • Strategy: leave bet up (let it ride) with a paying hand (10s or better, or three to a flush/straight with high cards). Pull back otherwise at each stage.
            """
        ),
        "Caribbean Stud": Entry(
            summary: """
            • Five cards each; dealer must have Ace-King or better to qualify. You ante, then see one dealer card and choose to fold or raise (2x ante). No additional draws.
            • Strategy: raise with a pair or better, or Ace-King; otherwise fold (with some exceptions for Ace-King high cards). House edge is around 5% with optimal strategy. Progressive side bet is usually poor value.
            """
        ),
        "Casino War": Entry(
            summary: """
            • Single card each; higher card wins. Tie: you may surrender half or “go to war” (double bet, then each get one more card). Very simple; house edge is about 2.9% with optimal play (surrender on ties).
            """
        ),
        "Big Six / Money Wheel": Entry(
            summary: """
            • Wheel with segments (e.g. 1, 2, 5, 10, 20, 40, joker). You bet on a symbol; if the pointer lands on it you get paid. House edge is very high (often 11%–24% depending on layout).
            • No strategy; purely a novelty bet. Prefer table games with lower house edge if you care about odds.
            """
        ),
        "Sic Bo": Entry(
            summary: """
            • Three dice; you bet on totals, combinations, or single numbers. House edge varies widely by bet: “small” (4–10) and “big” (11–17) are often around 2.8%; single-number and combination bets are much higher.
            • Stick to Small/Big or the best single-number paytables where offered. Avoid multiple single-dice combos with poor payouts.
            """
        ),
        "Dragon Tiger": Entry(
            summary: """
            • One card to “Dragon,” one to “Tiger”; higher card wins. Tie option available (high house edge). Simple even-money bet; house edge is around 3.7% (with tie). No strategy; similar to baccarat in simplicity.
            """
        ),
        "Spanish 21": Entry(
            summary: """
            • Blackjack with all 10s removed from the deck; special rules (e.g. late surrender, double any number, re-split aces, 21 always wins, bonus payouts). Strategy differs from standard blackjack.
            • Use a Spanish 21–specific basic strategy chart. Despite no 10s, good rules can bring house edge to about 0.4%–0.8%.
            """
        ),
        "Double Attack Blackjack": Entry(
            summary: """
            • Blackjack variant: after seeing dealer’s upcard you may double your bet (“double attack”). Dealer typically stands on all 17s. Strategy differs from standard blackjack; use a variant-specific strategy chart.
            """
        ),
        "Super Fun 21": Entry(
            summary: """
            • Blackjack variant with liberal rules (e.g. double any number, late surrender, 1:1 blackjack). Single deck common. House edge can be under 1% with correct basic strategy; use a Super Fun 21–specific strategy chart.
            """
        ),
        "EZ Baccarat": Entry(
            summary: """
            • Baccarat without commission on Banker wins; “Dragon 7” (Banker wins with 7) causes a push instead of win. Side bets (Dragon 7, Panda 8) available. Main Banker/Player strategy same as baccarat: bet Banker for best value; avoid bad side bets unless you know the paytable.
            """
        ),
        "Dragon Bonus Baccarat": Entry(
            summary: """
            • Baccarat with a “Dragon Bonus” side bet (e.g. on margin of victory). Main game same as baccarat; Dragon Bonus house edge depends on paytable. Stick to Banker/Player for lowest edge unless you’ve checked the bonus odds.
            """
        ),
        "Fortune Pai Gow": Entry(
            summary: """
            • Pai Gow Poker variant; Fortune bet is a side bet on your seven cards (e.g. envy bonuses, jackpots). Main game strategy same as Pai Gow Poker. Fortune bet house edge varies by paytable.
            """
        ),
        "Crazy 4 Poker": Entry(
            summary: """
            • Four-card poker; you and dealer get four cards, make best four-card hand. Ante, then fold or raise. No dealer qualification. Generally raise with strong four-card hands; full strategy available from many strategy sources.
            """
        ),
        "High Card Flush": Entry(
            summary: """
            • Flush-based game; you get seven cards, make best flush (or high cards). Ante, then fold or raise. Paytable for flush length and/or high card. Strategy: raise when you have a flush or strong draw; full strategy charts are available from multiple sources.
            """
        ),
        "Casino Hold'em": Entry(
            summary: """
            • Similar to Texas Hold’em vs dealer. Two cards to you, five community. Bet flop and river; dealer needs pair of 4s or better to qualify. House edge typically 2%–3% with correct play. Use a variant-specific strategy chart.
            """
        ),
        "Heads Up Hold'em": Entry(
            summary: """
            • Heads-up Texas Hold’em vs dealer. Strategy and paytables vary by venue. Generally play strong hands and fold weak ones; full strategy depends on the specific variant and paytable.
            """
        ),
        "Texas Hold'em Bonus": Entry(
            summary: """
            • Texas Hold’em vs dealer with bonus payouts for your hand. Strategy similar to other hold’em table games; use a strategy chart for the specific paytable.
            """
        ),
        "3-5-7 Poker": Entry(
            summary: """
            • Multiple hands (3, 5, 7 cards) with different paytables. You choose which hands to play and bet. Strategy is complex; consult strategy guides for optimal play and house edge for your paytable.
            """
        ),
        "Blackjack Switch": Entry(
            summary: """
            • Two hands; you may switch the second card between hands. Dealer 22 pushes vs player 21. Strategy is different from normal blackjack (e.g. switch to make strong hand and weak hand, then play each). House edge can be under 0.6% with optimal strategy; use a Switch-specific chart.
            """
        ),
        "Free Bet Blackjack": Entry(
            summary: """
            • Blackjack with “free” doubles and splits (you don’t put up extra money, but push on 22). Strategy differs from standard blackjack; house edge is typically around 0.5%–1% with correct play. Use a Free Bet–specific basic strategy.
            """
        ),
        "Lucky Ladies Blackjack": Entry(
            summary: """
            • Standard blackjack with a “Lucky Ladies” side bet (e.g. on your two cards totaling 20, with bonuses for suited/paired 20). Main game: use normal basic strategy. Side bet has high house edge; optional. Check paytable before playing the side bet.
            """
        ),
        "Pontoon": Entry(
            summary: """
            • British-style blackjack (twist, stick, buy, etc.). Dealer cards often both down; no hole card. Strategy differs from US blackjack; use a Pontoon-specific strategy. House edge varies with rules.
            """
        )
    ]

    /// Returns strategy summary for a game name (as stored in sessions). Case-sensitive match first; then case-insensitive.
    static func entry(forGame gameName: String) -> Entry? {
        if let e = entries[gameName] { return e }
        let key = entries.keys.first { $0.lowercased() == gameName.lowercased() }
        return key.flatMap { entries[$0] }
    }

    /// Whether we have strategy content for this game.
    static func hasStrategy(forGame gameName: String) -> Bool {
        entry(forGame: gameName) != nil
    }

    // MARK: - House edge (for “above/below statistical house edge” at session end)

    /// Typical house edge (percent) and rounds per hour for estimating expected loss. Values are approximate and vary by rules/casino.
    private static let houseEdgePercent: [String: Double] = [
        "Blackjack": 0.5, "Craps": 1.4, "Baccarat": 1.06, "Roulette": 5.26,
        "Pai Gow (Tiles)": 3.0, "Pai Gow Poker": 2.7, "Three Card Poker": 3.4, "Four Card Poker": 3.5,
        "Ultimate Texas Hold'em": 2.2, "Mississippi Stud": 4.5, "Let It Ride": 3.5, "Caribbean Stud": 5.2,
        "Casino War": 2.9, "Big Six / Money Wheel": 15.0, "Sic Bo": 2.8, "Dragon Tiger": 3.7,
        "Spanish 21": 0.8, "Double Attack Blackjack": 0.6, "Super Fun 21": 0.8, "EZ Baccarat": 1.06,
        "Dragon Bonus Baccarat": 1.06, "Fortune Pai Gow": 2.7, "Crazy 4 Poker": 3.5, "High Card Flush": 3.5,
        "Casino Hold'em": 2.3, "Heads Up Hold'em": 2.5, "Texas Hold'em Bonus": 2.5, "3-5-7 Poker": 4.0,
        "Blackjack Switch": 0.6, "Free Bet Blackjack": 0.7, "Lucky Ladies Blackjack": 0.5, "Pontoon": 0.4
    ]
    private static let roundsPerHour: [String: Double] = [
        "Blackjack": 70, "Craps": 30, "Baccarat": 70, "Roulette": 30,
        "Pai Gow (Tiles)": 25, "Pai Gow Poker": 25, "Three Card Poker": 50, "Four Card Poker": 40,
        "Ultimate Texas Hold'em": 40, "Mississippi Stud": 35, "Let It Ride": 40, "Caribbean Stud": 45,
        "Casino War": 60, "Big Six / Money Wheel": 20, "Sic Bo": 40, "Dragon Tiger": 70,
        "Spanish 21": 70, "Double Attack Blackjack": 70, "Super Fun 21": 70, "EZ Baccarat": 70,
        "Dragon Bonus Baccarat": 70, "Fortune Pai Gow": 25, "Crazy 4 Poker": 45, "High Card Flush": 40,
        "Casino Hold'em": 45, "Heads Up Hold'em": 50, "Texas Hold'em Bonus": 45, "3-5-7 Poker": 35,
        "Blackjack Switch": 65, "Free Bet Blackjack": 70, "Lucky Ladies Blackjack": 70, "Pontoon": 70
    ]
    private static let defaultRoundsPerHour: Double = 50

    /// Expected loss (positive = amount you’d expect to lose) and amount above/below that expectation.
    /// - Parameters:
    ///   - gameName: Session game name.
    ///   - winLoss: Actual $ result (positive = win, negative = loss).
    ///   - avgBet: Average bet size in $ (use avgBetActual or avgBetRated).
    ///   - hours: Hours played.
    /// - Returns: (expectedLossDollars, aboveEdgeDollars) or nil if game unknown or inputs invalid. aboveEdge &gt; 0 means you did better than house edge would predict.
    static func expectedLossAndAboveEdge(gameName: String, winLoss: Int, avgBet: Int, hours: Double) -> (expectedLoss: Double, aboveEdge: Double)? {
        guard hours > 0, avgBet > 0 else { return nil }
        let edge = houseEdgePercent[gameName]
            ?? houseEdgePercent.keys.first(where: { $0.lowercased() == gameName.lowercased() }).flatMap { houseEdgePercent[$0] }
        guard let houseEdgePct = edge else { return nil }
        let rounds = roundsPerHour[gameName]
            ?? roundsPerHour.keys.first(where: { $0.lowercased() == gameName.lowercased() }).flatMap { roundsPerHour[$0] }
            ?? defaultRoundsPerHour
        let totalWagered = Double(avgBet) * rounds * hours
        let expectedLoss = (houseEdgePct / 100.0) * totalWagered
        let aboveEdge = Double(winLoss) + expectedLoss
        return (expectedLoss, aboveEdge)
    }

    // MARK: - Wikipedia links (when no strategy entry exists)

    /// Wikipedia article slugs (path component after /wiki/) for known games. Used when we have no strategy entry.
    private static let wikipediaSlugs: [String: String] = [
        "Blackjack": "Blackjack",
        "Craps": "Craps",
        "Baccarat": "Baccarat",
        "Roulette": "Roulette",
        "Pai Gow (Tiles)": "Pai_gow",
        "Pai Gow Poker": "Pai_gow_poker",
        "Three Card Poker": "Three_Card_Poker",
        "Four Card Poker": "Four_Card_Poker",
        "Ultimate Texas Hold'em": "Ultimate_Texas_Hold%27em",
        "Mississippi Stud": "Mississippi_Stud",
        "Let It Ride": "Let_It_Ride",
        "Caribbean Stud": "Caribbean_stud_poker",
        "Casino War": "Casino_war",
        "Big Six / Money Wheel": "Big_Six_Wheel",
        "Sic Bo": "Sic_bo",
        "Dragon Tiger": "Dragon_Tiger_(game)",
        "Spanish 21": "Spanish_21",
        "Double Attack Blackjack": "Blackjack",
        "Super Fun 21": "Blackjack",
        "EZ Baccarat": "Baccarat",
        "Dragon Bonus Baccarat": "Baccarat",
        "Fortune Pai Gow": "Pai_gow_poker",
        "Crazy 4 Poker": "Casino_poker",
        "High Card Flush": "High_card_flush",
        "Casino Hold'em": "Casino_hold%27em",
        "Heads Up Hold'em": "Texas_hold_%27em",
        "Texas Hold'em Bonus": "Texas_hold_%27em",
        "3-5-7 Poker": "3-5-7_Poker",
        "Blackjack Switch": "Blackjack_Switch",
        "Free Bet Blackjack": "Blackjack",
        "Lucky Ladies Blackjack": "Blackjack",
        "Pontoon": "Pontoon_(card_game)"
    ]

    /// Returns a Wikipedia URL for the game when no strategy exists. Uses known slugs where available; otherwise builds from the game name.
    static func wikipediaURL(forGame gameName: String) -> URL? {
        let trimmed = gameName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let slug: String
        if let known = wikipediaSlugs[trimmed] ?? wikipediaSlugs.keys.first(where: { $0.lowercased() == trimmed.lowercased() }).flatMap({ wikipediaSlugs[$0] }) {
            slug = known
        } else {
            let encoded = trimmed
                .replacingOccurrences(of: " ", with: "_")
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? trimmed
            slug = encoded
        }
        return URL(string: "https://en.wikipedia.org/wiki/\(slug)")
    }
}
