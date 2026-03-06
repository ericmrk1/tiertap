import Foundation

struct SessionShareFormatter {
    // MARK: - Public API

    static func combinedMessage(for sessions: [Session]) -> String {
        sessions
            .sorted { $0.startTime < $1.startTime }
            .map { session in
                let stats = summary(for: session)
                let sentiment = sentiment(for: session)
                return "\(stats)\n\(sentiment)"
            }
            .joined(separator: "\n\n")
    }

    static func sentiment(for session: Session) -> String {
        isPositive(session) ? SessionSharePhrases.randomPositivePhrase() : SessionSharePhrases.randomNegativePhrase()
    }

    // MARK: - Private helpers

    private static func summary(for session: Session) -> String {
        let dateString = dateFormatter.string(from: session.startTime)
        let durationString = humanReadableDuration(session.duration)

        var parts: [String] = []
        parts.append("On \(dateString) at \(session.casino), you played \(session.game) for \(durationString).")
        parts.append("You bought in for $\(session.totalBuyIn).")

        if let cashOut = session.cashOut, let winLoss = session.winLoss {
            if winLoss > 0 {
                parts.append("You cashed out with $\(cashOut), finishing with a profit of $\(winLoss).")
            } else if winLoss < 0 {
                parts.append("You cashed out with $\(cashOut), finishing with a loss of $\(abs(winLoss)).")
            } else {
                parts.append("You cashed out with $\(cashOut), finishing even on the session.")
            }
        } else if let cashOut = session.cashOut {
            parts.append("You cashed out with $\(cashOut).")
        }

        if let points = session.tierPointsEarned {
            if points > 0 {
                parts.append("You earned \(points) tier points along the way.")
            } else if points < 0 {
                parts.append("You finished with \(abs(points)) fewer tier points than you started with.")
            } else {
                parts.append("You finished with the same number of tier points you started with.")
            }
        }

        return parts.joined(separator: " ")
    }

    private static func isPositive(_ session: Session) -> Bool {
        if let wl = session.winLoss {
            if wl > 0 { return true }
            if wl < 0 { return false }
        }
        if let points = session.tierPointsEarned {
            if points > 0 { return true }
            if points < 0 { return false }
        }
        return true
    }

    private static func humanReadableDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60

        switch (hours, minutes) {
        case (0, 0):
            return "less than a minute"
        case (0, _):
            return "\(minutes) minute\(minutes == 1 ? "" : "s")"
        case (_, 0):
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        default:
            return "\(hours)h \(minutes)m"
        }
    }

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()
}

struct SessionSharePhrases {
    // Using opener/closer combinations to create far more than 10,000
    // distinct phrases without bloating the source with literal strings.

    // MARK: - Positive

