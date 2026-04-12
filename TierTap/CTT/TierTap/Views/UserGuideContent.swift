import Foundation

/// Structured rows for in-app display and plain-text PDF export (no implementation details).
enum UserGuideRow {
    case h1(String)
    case h2(String)
    case paragraph(String)
    case bullet(String)
}

/// One top-level guide chapter (from an `h1` heading).
struct UserGuideTopSection: Identifiable {
    let id: String
    let title: String
    let subsections: [UserGuideSubsection]
}

/// A block under a chapter: either intro text (`heading == nil`) or an `h2` subsection.
struct UserGuideSubsection: Identifiable {
    let id: String
    let heading: String?
    let rows: [UserGuideRow]
}

enum UserGuideContent {
    /// Localized rows for the current app language (`\.appLanguage` / `SettingsStore.appLanguage`).
    static func rows(for language: AppLanguage) -> [UserGuideRow] {
        overviewRows(language)
            + gettingStartedRows(language)
            + mainFeaturesRows(language)
            + faqRows(language)
            + troubleshootingRows(language)
    }

    /// Chapters and subsections for the in-app guide (expand/collapse UI). PDF export still uses `rows(for:)`.
    static func guideSections(for language: AppLanguage) -> [UserGuideTopSection] {
        let all = rows(for: language)
        var topSections: [UserGuideTopSection] = []
        var index = 0
        var topIndex = 0
        while index < all.count {
            guard case .h1(let title) = all[index] else {
                index += 1
                continue
            }
            index += 1
            var slice: [UserGuideRow] = []
            while index < all.count {
                if case .h1 = all[index] { break }
                slice.append(all[index])
                index += 1
            }
            let subsections = parseSubsections(from: slice, topIndex: topIndex)
            topSections.append(
                UserGuideTopSection(
                    id: "guide-top-\(topIndex)",
                    title: title,
                    subsections: subsections
                )
            )
            topIndex += 1
        }
        return topSections
    }

