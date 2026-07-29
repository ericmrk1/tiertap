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
            + tierTapPRORows(language)
            + tierTapPlusRows(language)
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

    /// When `searchQuery` is empty (after trimming), returns `sections` unchanged. Otherwise keeps only chapters whose title or any subsection heading/body matches, using a locale-aware case- and diacritic-insensitive search. If a subsection heading matches, the whole subsection is kept; if only some bullets or paragraphs match, only those rows are kept.
    static func filteredGuideSections(_ sections: [UserGuideTopSection], searchQuery: String) -> [UserGuideTopSection] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return sections }

        return sections.compactMap { section -> UserGuideTopSection? in
            if section.title.localizedStandardContains(q) {
                return section
            }

            let newSubsections: [UserGuideSubsection] = section.subsections.compactMap { sub -> UserGuideSubsection? in
                let heading = sub.heading ?? ""
                if heading.localizedStandardContains(q) {
                    return sub
                }

                let matchingRows: [UserGuideRow] = sub.rows.compactMap { row in
                    switch row {
                    case .paragraph(let s):
                        return s.localizedStandardContains(q) ? .paragraph(s) : nil
                    case .bullet(let s):
                        return s.localizedStandardContains(q) ? .bullet(s) : nil
                    case .h1, .h2:
                        return nil
                    }
                }
                guard !matchingRows.isEmpty else { return nil }
                return UserGuideSubsection(id: sub.id, heading: sub.heading, rows: matchingRows)
            }

            guard !newSubsections.isEmpty else { return nil }
            return UserGuideTopSection(id: section.id, title: section.title, subsections: newSubsections)
        }
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
            .h2(loc("User guide", language)),
            .paragraph(loc("Open the book icon on the Sessions toolbar anytime for this searchable guide. Use the share control to export the guide as PDF for offline reading.", language)),
        ]
    }

    private static func mainFeaturesRows(_ language: AppLanguage) -> [UserGuideRow] {
        [
            .h1(loc("Main features", language)),

            .h2(loc("Sessions (home)", language)),
            .paragraph(loc("What it does: Your hub for starting sessions, seeing an active session at a glance, and opening bankroll, history, and related tools.", language)),
            .paragraph(loc("How to use it:", language)),
            .bullet(loc("Tap Check In to pick game type (table games, slots, or poker), location (public or private), starting tier points, buy-in, free play, rewards program, and optional TierTap Wallet card. For poker, choose cash vs tournament and enter blinds or tournament details.", language)),
            .bullet(loc("Use the shortcut row for one-tap starts when you’ve set up favorite games and locations, or when a fast check-in preset exists from your last session.", language)),
            .bullet(loc("Open fast check-in settings (gear on the shortcut row) to review or edit saved presets per game category.", language)),
            .bullet(loc("When a session is live, a card shows elapsed time, venue, game, buy-in total, and comps. Tap it to open the full live session screen.", language)),
            .bullet(loc("From the home screen you can add extra buy-ins, free play, or comps, update stack (table games), open bankroll or wallet, review history, add a past session manually, or finish the live session.", language)),
            .bullet(loc("Fast close-out (slots-focused shortcut) saves the session immediately with default cash-out and unverified tier points—useful when you want a quick record without the full close-out form.", language)),
            .bullet(loc("Swipe the home metrics widget below the live card: recent sessions, a profit/loss activity grid, and closing-metrics rings (verified tier and published-session percentages).", language)),
            .bullet(loc("Tap Level shows progress based on your logged play; open the info control on the card to read how levels and milestones work, celebrate level-ups, or share your level as an image.", language)),
            .bullet(loc("The toolbar bell opens Play Reminders; the photo icon opens Photo Feed; the book icon opens this user guide.", language)),
            .paragraph(loc("Tips: Log buy-ins as they happen so totals stay accurate. Use private notes during play for anything you want to remember later.", language)),

            .h2(loc("Live session", language)),
            .paragraph(loc("What it does: A running timer and ledger for the session you’re in now.", language)),
            .paragraph(loc("How to use it:", language)),
            .bullet(loc("Review buy-ins, free play, and comps; add more at any time.", language)),
            .bullet(loc("For table games, update your stack manually to track chip count during play.", language)),
            .bullet(loc("Attach session photos and keep private notes that stay with the session.", language)),
            .bullet(loc("Share a formatted summary while the session is still live, if you want.", language)),
            .bullet(loc("Abort discards the live session entirely if you started by mistake.", language)),
            .bullet(loc("When you’re ready to leave, start close-out to enter cash-out, ending tier points, and other wrap-up details—or use fast close-out for a quick save.", language)),
            .paragraph(loc("Tips: You must have at least one buy-in or free play entry, plus game and location filled in, before you can close out. While a session is live, a lock-screen Live Activity shows the timer on iPhone (including Dynamic Island when supported).", language)),

            .h2(loc("Close-out and session mood", language)),
            .paragraph(loc("What it does: Turns a live session into a saved record with win/loss, tier progress, and optional photo or chip tools.", language)),
            .paragraph(loc("How to use it:", language)),
            .bullet(loc("Enter cash-out and ending tier points. Use quick denomination buttons or Lost everything for faster entry.", language)),
            .bullet(loc("Stop and resume the session timer during close-out if you’re still winding down; Uber and OpenTable shortcuts appear when the timer is stopped.", language)),
            .bullet(loc("If you use TierTap Pro, you can use chip estimation from a table photo when supported.", language)),
            .bullet(loc("Attach or review session photos before saving.", language)),
            .bullet(loc("If the session is linked to a TierTap Wallet card and your ending tier differs from the start, the app can update the card tier automatically and show a confirmation.", language)),
            .bullet(loc("If enabled in Settings, you’ll pick a session mood (how the session felt) after saving.", language)),
            .bullet(loc("After saving, you may be prompted to generate session art or publish to Community (TierTap Pro).", language)),
            .paragraph(loc("Tips: Average bet fields are entered later when completing Watch sessions or editing a saved session—not on the main close-out screen. If you indicate a difficult emotional outcome, the app may offer supportive resources you can open or dismiss.", language)),

            .h2(loc("Complete session (Watch)", language)),
            .paragraph(loc("What it does: Finishes sessions that were closed on Apple Watch with cash-out but still need average bet and tier verification on iPhone.", language)),
            .paragraph(loc("How to use it: Open History, find the session marked Incomplete, and tap Complete session. Enter average bet actual and rated, confirm ending tier points, and save.", language)),
            .paragraph(loc("Tips: You can also edit these fields later from the session detail screen.", language)),

            .h2(loc("History", language)),
            .paragraph(loc("What it does: Searchable, filterable list of saved sessions with an optional activity grid.", language)),
            .paragraph(loc("How to use it:", language)),
            .bullet(loc("Switch between Sessions (list) and Grid tabs. The grid shows play activity by day with selectable metrics (profit/loss, comps, tier changes).", language)),
            .bullet(loc("Filter by date range, game, or location, or use free-text search.", language)),
            .bullet(loc("Session rows show badges for verified vs unverified tier points and for incomplete Watch sessions.", language)),
            .bullet(loc("Open a session for details, editing, sharing, or deletion.", language)),
            .bullet(loc("Tools menu (wrench): bulk delete selected sessions, Tax Prep (TierTap Pro), and related utilities.", language)),
            .bullet(loc("Photo Feed (toolbar or Sessions tab) browses photos attached across all sessions.", language)),
            .paragraph(loc("Tips: Clear filters when your list looks empty but you know you have sessions.", language)),

            .h2(loc("Add past session", language)),
            .paragraph(loc("What it does: Lets you record a session that already ended so your stats stay complete.", language)),
            .paragraph(loc("How to use it: Enter the same kind of information as a live check-in and close-out, with times and amounts you remember.", language)),
            .paragraph(loc("Tips: Approximate values are fine; you can edit the session later from History.", language)),

            .h2(loc("Bankroll", language)),
            .paragraph(loc("What it does: Tracks your bankroll with a running total, timeline graph, and reset history alongside bankroll fields in Settings.", language)),
            .paragraph(loc("How to use it:", language)),
            .bullet(loc("Open from the Sessions tab for a focused bankroll screen during or between trips.", language)),
            .bullet(loc("Review the timeline chart and event list; reset bankroll when you want a fresh baseline.", language)),
            .bullet(loc("Share the bankroll graph as an image when you want a snapshot.", language)),
            .paragraph(loc("Tips: Keep bankroll in Settings updated so risk views stay meaningful.", language)),

            .h2(loc("TierTap Wallet", language)),
            .paragraph(loc("What it does: Stores photos of your loyalty cards or status screens with quick card details and optional tier-history overlay.", language)),
            .paragraph(loc("How to use it:", language)),
            .bullet(loc("Open TierTap Wallet from session flows (for card selection) or from app shortcuts where available.", language)),
            .bullet(loc("Tap + to add a card from Camera or Photo Library, then enter reward program, current tier, expiration date, and notes.", language)),
            .bullet(loc("Swipe through cards in the stack, switch between stack and single-card view, and use share to export a card image.", language)),
            .bullet(loc("Use the tier-history control to view progression snapshots captured over time for that card.", language)),
            .paragraph(loc("Tips: Keep the reward program and current tier fields up to date so check-in and tier tracking stay accurate.", language)),

            .h2(loc("Slot game reader", language)),
            .paragraph(loc("What it does: Uses TierTap AI to read a slot machine photo during check-in and suggest a game name with a short note.", language)),
            .paragraph(loc("How to use it:", language)),
            .bullet(loc("Start a Slots check-in, then tap Scan slot game name.", language)),
            .bullet(loc("Choose Camera or Photo Library and capture the machine title area as clearly as possible.", language)),
            .bullet(loc("Review the suggested game name and notes, then adjust before continuing if needed.", language)),
            .paragraph(loc("Tips: Frame the top game title and avoid glare or motion blur for better recognition.", language)),

            .h2(loc("Analytics", language)),
            .paragraph(loc("What it does: Charts and summaries of closed sessions, broken out by table games, slots, or poker where applicable.", language)),
            .paragraph(loc("How to use it:", language)),
            .bullet(loc("Choose the game category and optional date or location filters.", language)),
            .bullet(loc("Toggle between cash net and EV (cash plus logged comps) for results and some charts.", language)),
            .bullet(loc("Browse overview stats, graph styles (distribution, tier curve, bet rating, mood distribution, tier by loyalty program, and poker-specific cards when applicable).", language)),
            .bullet(loc("Open Risk of Ruin to compare play to your bankroll and target averages (table-focused; poker is handled separately in copy inside the app).", language)),
            .bullet(loc("With TierTap Pro, use Ask TierTap for natural-language style summaries of your data and share selected charts as images.", language)),
            .paragraph(loc("Tips: More accurate average bet and tier fields make analytics more useful.", language)),

            .h2(loc("Trips", language)),
            .paragraph(loc("What it does: Groups travel plans and past visits; link sessions to trips and share trip cards.", language)),
            .paragraph(loc("How to use it:", language)),
            .bullet(loc("Create or edit trips with dates, location, notes, and an optional cover photo. Trips are grouped as upcoming, current, or historical.", language)),
            .bullet(loc("Add flight legs (airlines, airports, route map) and lodging (hotels or other stays with map picker).", language)),
            .bullet(loc("Open a trip to see its timeline and linked sessions; link sessions after the fact if you forgot during play.", language)),
            .bullet(loc("Share a trip summary card as an image.", language)),
            .bullet(loc("Use the magic wand entry in the toolbar for AI-assisted trip suggestions when available.", language)),
            .paragraph(loc("Tips: A cover photo and flight/lodging details make trip cards easier to share and revisit later.", language)),

            .h2(loc("Community", language)),
            .paragraph(loc("What it does: A feed of sessions shared by the community, with filters and map viewing when you’re subscribed and signed in.", language)),
            .paragraph(loc("How to use it:", language)),
            .bullet(loc("Apply date and filter chips, search by display name, reload the feed, and switch to map view.", language)),
            .bullet(loc("Publish eligible sessions from the Community tab, after close-out, or from session detail. Choose what to include (win/loss, comps, tier rate, free play) and add an optional comment.", language)),
            .bullet(loc("Set your screen name and profile photo in your TierTap account so your posts appear as you prefer—or publish anonymously when offered.", language)),
            .paragraph(loc("Tips: Without Pro or a signed-in account, you’ll see upgrade prompts instead of the feed.", language)),

            .h2(loc("Widgets, shortcuts & Live Activity", language)),
            .paragraph(loc("What it does: Home-screen widgets, Siri shortcuts, and lock-screen timer for quick access without opening the full app.", language)),
            .paragraph(loc("How to use it:", language)),
            .bullet(loc("Add TierTap home or recent-sessions widgets from the iOS widget gallery. The home widget can show your live session and configurable metrics (bankroll, today’s play, win rate, Tap Level, running P/L, buy-in, last tier).", language)),
            .bullet(loc("Customize widget metrics in Settings → Theme → Home widget metrics.", language)),
            .bullet(loc("Use Siri shortcuts or widget taps to jump to check-in, live session, analytics, history, bankroll, or a specific session.", language)),
            .bullet(loc("While a session is live, the lock-screen Live Activity (and Dynamic Island on supported iPhones) shows the running timer.", language)),
            .paragraph(loc("Tips: Widget data refreshes when the app updates its snapshot—open TierTap occasionally for the most current numbers.", language)),

            .h2(loc("Settings", language)),
            .paragraph(loc("What it does: Account, subscriptions, bankroll and currency, favorites, session mood prompts, Play Reminders, TierTap AI tone and typing speed, themes, home widget layout, Watch Experience, data export, privacy links, and more.", language)),
            .paragraph(loc("How to use it:", language)),
            .bullet(loc("Expand each section. Export sessions as CSV from Data & Export.", language)),
            .bullet(loc("Manage favorites (table games, slot games, casinos), default game type, and common denominations for quick buy-in grids.", language)),
            .bullet(loc("Set target average win per session for Risk of Ruin under Target average.", language)),
            .bullet(loc("Configure Watch Experience (haptics, animations, pulse, wrist-raise summary, buy-in/comp defaults) to sync preferences to Apple Watch.", language)),
            .bullet(loc("About includes this user guide and a link to Gamblers Anonymous support resources.", language)),
            .paragraph(loc("Tips: Theme presets and custom colors change gradients across the app.", language)),

            .h2(loc("Account and subscription", language)),
            .paragraph(loc("What it does: Sign in or out, manage TierTap Pro, configure optional app lock, and set Community profile details.", language)),
            .paragraph(loc("How to use it: Reach TierTap Account from Settings; manage subscription from the Account section or paywall screens.", language)),
            .paragraph(loc("Tips: Signing out does not erase sessions stored on the device.", language)),

            .h2(loc("Apple Watch", language)),
            .paragraph(loc("What it does: Companion remote for live play—the iPhone owns session data; the Watch sends commands and shows synced state.", language)),
            .paragraph(loc("How to use it:", language)),
            .bullet(loc("When a session is live on iPhone, open Live Remote on Watch for timer, buy-in, free play, comp, stack, and food/beverage quick actions. Pause or unpause the timer from your wrist.", language)),
            .bullet(loc("End session from Watch: fast close-out (quick save), regular close-out (enter cash-out on Watch), or cancel/discard.", language)),
            .bullet(loc("When no session is live, use Fast Start on the timer tab to begin from the Watch (when synced).", language)),
            .bullet(loc("Browse History and Remotes (command delivery log) on Watch. Adjust theme, haptics, pulse, and quick-pick defaults in Watch Settings.", language)),
            .bullet(loc("Add TierTap corner complications to your watch face for casino, timer, buy-in, or stack/P&L at a glance.", language)),
            .paragraph(loc("Tips: Keep the watch and phone in sync for the most reliable session state. Finish incomplete Watch close-outs on iPhone via Complete session in History.", language)),
        ]
    }

    private static func tierTapPRORows(_ language: AppLanguage) -> [UserGuideRow] {
        [
            .h1(loc("TierTap PRO", language)),
            .paragraph(loc("TierTap Pro is the paid subscription that unlocks TierTap’s cloud-backed AI experiences and the Community feed. Most features also require you to be signed in with your TierTap account (email, Apple, or Google). You can subscribe or manage your plan from Settings → Upgrade to TierTap Pro / Manage TierTap Pro, or from the TierTap Pro paywall when the app prompts you.", language)),
            .h2(loc("Subscribe or manage", language)),
            .bullet(loc("Settings tab → Account → Upgrade to TierTap Pro (or Manage TierTap Pro when you are already subscribed).", language)),
            .bullet(loc("TierTap Account (from Settings) → Subscribe / Manage opens the same subscription choices.", language)),
            .bullet(loc("Some screens show an upgrade prompt that opens the TierTap Pro paywall directly.", language)),
            .h2(loc("What TierTap Pro includes", language)),
            .bullet(loc("Ask TierTap (AI Play Analysis): Analytics tab → Ask TierTap for natural-language summaries of your saved play data.", language)),
            .bullet(loc("AI session share images: After close-out or from session sharing flows, generate premium session art with TierTap AI where the app offers Generate Session Art or similar.", language)),
            .bullet(loc("Chip Estimator: During close-out, use the Chip Estimator camera flow to estimate stacks from a table photo (signed-in TierTap account required).", language)),
            .bullet(loc("Comp Estimator: When adding comps during a live session, capture a comp slip, receipt, or screen so TierTap AI can suggest a dollar value you can accept or edit.", language)),
            .bullet(loc("Slot reader: On a Slots check-in, tap Scan slot game name and use Camera or Photo Library so TierTap AI can read the machine title area.", language)),
            .bullet(loc("Trips magic wand: Trips tab → toolbar magic wand for AI-assisted trip suggestions when you are subscribed.", language)),
            .bullet(loc("Community: Community tab → browse, filter, map, and publish eligible sessions when you have TierTap Pro access and are signed in.", language)),
            .bullet(loc("Tax Preparation Documentation: Sessions tab → History → toolbar Tools (wrench) → Tax Prep. Subscribers can generate a US-focused tax assistance summary for a chosen calendar year with TierTap AI, then export documents including Annual Gambling Tax Summary (PDF), Session Ledger (CSV), W-2G Register (CSV), IRS Gambling Diary (PDF), CPA Packet (ZIP), and optional TurboTax Import (CSV). Have a tax professional review outputs; TierTap is not a CPA and this is not certified tax advice.", language)),
            .paragraph(loc("Tip: If a TierTap Pro feature looks inactive, confirm both an active subscription and sign-in, then retry after a good network connection.", language)),
        ]
    }

    private static func tierTapPlusRows(_ language: AppLanguage) -> [UserGuideRow] {
        [
            .h1(loc("TierTap+", language)),
            .paragraph(loc("TierTap+ is an optional token-pack purchase for more AI capacity. You can buy packs with or without a TierTap Pro subscription. With Pro, your subscription covers a per-calendar-month pool first, then any TierTap+ tokens you have purchased; without Pro, AI draws from your TierTap+ balance.", language)),
            .h2(loc("Why add tokens", language)),
            .bullet(loc("More headroom for Ask TierTap, image generation, chip and comp estimation, slot reading, trip magic wand, and other TierTap AI calls—without waiting for the next monthly reset if you have Pro, or as standalone AI capacity if you do not.", language)),
            .bullet(loc("Purchased tokens accumulate in your TierTap+ balance until used; usage charts help you see day-to-day trends.", language)),
            .h2(loc("Where to buy TierTap+ packs", language)),
            .bullet(loc("Settings tab → expand the TierTap+ section (labeled TierTap Plus in text-to-speech) → Buy TierTap+ Tokens when the pack appears with a store price.", language)),
            .bullet(loc("TierTap Account (Settings → TierTap Account) → AI token packs card has the same purchase control and shows balances.", language)),
            .h2(loc("Requirements", language)),
            .bullet(loc("TierTap+ packs can be purchased independently of a TierTap Pro subscription.", language)),
            .bullet(loc("Token packs are normal App Store consumables—use Restore Purchases on the TierTap Pro paywall if Apple confirms a sale but the balance did not update.", language)),
            .h2(loc("Track balances and usage", language)),
            .bullet(loc("Settings → TierTap+ section: switch the chart between sessions, tokens, and TierTap AI views for the selected month.", language)),
            .bullet(loc("TierTap Account: review purchased-pack balance, lifetime purchased total, pack usage, and how many Pro plan tokens remain this month.", language)),
        ]
    }

    private static func faqRows(_ language: AppLanguage) -> [UserGuideRow] {
        [
            .h1(loc("FAQ", language)),
            .h2(loc("Why doesn’t Community or AI work?", language)),
            .paragraph(loc("Those features require an active TierTap Pro subscription and a signed-in TierTap account.", language)),
            .h2(loc("Why can’t I close out?", language)),
            .paragraph(loc("The app needs a game, a location, and at least one buy-in or free play entry recorded for that session.", language)),
            .h2(loc("Where did my session go?", language)),
            .paragraph(loc("Finished sessions appear in History. Check filters and search if you don’t see them immediately.", language)),
            .h2(loc("What is an Incomplete session?", language)),
            .paragraph(loc("Sessions closed on Apple Watch may save with cash-out but still need average bet and tier details. Open Complete session from History to finish them.", language)),
            .h2(loc("How do I back up my data?", language)),
            .paragraph(loc("Use Export sessions as CSV in Settings to send a file to Files, email, or another app.", language)),
            .h2(loc("Can I change language or currency?", language)),
            .paragraph(loc("Yes—use App language and Currency in Settings under Bankroll & Localization.", language)),
            .h2(loc("Why did slot scanning fail?", language)),
            .paragraph(loc("Slot scanning needs TierTap Pro, a signed-in account, and a clear machine photo. Try retaking the image with the title area in focus and less glare.", language)),
            .h2(loc("How do home-screen widgets stay current?", language)),
            .paragraph(loc("Widgets read a snapshot TierTap writes when the app runs. Open the app after logging play so live session and metric widgets refresh.", language)),
            .h2(loc("How do I update or remove a wallet card?", language)),
            .paragraph(loc("Open TierTap Wallet, select the card, then use Edit card for details/photo updates or Delete card to remove it permanently.", language)),
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
            .h2(loc("Slot scanner can’t identify game name", language)),
            .paragraph(loc("Use a tighter, well-lit photo of the machine title area and retry. If recognition still fails, enter the game manually and continue.", language)),
            .h2(loc("Wallet card image or details are outdated", language)),
            .paragraph(loc("Open TierTap Wallet, edit the card, and retake or replace the photo. Save changes to refresh what appears in selection and share views.", language)),
            .h2(loc("Watch session stuck or out of sync", language)),
            .paragraph(loc("Keep iPhone and Watch paired and TierTap open on the phone when possible. Check Remotes on Watch for command status. Finish incomplete sessions on iPhone via Complete session in History.", language)),
            .h2(loc("Live Activity or widget shows stale data", language)),
            .paragraph(loc("Open TierTap on iPhone to refresh the widget snapshot and reconcile the Live Activity with your current live session.", language)),
        ]
    }
}