    private static let positiveOpeners: [String] = [
        "Nice work managing the swings.",
        "That was a rock-solid grind.",
        "Great session from start to finish.",
        "You stayed composed and it showed.",
        "Smart, disciplined play all night.",
        "You picked your spots really well.",
        "You made the most of that run.",
        "Strong table presence the whole way.",
        "You trusted your reads and it paid off.",
        "You navigated the lineup beautifully.",
        "You stayed patient and let the game come to you.",
        "You protected your wins without getting greedy.",
        "Your decisions were sharp all session.",
        "You found value in all the right places.",
        "You adjusted to the table dynamics quickly.",
        "You played your A-game when it mattered.",
        "You controlled the pace of the session.",
        "You chose your battles with intention.",
        "You stayed focused through the entire session.",
        "You balanced risk and reward nicely.",
        "You picked a great spot to wrap things up.",
        "You let the math and discipline lead the way.",
        "You stayed inside your bankroll and your edge.",
        "You let the good spots come to you.",
        "You made consistently thoughtful decisions.",
        "You trusted your process and it delivered.",
        "You kept emotions in check the whole way.",
        "You leaned into your strengths at the right times.",
        "You stayed locked in when it mattered most.",
        "You played a very mature session.",
        "You never chased – you executed.",
        "You managed volatility like a pro.",
        "You folded well and pressed when it counted.",
        "You sat in a tough lineup and held your own.",
        "You carried yourself like a seasoned regular.",
        "You turned a small edge into a solid result.",
        "You kept your foot on the gas in good spots.",
        "You respected the variance and still won.",
        "You read the room and adjusted perfectly.",
        "You stayed curious and kept learning mid-session.",
        "You focused on quality decisions, not just outcomes.",
        "You stayed present, one hand at a time.",
        "You handled pressure spots with confidence.",
        "You found thin but profitable spots to push.",
        "You turned a slow start into a strong finish.",
        "You cashed in on your patience.",
        "You made disciplined laydowns that saved money.",
        "You made value bets that squeezed every dollar.",
        "You maximized good situations without overextending.",
        "You kept your edge even late in the session.",
        "You stayed humble while still pushing for value.",
        "You locked up a win and left on your terms.",
        "You played like someone who knows their game.",
        "You stayed clear-headed even as the stakes rose.",
        "You picked a great time to book the win.",
        "You trusted the long run and it showed.",
        "You made high-quality decisions under pressure.",
        "You stayed intentional with every chip that went in.",
        "You never let one hand define the session.",
        "You took spots that fit your skill and style.",
        "You navigated short stacks and deep stacks well.",
        "You earned every dollar on that table.",
        "You rode the heater with control and awareness.",
        "You didn’t force action – you created it.",
        "You stayed composed through big pots.",
        "You played a confident, measured game.",
        "You made the most of good table conditions.",
        "You protected your mental game all session.",
        "You stayed disciplined with game selection.",
        "You avoided marginal spots when you didn’t need them.",
        "You capitalized when the table got loose.",
        "You pushed your edge without overplaying it.",
        "You kept your strategy simple and effective.",
        "You stayed aligned with your pre-session plan.",
        "You made smart adjustments as stacks shifted.",
        "You used position to your advantage all night.",
        "You extracted thin value without getting reckless.",
        "You kept your ranges tight and purposeful.",
        "You played a very controlled, professional session.",
        "You maintained composure even after tough hands.",
        "You closed the session with intention, not emotion.",
        "You trusted your bankroll management the whole way.",
        "You stayed selective and it paid off.",
        "You avoided hero calls that didn’t need to happen.",
        "You didn’t let a heater turn into a punt.",
        "You showed a lot of patience and restraint.",
        "You respected the variance but still leaned into good spots.",
        "You played within yourself and your comfort zone.",
        "You handled table talk and distractions really well.",
        "You used your reads to guide tough decisions.",
        "You made disciplined folds that saved real money.",
        "You took high-quality shots, not hopeful ones.",
        "You walked away with both profit and confidence.",
        "You grew as a player with this session.",
        "You treated this like a professional would.",
        "You showed real growth in your decision-making.",
        "You balanced aggression with smart defense.",
        "You ran well and still played tight, solid poker.",
        "You sharpened your instincts and trusted them.",
        "You kept your ego out of the way of good choices.",
        "You walked away with a result you earned.",
        "You left the table with momentum and clarity.",
        "You used discipline as your biggest edge.",
        "You stayed process-focused and the results followed.",
        "You showed up like the player you’re becoming."
    ]