    static func plainTextForPDF(language: AppLanguage) -> String {
        let locale = language.locale
        var lines: [String] = []
        for row in rows(for: language) {
            switch row {
            case .h1(let s):
                lines.append("")
                lines.append(s.uppercased(with: locale))
                lines.append(String(repeating: "=", count: min(s.count, 50)))
            case .h2(let s):
                lines.append("")
                lines.append(s)
            case .paragraph(let s):
                lines.append(s)
            case .bullet(let s):
                lines.append("• \(s)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func loc(_ key: String, _ language: AppLanguage) -> String {
        L10n.tr(key, language: language)
    }

    private static func parseSubsections(from rows: [UserGuideRow], topIndex: Int) -> [UserGuideSubsection] {
        var result: [UserGuideSubsection] = []
        var currentHeading: String?
        var currentRows: [UserGuideRow] = []
        var subIndex = 0

        func appendCurrentBlock() {
            guard currentHeading != nil || !currentRows.isEmpty else { return }
            let id = "guide-top-\(topIndex)-sub-\(subIndex)"
            result.append(UserGuideSubsection(id: id, heading: currentHeading, rows: currentRows))
            subIndex += 1
            currentHeading = nil
            currentRows = []
        }

        for row in rows {
            switch row {
            case .h2(let title):
                appendCurrentBlock()
                currentHeading = title
            case .paragraph, .bullet:
                currentRows.append(row)
            case .h1:
                break
            }
        }
        appendCurrentBlock()
        return result
    }

    private static func overviewRows(_ language: AppLanguage) -> [UserGuideRow] {
        [
            .h1(loc("App overview", language)),
            .paragraph(loc("TierTap helps you log casino play sessions—buy-ins, comps, tier points, and outcomes—then review history, analytics, trips, and optional community sharing. The app is organized around five main tabs: Analytics, Trips, Sessions (home), Community, and Settings.", language)),
            .paragraph(loc("A TierTap Pro subscription plus a signed-in account unlocks AI-powered analysis, chip estimation at close-out, and the Community feed. Core session logging works on your device either way.", language)),
        ]
    }

    private static func gettingStartedRows(_ language: AppLanguage) -> [UserGuideRow] {
        [
            .h1(loc("Getting started", language)),
            .h2(loc("First launch", language)),
            .bullet(loc("You’ll briefly see the splash screen, then land on the main tab bar.", language)),
            .bullet(loc("If account sign-in is offered, you can sign in now or later from Settings.", language)),
            .h2(loc("Optional app lock", language)),
            .paragraph(loc("In your TierTap account area you can require Face ID, Touch ID, or your device passcode before the app opens after you leave it or return from the background.", language)),
            .h2(loc("Start logging", language)),
            .paragraph(loc("Open the Sessions tab. Tap Check In to begin a new live session, or use the quick shortcuts when you have favorites configured. When you’re done playing, finish the live session and complete close-out.", language)),
        ]
    }

    private static func mainFeaturesRows(_ language: AppLanguage) -> [UserGuideRow] {
        [
            .h1(loc("Main features", language)),

            .h2(loc("Sessions (home)", language)),
            .paragraph(loc("What it does: Your hub for starting sessions, seeing an active session at a glance, and opening bankroll, history, and related tools.", language)),
            .paragraph(loc("How to use it:", language)),
            .bullet(loc("Tap Check In to pick game type (table games, slots, or poker), location, starting tier points, buy-in, and loyalty program details.", language)),
            .bullet(loc("Use the shortcut row for one-tap starts when you’ve set up favorite games and locations.", language)),
            .bullet(loc("When a session is live, a card shows elapsed time, venue, game, buy-in total, and comps. Tap it to open the full live session screen.", language)),
            .bullet(loc("From the home screen you can add extra buy-ins or comps, open bankroll tools, review history, add a past session manually, or finish the live session.", language)),
            .bullet(loc("Tap Level shows progress based on your logged play; open the info control on the card to read how levels and milestones work, or share your level as an image.", language)),
            .paragraph(loc("Tips: Log buy-ins as they happen so totals stay accurate. Use private notes during play for anything you want to remember later.", language)),

            .h2(loc("Live session", language)),
            .paragraph(loc("What it does: A running timer and ledger for the session you’re in now.", language)),
            .paragraph(loc("How to use it:", language)),
            .bullet(loc("Review buy-ins and comps, add more at any time, and open strategy or odds reference for your game.", language)),
            .bullet(loc("Keep private notes that stay with the session.", language)),
            .bullet(loc("When you’re ready to leave, start close-out to enter cash-out, ending tier points, and other wrap-up details.", language)),
            .paragraph(loc("Tips: You must have at least one buy-in, plus game and location filled in, before you can close out.", language)),

            .h2(loc("Close-out and session mood", language)),
            .paragraph(loc("What it does: Turns a live session into a saved record with win/loss, tier progress, and optional photo or chip tools.", language)),
            .paragraph(loc("How to use it:", language)),
            .bullet(loc("Enter cash-out and ending tier points (and other fields the app asks for, such as average bet where applicable).", language)),
            .bullet(loc("If you use TierTap Pro, you can use chip estimation from a table photo when supported.", language)),
            .bullet(loc("If enabled in Settings, you’ll pick a session mood (how the session felt) after saving.", language)),
            .paragraph(loc("Tips: If you indicate a difficult emotional outcome, the app may offer supportive resources you can open or dismiss.", language)),

            .h2(loc("History", language)),
            .paragraph(loc("What it does: Searchable, filterable list of saved sessions.", language)),
            .paragraph(loc("How to use it:", language)),
            .bullet(loc("Filter by date range, game, location, tier verification state, or free-text search.", language)),
            .bullet(loc("Open a session for details, editing, sharing, or deletion.", language)),
            .paragraph(loc("Tips: Clear filters when your list looks empty but you know you have sessions.", language)),

            .h2(loc("Add past session", language)),
            .paragraph(loc("What it does: Lets you record a session that already ended so your stats stay complete.", language)),
            .paragraph(loc("How to use it: Enter the same kind of information as a live check-in and close-out, with times and amounts you remember.", language)),
            .paragraph(loc("Tips: Approximate values are fine; you can edit the session later from History.", language)),

            .h2(loc("Bankroll", language)),
            .paragraph(loc("What it does: Tracks bankroll-related views tied to your settings and play (alongside bankroll fields in Settings).", language)),
            .paragraph(loc("How to use it: Open from the Sessions tab when you want a focused bankroll screen during or between trips.", language)),
            .paragraph(loc("Tips: Keep bankroll and unit size in Settings updated so risk views stay meaningful.", language)),

            .h2(loc("Analytics", language)),
            .paragraph(loc("What it does: Charts and summaries of closed sessions, broken out by table games, slots, or poker where applicable.", language)),
            .paragraph(loc("How to use it:", language)),
            .bullet(loc("Choose the game category and optional date or location filters.", language)),
            .bullet(loc("Open Risk of Ruin to compare play to your bankroll and target averages (table-focused; poker is handled separately in copy inside the app).", language)),
            .bullet(loc("With TierTap Pro, use Ask TierTap for natural-language style summaries of your data and share selected charts as images.", language)),
            .paragraph(loc("Tips: More accurate average bet and tier fields make analytics more useful.", language)),

            .h2(loc("Trips", language)),
            .paragraph(loc("What it does: Groups travel plans and past visits; link sessions to trips and share trip cards.", language)),
            .paragraph(loc("How to use it:", language)),
            .bullet(loc("Create or edit trips with dates and details; open a trip to see its timeline and linked sessions.", language)),
            .bullet(loc("Use the magic wand entry in the toolbar for AI-assisted trip suggestions when available.", language)),
            .paragraph(loc("Tips: Link sessions after the fact if you forgot during play.", language)),

            .h2(loc("Community", language)),
            .paragraph(loc("What it does: A feed of sessions shared by the community, with filters and map viewing when you’re subscribed and signed in.", language)),
            .paragraph(loc("How to use it: Apply date and filter chips, search by display name, reload the feed, and publish your own eligible sessions when the app offers it.", language)),
            .paragraph(loc("Tips: Without Pro or a signed-in account, you’ll see upgrade prompts instead of the feed.", language)),

            .h2(loc("Settings", language)),
            .paragraph(loc("What it does: Account, subscriptions, bankroll and currency, favorites, session mood prompts, TierTap AI tone and typing speed, themes, data export, privacy links, and more.", language)),
            .paragraph(loc("How to use it: Expand each section. Export sessions as CSV from Data & Export. Manage favorites to power quick check-in and buy-in grids.", language)),
            .paragraph(loc("Tips: Theme presets and custom colors change gradients across the app.", language)),

            .h2(loc("Account and subscription", language)),
            .paragraph(loc("What it does: Sign in or out, manage TierTap Pro, and configure optional app lock.", language)),
            .paragraph(loc("How to use it: Reach TierTap Account from Settings; manage subscription from the Account section or paywall screens.", language)),
            .paragraph(loc("Tips: Signing out does not erase sessions stored on the device.", language)),

            .h2(loc("Apple Watch", language)),
            .paragraph(loc("What it does: Companion experience to start or monitor play from your wrist, with details completed on iPhone when needed.", language)),
            .paragraph(loc("How to use it: Open TierTap on Apple Watch and follow the start and live flows; finish missing details on the phone if prompted.", language)),
            .paragraph(loc("Tips: Keep the watch and phone in sync for the most reliable session state.", language)),
        ]
    }

    private static func faqRows(_ language: AppLanguage) -> [UserGuideRow] {
        [
            .h1(loc("FAQ", language)),
            .h2(loc("Why doesn’t Community or AI work?", language)),
            .paragraph(loc("Those features require an active TierTap Pro subscription and a signed-in TierTap account.", language)),
            .h2(loc("Why can’t I close out?", language)),
            .paragraph(loc("The app needs a game, a location, and at least one buy-in recorded for that session.", language)),
            .h2(loc("Where did my session go?", language)),
            .paragraph(loc("Finished sessions appear in History. Check filters and search if you don’t see them immediately.", language)),
            .h2(loc("How do I back up my data?", language)),
            .paragraph(loc("Use Export sessions as CSV in Settings to send a file to Files, email, or another app.", language)),
            .h2(loc("Can I change language or currency?", language)),
            .paragraph(loc("Yes—use App language and Currency in Settings under Bankroll & Localization.", language)),
        ]
    }

    private static func troubleshootingRows(_ language: AppLanguage) -> [UserGuideRow] {
        [
            .h1(loc("Troubleshooting", language)),
            .h2(loc("App asks to unlock every time", language)),
            .paragraph(loc("App lock is enabled. Turn it off in your TierTap account settings if you prefer not to authenticate each return to the app.", language)),
            .h2(loc("Community feed errors or empty feed", language)),
            .paragraph(loc("Confirm you’re signed in, have Pro access, and try adjusting or clearing filters. Poor network connectivity can also delay loading.", language)),
            .h2(loc("Analytics looks sparse", language)),
            .paragraph(loc("Analytics uses closed sessions with complete outcomes. Add or finish sessions, and check that the selected game category matches how sessions were saved.", language)),
            .h2(loc("CSV export fails or is empty", language)),
            .paragraph(loc("Pick a game type that matches the sessions you’ve saved; older entries may default to table games.", language)),
            .h2(loc("Sign-in sheet keeps appearing", language)),
            .paragraph(loc("You may be signed out, or the app may be offering account setup after unlock. Sign in once or dismiss if you’ll continue without account features.", language)),
        ]
    }
}