    private static let positiveClosers: [String] = [
        "Keep leaning into that version of your game.",
        "Bank this confidence and bring it to the next session.",
        "This is exactly how winning players build long-term graphs.",
        "Keep stacking sessions like this and the long run takes care of itself.",
        "Wins like this are built on discipline, not luck.",
        "Carry this decision quality into your next outing.",
        "Bookmark this feeling – it’s what solid execution feels like.",
        "This is the kind of session your future self will thank you for.",
        "Let this be a reminder that your edge is real.",
        "Wins like this are the payoff for all the quiet work.",
        "Keep protecting your mental game the way you did here.",
        "Use this as proof that your strategy holds up live.",
        "Let this result reinforce your commitment to good habits.",
        "Stack enough sessions like this and the numbers will show it.",
        "Keep choosing quality decisions over short-term excitement.",
        "This is exactly how you stay ahead of the curve.",
        "Let this win fuel your patience, not your ego.",
        "This session belongs on the highlight reel.",
        "Treat this not as a rush, but as validation.",
        "Keep trusting your reads and your preparation.",
        "This kind of discipline makes downswings much easier to handle.",
        "Your future volume will love sessions just like this.",
        "Wins like this are how bankrolls quietly grow.",
        "Keep doing the boring, profitable things well.",
        "This is the blueprint worth repeating.",
        "You’re clearly building more than just results here.",
        "Let this be one of many professional-feeling sessions.",
        "Keep showing up with this level of focus.",
        "Your instincts and strategy lined up nicely tonight.",
        "Treat this session as confirmation, not an exception.",
        "Bank the lesson and the profit at the same time.",
        "Use this to anchor your confidence on tough days.",
        "You’re building a very real sample of quality play.",
        "Let this be a quiet, steady step forward.",
        "Keep chasing execution, not just heat.",
        "Sessions like this are what long-term graphs are made of.",
        "Keep stacking edges, big and small.",
        "This is what sustainable success actually looks like.",
        "Your process is clearly moving in the right direction.",
        "Keep giving yourself time to make thoughtful decisions.",
        "Sessions like this make future variance easier to stomach.",
        "You’re proving to yourself that you belong in these games.",
        "Carry this calm, technical mindset forward.",
        "You’re clearly growing into a tougher opponent.",
        "Keep your standards here, even when the cards cool off.",
        "Let this be a baseline, not a high point.",
        "You’re starting to turn theory into real-world profit.",
        "This is exactly the kind of session to build on.",
        "Your future sessions will benefit from this confidence.",
        "Keep bringing this level of patience and awareness.",
        "You’re earning both money and experience at the same time.",
        "Let this win raise your expectations for your own discipline.",
        "You’ve shown that your best game travels to live tables.",
        "Keep anchoring your game around decisions like these.",
        "You’re building a track record you can trust.",
        "Treat this as a proof-of-concept for your style.",
        "Your edge showed up quietly and consistently here.",
        "Keep choosing the long-term line over the flashy one.",
        "You’re clearly capable of playing at this standard often.",
        "Let this shape how you talk to yourself as a player.",
        "You’re seeing what happens when patience and skill meet.",
        "Keep showing up like this and the numbers will follow.",
        "You’re starting to feel like the regular, not the tourist.",
        "Let this session redefine what a ‘good’ night looks like.",
        "You proved you can protect a lead with discipline.",
        "Keep approaching sessions like a long-term project.",
        "You’re developing a game that wears well over time.",
        "Let this reinforce your belief in structured play.",
        "You’re playing with intention, not just hope.",
        "Keep building this version of your bankroll curve.",
        "You’re learning to win without having to gamble.",
        "Let this nudge you to trust your preparation even more.",
        "You’re proving that solid fundamentals still win.",
        "Keep steering toward these boring, profitable decisions.",
        "You’re turning good theory into live execution.",
        "Let this be evidence that your process is working.",
        "You’re stacking skills, not just results.",
        "Keep giving yourself credit for sessions like this.",
        "You’re building a strong mental game around nights like these.",
        "Let this win quietly raise your baseline expectations.",
        "You’re steadily becoming the tough seat at the table.",
        "Keep focusing on the next good session, not the next big score.",
        "You’re treating the game with respect and it shows.",
        "Let this session be one data point in a long, winning line.",
        "You’re clearly leveling up your live execution.",
        "Keep finding ways to reproduce this level of focus.",
        "You’re building something durable with sessions like this.",
        "Let this be the standard you hold yourself to.",
        "You’re slowly rewriting your story as a player.",
        "Keep making the kinds of choices future-you will be proud of.",
        "You’re learning how to win like a professional.",
        "Let this be another brick in a very solid foundation.",
        "You’re proving that you don’t need miracles to book wins.",
        "Keep investing nights like this into your long-term edge.",
        "You’re quietly putting together a serious body of work.",
        "Let this result encourage you to keep studying and applying.",
        "You’re finding a style that fits both you and the game.",
        "Keep letting patience be your biggest superpower.",
        "You’re building a graph that tells a disciplined story.",
        "Let this be a reminder that you can absolutely beat this environment.",
        "You’re turning knowledge into steady execution.",
        "Keep bringing this version of yourself to the table.",
        "You’re playing a game that scales well over time.",
        "Let this win sit in your memory for the tougher nights.",
        "You’re proving that you know how to close out a good session.",
        "Keep your standards here; the long-term graph will follow."
    ]

    // MARK: - Negative

    private static let negativeOpeners: [String] = [
        "Tough session – variance didn’t exactly cooperate.",
        "This one definitely landed on the rough side.",
        "The cards weren’t doing you many favors tonight.",
        "This session asked a lot from your resilience.",
        "You ran into some difficult spots this time.",
        "The deck felt pretty unfriendly overall.",
        "You were fighting uphill more often than not.",
        "The session was heavy on friction and light on flow.",
        "You faced more coolers than clean runouts.",
        "The spots you wanted just didn’t really materialize.",
        "You walked into a lineup that wasn’t easy to navigate.",
        "Board textures weren’t exactly lining up with your range.",
        "You seemed to get clipped in too many medium pots.",
        "The timing of your big hands wasn’t ideal tonight.",
        "Showdowns didn’t lean your way this time.",
        "You got put in some brutal decision points.",
        "You spent more time on the back foot than attacking.",
        "You had to weather far more losing stretches than usual.",
        "You kept getting squeezed out of promising spots.",
        "Runouts turned a lot of good situations into marginal ones.",
        "Your strong hands didn’t often stay strong by the river.",
        "Even good lines just weren’t getting paid this session.",
        "Your value bets ran into the top of people’s ranges more than once.",
        "You were on the wrong side of some big flips.",
        "A lot of reasonable decisions ran into bad outcomes.",
        "Your bluffs found the very top of their continuing ranges.",
        "You got an above-average share of awkward, bloated pots.",
        "You were often capped when others were still uncapped.",
        "The texture of this session leaned more punitive than kind.",
        "You had to absorb more pain than momentum tonight.",
        "The session never really let you get comfortable.",
        "You were constantly stuck in recovery mode.",
        "It felt like the deck had you specifically in mind.",
        "So many close spots seemed to fall the wrong way.",
        "Your patience was tested more than your skill this time.",
        "You ran into a lot of unexpected resistance at the table.",
        "The rhythm of the session stayed choppy from start to finish.",
        "The key pots you needed to go your way simply didn’t.",
        "You were forced into too many defensive decisions.",
        "You watched a lot of small losses stack into something bigger.",
        "The downswing energy was loud in this one.",
        "Your best decisions didn’t get rewarded on the scoreboard.",
        "You had to watch the graph lean the wrong direction.",
        "A lot of theoretically sound lines still lost chips tonight.",
        "You experienced the sharp end of variance here.",
        "The session leaned hard into the uncomfortable side of the game.",
        "You kept colliding with the top of people’s ranges.",
        "You saw more red numbers than you wanted on this run.",
        "The cards felt stubbornly one-sided against you.",
        "The river kept rewriting otherwise solid stories.",
        "You were forced to respect aggression more than you could punish it.",
        "You had to fold more strong hands than you’d like.",
        "You took a lot of spots that looked fine on paper but failed in practice.",
        "The deck chose chaos over cooperation tonight.",
        "Momentum just never seemed willing to stick.",
        "Every time you built something, the game knocked it back down.",
        "You got a full tour of the downside of variance.",
        "You spent more time in damage control than attack mode.",
        "Even your best spots came with strings attached.",
        "The table dynamic never fully broke your way.",
        "You kept seeing better runouts on everyone else’s boards.",
        "There were more bad beats than clean pickups.",
        "Your showdowns mostly ended with chips going the wrong direction.",
        "This one tilted more toward learning than winning.",
        "The session was stingier than usual with its rewards.",
        "You watched decent equity melt away a few too many times.",
        "You kept needing to reload mentally after rough hands.",
        "The night had more gut-punches than celebrations.",
        "You ran straight into the variance tax this time.",
        "The edges you had didn’t translate well to outcomes tonight.",
        "Coolers showed up right when you were trying to stabilize.",
        "Pot after pot seemed to slip just out of reach.",
        "The game kept you in uncomfortable territory for long stretches.",
        "You saw a lot of second-best hands at showdown.",
        "You ran headfirst into some very strong ranges.",
        "You were stuck playing from behind more than you’d like.",
        "You had to make peace with a lot of losing results.",
        "Each attempt to build momentum met fresh resistance.",
        "The high-leverage pots leaned against you this session.",
        "You felt the full weight of negative variance in real time.",
        "You got a concentrated dose of the game’s tougher side.",
        "Your resilience got more reps than your celebration muscles.",
        "You saw the ugly part of the distribution curve tonight.",
        "You hit the part of the graph that’s hard to love but very real.",
        "The runout reel would not win any awards this time.",
        "You had to sit through more setbacks than successes.",
        "You ran below expectation in some big spots.",
        "The session gave you more bruises than trophies.",
        "You took a lot of hits to the stack and the ego.",
        "You got a strong reminder that downswings are part of the job.",
        "This one leaned heavily into the ‘tuition payment’ category.",
        "You had to hold your nerve through some rough variance.",
        "You didn’t get much help from the deck at all.",
        "Tonight belonged to the other side of the table.",
        "You got a crash course in emotional bankroll management.",
        "You took some lumps that don’t feel great in the moment.",
        "You left with fewer chips but more perspective.",
        "It was a tough night for both bankroll and mindset.",
        "You had to navigate a lot of frustrating sequences.",
        "You saw the kind of session people gloss over in highlight reels."
    ]

    private static let negativeClosers: [String] = [
        "Still, nights like this are exactly why bankroll management exists.",
        "What matters now is protecting your confidence and coming back fresh.",
        "The result stings, but the next session is a blank slate.",
        "Let this one inform your growth, not define your ceiling.",
        "Bank the lesson, not the self-doubt.",
        "Use this loss as data, not a verdict on your skill.",
        "Sessions like this are painful but completely normal in the long run.",
        "You survived a rough night – that alone is work worth respecting.",
        "Walk away, reset, and let the graph smooth this one out over time.",
        "Tonight belongs to variance; the long run still belongs to discipline.",
        "Your job now is to recover well, not chase it back.",
        "The bankroll took a hit, but your edge can absolutely outlast it.",
        "You’re allowed to be frustrated, just don’t turn it into chaos.",
        "Sleep on this session before deciding what it means.",
        "Let this be a reminder that even good players book losing nights.",
        "Treat this as tuition for a long career, not proof you’re behind.",
        "Losses hurt, but quitting on yourself would hurt more.",
        "Give yourself credit for sitting through the discomfort without tilting off.",
        "You showed up and competed; that still matters.",
        "Tonight’s graph is one line in a very long story.",
        "You can review hands later – for now, focus on closing well.",
        "The best response to a night like this is a quiet, disciplined comeback.",
        "Use the frustration as fuel to refine, not to chase.",
        "The right move now is rest, not more risk.",
        "Let this session push you to tighten your process, not your fears.",
        "Even the best players collect sessions that look like this.",
        "Remember that downswings feel bigger up close than they do over time.",
        "Anchor to your long-term data, not one ugly night.",
        "Your identity as a player isn’t written by a single session.",
        "You can lose money without losing the lessons embedded in each hand.",
        "This is a chance to practice emotional discipline, not just technical skill.",
        "You handled the hit; now handle the recovery with care.",
        "Treat yourself like a long-term asset, not a short-term disappointment.",
        "Tonight goes in the ‘hard but useful’ category.",
        "Once the sting fades, there’s value waiting in the review.",
        "Don’t let one bad session erase dozens of good ones.",
        "The right comeback isn’t a heater – it’s a steady, focused return.",
        "This is where your mental game matters more than your card luck.",
        "Let this session remind you why structure and routines are so important.",
        "It’s okay to step back, breathe, and regroup.",
        "Short-term pain does not rewrite your long-term edge.",
        "You took a hit, but you also chose not to spiral.",
        "There’s quiet strength in walking away instead of forcing it.",
        "Bankrolls recover; good habits are what make sure they do.",
        "You can turn this frustration into better preparation.",
        "This loss doesn’t get to speak for your whole graph.",
        "The most important thing you protect right now is your mindset.",
        "You’re still the same player you were before the downswing.",
        "Let this be one low point in a generally rising line.",
        "A losing session is mandatory; staying stuck in its story is optional.",
        "Use what you learned here to sharpen your future instincts.",
        "The table was rough; be kind to yourself on the way out.",
        "Walking away now is a win for your discipline.",
        "Not every night is about profit – some are about resilience.",
        "This session might hurt today but help you months from now.",
        "You just strengthened the muscles you’ll need in every real downswing.",
        "Tonight showed you exactly why emotional bankroll matters.",
        "The loss is real, but so is the experience you just logged.",
        "Treat this as information, not identity.",
        "You can absorb this result without letting it own you.",
        "This is what the unglamorous side of the grind looks like.",
        "You’re allowed to feel this and still move forward.",
        "There’s no shame in a losing session played with honesty and effort.",
        "The game handed you rough variance; don’t add self-tilt on top.",
        "You earned the right to reset, reflect, and return stronger.",
        "A night like this doesn’t erase your hard-earned progress.",
        "Stay curious about what you can learn, not cruel about what you lost.",
        "Your future graph will barely remember this dot.",
        "Getting through this without punting more is a quiet victory.",
        "The best players remember: results are loud, but sample size is louder.",
        "You’ve seen worse graphs turn around – this one can, too.",
        "Your edge doesn’t disappear just because variance got loud.",
        "Let this be a data point, not a defining moment.",
        "You’re still building a skill set that can outlast nights like this.",
        "Tonight’s pain can become tomorrow’s discipline.",
        "Remember: one ugly session is statistically guaranteed.",
        "You showed you can walk away instead of spiraling.",
        "This loss is temporary; the lessons can compound.",
        "If you can handle nights like this, you can handle the grind.",
        "You protected your future by not chasing tonight.",
        "Trust that your long-term game can digest this result.",
        "You’re playing a marathon; this is one tough mile.",
        "There’s value in how you responded, not just in what you booked.",
        "Let this be another story you outgrow with time.",
        "You’re allowed bad sessions – they’re built into the price of admission.",
        "Keep your standards for effort high, even when results are low.",
        "This might be a red number, but it can still be a green lesson.",
        "The best thing you can do now is log it, learn, and move on.",
        "You’re learning how to stay a player, not become a gambler.",
        "This session is tough, but it’s still just one night’s data.",
        "You took the professional route by ending instead of chasing.",
        "Trust that your future volume will put this in context.",
        "Your job isn’t to avoid every bad night; it’s to outlast them.",
        "Use this as fuel to tighten leaks, not to loosen discipline.",
        "You’re building the resilience that long-term success demands.",
        "Treat the sting as proof that you care, not that you’re failing.",
        "One bad session cannot erase your capacity to improve.",
        "You learned something tonight that a winning session can’t teach.",
        "The graph dipped, but your commitment can still point upward.",
        "You’re still in the game – and that matters more than this one result."
    ]

    // MARK: - Public API

    static func randomPositivePhrase() -> String {
        let opener = positiveOpeners.randomElement() ?? ""
        let closer = positiveClosers.randomElement() ?? ""
        return "\(opener) \(closer)"
    }

    static func randomNegativePhrase() -> String {
        let opener = negativeOpeners.randomElement() ?? ""
        let closer = negativeClosers.randomElement() ?? ""
        return "\(opener) \(closer)"
    }

    static var positivePhraseCount: Int {
        positiveOpeners.count * positiveClosers.count
    }

    static var negativePhraseCount: Int {
        negativeOpeners.count * negativeClosers.count
    }
}

