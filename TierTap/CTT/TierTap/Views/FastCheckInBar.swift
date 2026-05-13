import SwiftUI

/// Resolved parameters for a one-tap fast check-in (home screen).
struct FastCheckInPlan {
    let category: SessionGameCategory
    let template: Session?
    let casinoValue: String
    let gameName: String
    let startingTier: Int
    let initialBuyIn: Int
    let rewardsProgramName: String?
    let casinoLatitude: Double?
    let casinoLongitude: Double?

    var needsTierTrackingWarning: Bool { startingTier <= 0 }
}

/// Shared fast check-in logic (used from the home screen).
enum FastCheckInHelper {
    /// Saved fast check-in preset, if any, otherwise the most recent finished session for that category.
    static func effectiveTemplateSession(category: SessionGameCategory, store: SessionStore, settingsStore: SettingsStore) -> Session? {
        if let preset = settingsStore.fastCheckInSavedPreset(for: category) {
            return preset.makeTemplateSession(for: category)
        }
        return store.mostRecentSession(forGameCategory: category)
    }

    static func canFastCheckIn(category: SessionGameCategory, store: SessionStore, settingsStore: SettingsStore) -> Bool {
        effectiveTemplateSession(category: category, store: store, settingsStore: settingsStore) != nil
    }

    static func composedPokerGameName(
        pokerGameKind: SessionPokerGameKind,
        pokerVariant: String,
        pokerAllowsRebuy: Bool,
        pokerAllowsAddOn: Bool,
        pokerHasFreezeOut: Bool
    ) -> String {
        var parts: [String] = []
        let kindLabel = (pokerGameKind == .cash) ? "Cash" : "Tournament"
        parts.append("Poker \(kindLabel)")
        if !pokerVariant.isEmpty {
            parts.append(pokerVariant)
        }
        if pokerGameKind == .tournament {
            var opts: [String] = []
            if pokerAllowsRebuy { opts.append("Re-buy") }
            if pokerAllowsAddOn { opts.append("Add-On") }
            if pokerHasFreezeOut { opts.append("Freeze-Out") }
            if !opts.isEmpty {
                parts.append(opts.joined(separator: ", "))
            }
        }
        return parts.joined(separator: " - ")
    }

    private static func composedPokerGameName(from defaults: LastPokerSessionDefaults) -> String {
        composedPokerGameName(
            pokerGameKind: defaults.pokerGameKind,
            pokerVariant: defaults.pokerVariant,
            pokerAllowsRebuy: defaults.pokerAllowsRebuy,
            pokerAllowsAddOn: defaults.pokerAllowsAddOn,
            pokerHasFreezeOut: defaults.pokerHasFreezeOut
        )
    }

    private static func pokerDefaultsForFastCheckIn(settingsStore: SettingsStore) -> LastPokerSessionDefaults {
        settingsStore.lastPokerSessionDefaults
            ?? LastPokerSessionDefaults(
                pokerGameKind: .cash,
                pokerAllowsRebuy: false,
                pokerAllowsAddOn: false,
                pokerHasFreezeOut: false,
                pokerVariant: "No Limit Texas Hold’em",
                pokerSmallBlind: 0,
                pokerBigBlind: 0,
                pokerAnte: 0,
                pokerLevelMinutesText: "",
                pokerStartingStackText: "",
                pokerTournamentCostText: "0"
            )
    }

    private static func lastPokerDefaultsMatchingSession(_ session: Session, settingsStore: SettingsStore) -> LastPokerSessionDefaults {
        LastPokerSessionDefaults(
            pokerGameKind: session.pokerGameKind ?? .cash,
            pokerAllowsRebuy: session.pokerAllowsRebuy ?? false,
            pokerAllowsAddOn: session.pokerAllowsAddOn ?? false,
            pokerHasFreezeOut: session.pokerHasFreeOut ?? false,
            pokerVariant: session.pokerVariant ?? "No Limit Texas Hold’em",
            pokerSmallBlind: session.pokerSmallBlind ?? 0,
            pokerBigBlind: session.pokerBigBlind ?? 0,
            pokerAnte: session.pokerAnte ?? 0,
            pokerLevelMinutesText: session.pokerLevelMinutes.map { String($0) } ?? "",
            pokerStartingStackText: session.pokerStartingStack.map { String($0) } ?? "",
            pokerTournamentCostText: settingsStore.lastPokerSessionDefaults?.pokerTournamentCostText ?? "0"
        )
    }

    static func makePlan(category: SessionGameCategory, store: SessionStore, settingsStore: SettingsStore) -> FastCheckInPlan {
        let template = effectiveTemplateSession(category: category, store: store, settingsStore: settingsStore)

        let casinoValue: String
        var gameName: String
        var startingTier: Int
        var initialBuyIn: Int
        let rewardsProgramName: String?
        let lat: Double?
        let lon: Double?

        if let t = template {
            casinoValue = t.casino
            gameName = t.game
            if gameName.isEmpty {
                switch category {
                case .table:
                    gameName = settingsStore.lastTableGameName
                case .slots:
                    gameName = settingsStore.lastSlotGameName
                case .poker:
                    gameName = composedPokerGameName(from: lastPokerDefaultsMatchingSession(t, settingsStore: settingsStore))
                }
            }
            startingTier = t.startingTierPoints
            initialBuyIn = t.initialBuyIn.flatMap { $0 > 0 ? $0 : nil } ?? 1
            rewardsProgramName = t.rewardsProgramName
            lat = t.casinoLatitude
            lon = t.casinoLongitude
        } else {
            casinoValue = store.mostRecentCasino() ?? ""
            switch category {
            case .table:
                gameName = settingsStore.lastTableGameName
            case .slots:
                gameName = settingsStore.lastSlotGameName
            case .poker:
                gameName = composedPokerGameName(from: pokerDefaultsForFastCheckIn(settingsStore: settingsStore))
            }
            startingTier = 0
            initialBuyIn = 1
            if store.hasSessionHistory(forExactCasino: casinoValue) {
                if let tier = store.defaultEndingTierPoints(for: casinoValue), tier > 0 {
                    startingTier = tier
                }
                if let buy = store.defaultInitialBuyIn(for: casinoValue), buy > 0 {
                    initialBuyIn = buy
                }
            }
            rewardsProgramName = nil
            lat = nil
            lon = nil
        }

        return FastCheckInPlan(
            category: category,
            template: template,
            casinoValue: casinoValue,
            gameName: gameName,
            startingTier: startingTier,
            initialBuyIn: initialBuyIn,
            rewardsProgramName: rewardsProgramName,
            casinoLatitude: lat,
            casinoLongitude: lon
        )
    }

    static func performFastCheckIn(plan: FastCheckInPlan, store: SessionStore, settingsStore: SettingsStore) {
        let category = plan.category
        let template = plan.template
        guard template != nil else { return }

        store.startSession(
            game: plan.gameName,
            casino: plan.casinoValue,
            startingTier: plan.startingTier,
            initialBuyIn: plan.initialBuyIn,
            rewardsProgramName: plan.rewardsProgramName,
            casinoLatitude: plan.casinoLatitude,
            casinoLongitude: plan.casinoLongitude,
            linkedRewardWalletCardId: template?.linkedRewardWalletCardId
        )

        if let t = template {
            let cat = t.gameCategory ?? category
            let slotMeta = Session.persistedSlotMetadata(
                gameCategory: cat,
                format: t.slotFormat,
                formatOther: t.slotFormatOther ?? "",
                feature: t.slotFeature,
                featureOther: t.slotFeatureOther ?? "",
                notes: t.slotNotes ?? ""
            )
            let kind: SessionPokerGameKind? = (cat == .poker) ? (t.pokerGameKind ?? .cash) : nil
            let rebuy: Bool? = (cat == .poker && kind == .tournament) ? (t.pokerAllowsRebuy ?? false) : nil
            let addOn: Bool? = (cat == .poker && kind == .tournament) ? (t.pokerAllowsAddOn ?? false) : nil
            let freeOut: Bool? = (cat == .poker && kind == .tournament) ? (t.pokerHasFreeOut ?? false) : nil
            let variant: String? = (cat == .poker) ? t.pokerVariant : nil
            let sb: Int? = (cat == .poker && (t.pokerSmallBlind ?? 0) > 0) ? t.pokerSmallBlind : nil
            let bb: Int? = (cat == .poker && (t.pokerBigBlind ?? 0) > 0) ? t.pokerBigBlind : nil
            let ante: Int? = (cat == .poker && (t.pokerAnte ?? 0) > 0) ? t.pokerAnte : nil
            let levelMinutes: Int? = (cat == .poker && kind == .tournament) ? t.pokerLevelMinutes : nil
            let startingStack: Int? = (cat == .poker && kind == .tournament) ? t.pokerStartingStack : nil
            store.updateLiveSessionGameMetadata(
                gameCategory: cat,
                pokerGameKind: kind,
                pokerAllowsRebuy: rebuy,
                pokerAllowsAddOn: addOn,
                pokerHasFreeOut: freeOut,
                pokerVariant: variant,
                pokerSmallBlind: sb,
                pokerBigBlind: bb,
                pokerAnte: ante,
                pokerLevelMinutes: levelMinutes,
                pokerStartingStack: startingStack,
                slotFormat: slotMeta.format,
                slotFormatOther: slotMeta.formatOther,
                slotFeature: slotMeta.feature,
                slotFeatureOther: slotMeta.featureOther,
                slotNotes: slotMeta.notes
            )
            let d = lastPokerDefaultsMatchingSession(t, settingsStore: settingsStore)
            settingsStore.recordLastCheckInGameSelection(
                gameCategory: cat,
                selectedGame: plan.gameName,
                pokerGameKind: d.pokerGameKind,
                pokerAllowsRebuy: d.pokerAllowsRebuy,
                pokerAllowsAddOn: d.pokerAllowsAddOn,
                pokerHasFreezeOut: d.pokerHasFreezeOut,
                pokerVariant: d.pokerVariant,
                pokerSmallBlind: d.pokerSmallBlind,
                pokerBigBlind: d.pokerBigBlind,
                pokerAnte: d.pokerAnte,
                pokerLevelMinutesText: d.pokerLevelMinutesText,
                pokerStartingStackText: d.pokerStartingStackText,
                pokerTournamentCostText: d.pokerTournamentCostText,
                slotNotes: slotMeta.notes ?? ""
            )
        } else {
            switch category {
            case .table:
                store.updateLiveSessionGameMetadata(
                    gameCategory: .table,
                    pokerGameKind: nil,
                    pokerAllowsRebuy: nil,
                    pokerAllowsAddOn: nil,
                    pokerHasFreeOut: nil,
                    pokerVariant: nil,
                    pokerSmallBlind: nil,
                    pokerBigBlind: nil,
                    pokerAnte: nil,
                    pokerLevelMinutes: nil,
                    pokerStartingStack: nil,
                    slotFormat: nil,
                    slotFormatOther: nil,
                    slotFeature: nil,
                    slotFeatureOther: nil,
                    slotNotes: nil
                )
                settingsStore.recordLastCheckInGameSelection(
                    gameCategory: .table,
                    selectedGame: plan.gameName,
                    pokerGameKind: .cash,
                    pokerAllowsRebuy: false,
                    pokerAllowsAddOn: false,
                    pokerHasFreezeOut: false,
                    pokerVariant: "No Limit Texas Hold’em",
                    pokerSmallBlind: 0,
                    pokerBigBlind: 0,
                    pokerAnte: 0,
                    pokerLevelMinutesText: "",
                    pokerStartingStackText: "",
                    pokerTournamentCostText: "0",
                    slotNotes: ""
                )
            case .slots:
                let notes = settingsStore.lastSlotSessionDefaults?.slotNotes ?? ""
                let slotMeta = Session.persistedSlotMetadata(
                    gameCategory: .slots,
                    format: nil,
                    formatOther: "",
                    feature: nil,
                    featureOther: "",
                    notes: notes
                )
                store.updateLiveSessionGameMetadata(
                    gameCategory: .slots,
                    pokerGameKind: nil,
                    pokerAllowsRebuy: nil,
                    pokerAllowsAddOn: nil,
                    pokerHasFreeOut: nil,
                    pokerVariant: nil,
                    pokerSmallBlind: nil,
                    pokerBigBlind: nil,
                    pokerAnte: nil,
                    pokerLevelMinutes: nil,
                    pokerStartingStack: nil,
                    slotFormat: slotMeta.format,
                    slotFormatOther: slotMeta.formatOther,
                    slotFeature: slotMeta.feature,
                    slotFeatureOther: slotMeta.featureOther,
                    slotNotes: slotMeta.notes
                )
                settingsStore.recordLastCheckInGameSelection(
                    gameCategory: .slots,
                    selectedGame: plan.gameName,
                    pokerGameKind: .cash,
                    pokerAllowsRebuy: false,
                    pokerAllowsAddOn: false,
                    pokerHasFreezeOut: false,
                    pokerVariant: "No Limit Texas Hold’em",
                    pokerSmallBlind: 0,
                    pokerBigBlind: 0,
                    pokerAnte: 0,
                    pokerLevelMinutesText: "",
                    pokerStartingStackText: "",
                    pokerTournamentCostText: "0",
                    slotNotes: slotMeta.notes ?? ""
                )
            case .poker:
                let d = pokerDefaultsForFastCheckIn(settingsStore: settingsStore)
                let kind = d.pokerGameKind
                let rebuy: Bool? = (kind == .tournament) ? d.pokerAllowsRebuy : nil
                let addOn: Bool? = (kind == .tournament) ? d.pokerAllowsAddOn : nil
                let freeOut: Bool? = (kind == .tournament) ? d.pokerHasFreezeOut : nil
                let sb: Int? = (d.pokerSmallBlind > 0) ? d.pokerSmallBlind : nil
                let bb: Int? = (d.pokerBigBlind > 0) ? d.pokerBigBlind : nil
                let ante: Int? = (d.pokerAnte > 0) ? d.pokerAnte : nil
                let levelMinutes: Int? = (kind == .tournament) ? Int(d.pokerLevelMinutesText) : nil
                let startingStack: Int? = (kind == .tournament) ? Int(d.pokerStartingStackText) : nil
                store.updateLiveSessionGameMetadata(
                    gameCategory: .poker,
                    pokerGameKind: kind,
                    pokerAllowsRebuy: rebuy,
                    pokerAllowsAddOn: addOn,
                    pokerHasFreeOut: freeOut,
                    pokerVariant: d.pokerVariant,
                    pokerSmallBlind: sb,
                    pokerBigBlind: bb,
                    pokerAnte: ante,
                    pokerLevelMinutes: levelMinutes,
                    pokerStartingStack: startingStack,
                    slotFormat: nil,
                    slotFormatOther: nil,
                    slotFeature: nil,
                    slotFeatureOther: nil,
                    slotNotes: nil
                )
                settingsStore.recordLastCheckInGameSelection(
                    gameCategory: .poker,
                    selectedGame: plan.gameName,
                    pokerGameKind: d.pokerGameKind,
                    pokerAllowsRebuy: d.pokerAllowsRebuy,
                    pokerAllowsAddOn: d.pokerAllowsAddOn,
                    pokerHasFreezeOut: d.pokerHasFreezeOut,
                    pokerVariant: d.pokerVariant,
                    pokerSmallBlind: d.pokerSmallBlind,
                    pokerBigBlind: d.pokerBigBlind,
                    pokerAnte: d.pokerAnte,
                    pokerLevelMinutesText: d.pokerLevelMinutesText,
                    pokerStartingStackText: d.pokerStartingStackText,
                    pokerTournamentCostText: d.pokerTournamentCostText,
                    slotNotes: ""
                )
            }
        }

        if settingsStore.enableCasinoFeedback {
            CelebrationPlayer.shared.playQuickChime()
        }
    }

    /// One-line status for the fast check-in summary screen (localized).
    static func fastCheckInStatusLabel(category: SessionGameCategory, store: SessionStore, settingsStore: SettingsStore, language: AppLanguage) -> String {
        if canFastCheckIn(category: category, store: store, settingsStore: settingsStore) {
            return L10n.tr("Ready", language: language)
        }
        return L10n.tr("Not set up yet", language: language)
    }
}

/// Summaries for each game type on the fast check-in settings sheet.
struct FastCheckInSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    let onRequestOpenCheckIn: (SessionGameCategory) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        L10nText("Fast check-in uses your last finished session for each game type. Check in once to enable a shortcut, or edit details below.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)

                        fastCheckInSummaryCard(.poker, emoji: "♠️", title: "Poker")
                        fastCheckInSummaryCard(.slots, emoji: "🎰", title: "Slots")
                        fastCheckInSummaryCard(.table, emoji: "🎲", title: "Table Game")
                    }
                    .padding()
                }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    L10nText("Fast Check-In")
                        .font(.headline)
                        .foregroundColor(.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel(Text(L10n.tr("Done", language: settingsStore.appLanguage)))
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    @ViewBuilder
    private func fastCheckInSummaryCard(_ category: SessionGameCategory, emoji: String, title: String) -> some View {
        let plan = FastCheckInHelper.makePlan(category: category, store: store, settingsStore: settingsStore)
        let ready = FastCheckInHelper.canFastCheckIn(category: category, store: store, settingsStore: settingsStore)

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(emoji).font(.title2)
                L10nText(title)
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer(minLength: 8)
                Text(FastCheckInHelper.fastCheckInStatusLabel(category: category, store: store, settingsStore: settingsStore, language: settingsStore.appLanguage))
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(ready ? Color.green.opacity(0.35) : Color.orange.opacity(0.35))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }

            Group {
                summaryRow(L10n.tr("Casino", language: settingsStore.appLanguage), plan.casinoValue.isEmpty ? "—" : plan.casinoValue)
                summaryRow(L10n.tr("Game", language: settingsStore.appLanguage), plan.gameName.isEmpty ? "—" : plan.gameName)
                summaryRow(
                    L10n.tr("Tier points", language: settingsStore.appLanguage),
                    plan.startingTier.formatted(.number.grouping(.automatic))
                )
                summaryRow(
                    L10n.tr("Initial buy-in", language: settingsStore.appLanguage),
                    "\(settingsStore.currencySymbol)\(plan.initialBuyIn.formatted(.number.grouping(.automatic)))"
                )
                if let prog = plan.rewardsProgramName?.trimmingCharacters(in: .whitespacesAndNewlines), !prog.isEmpty {
                    summaryRow(L10n.tr("Rewards program", language: settingsStore.appLanguage), prog)
                }
                if category == .slots, let t = plan.template, let notes = t.slotNotes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                    summaryRow(L10n.tr("Slot notes", language: settingsStore.appLanguage), notes)
                }
            }
            .font(.subheadline)
            .foregroundColor(.white.opacity(0.92))

            Button {
                onRequestOpenCheckIn(category)
                dismiss()
            } label: {
                HStack {
                    Image(systemName: "square.and.pencil")
                    L10nText("Edit in Check-In")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.18))
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.12))
        }
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundColor(.white.opacity(0.65))
                .frame(width: 120, alignment: .leading)
            Text(value)
                .foregroundColor(.white.opacity(0.95))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Three-zone fast check-in control (table / slots / poker) for the home screen.
struct FastCheckInBar: View {
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @Binding var showSettingsSheet: Bool

    @State private var showActiveSessionAlert = false
    @State private var pendingFastCategory: SessionGameCategory?
    @State private var showTierTrackingWarning = false
    @State private var pendingTierWarningPlan: FastCheckInPlan?

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                HStack {
                    Label("", systemImage: "plus.circle.fill")
                    Spacer(minLength: 0)
                    Button {
                        showSettingsSheet = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.body.weight(.semibold))
                            .foregroundColor(.white.opacity(0.95))
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(L10n.tr("Fast check-in settings", language: settingsStore.appLanguage)))
                }
                L10nText("Fast Check-In")
                    .font(.headline.bold())
                    .foregroundColor(.white.opacity(0.95))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .multilineTextAlignment(.center)
                    .allowsHitTesting(false)
            }
            HStack(spacing: 0) {
                fastZone(.poker, emoji: "♠️", title: "Poker")
                divider
                fastZone(.slots, emoji: "🎰", title: "Slots")
                divider
                fastZone(.table, emoji: "🎲", title: "Table Game")
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .background {
            GameCategoryBubbleBackground(cornerRadius: 12)
                .environmentObject(settingsStore)
        }
        .alert("Active Session", isPresented: $showActiveSessionAlert) {
            Button("Resume Existing", role: .cancel) {
                pendingFastCategory = nil
            }
            Button("End & Start New", role: .destructive) {
                let cat = pendingFastCategory
                pendingFastCategory = nil
                store.discardLiveSession()
                if let cat {
                    startFastCheckInOrWarn(for: cat)
                }
            }
        } message: {
            L10nText("You have a live session. Resume it or end it to start a new one?")
        }
        .alert(
            Text(L10n.tr("Tier points", language: settingsStore.appLanguage)),
            isPresented: $showTierTrackingWarning
        ) {
            Button("Cancel", role: .cancel) { pendingTierWarningPlan = nil }
            Button("Start anyway") {
                if let plan = pendingTierWarningPlan {
                    pendingTierWarningPlan = nil
                    FastCheckInHelper.performFastCheckIn(plan: plan, store: store, settingsStore: settingsStore)
                }
            }
        } message: {
            Text(L10n.tr("Starting sessions without a Tier rating will make it difficult to track Tier levels and points.", language: settingsStore.appLanguage))
        }
    }

    private func startFastCheckInOrWarn(for category: SessionGameCategory) {
        guard FastCheckInHelper.canFastCheckIn(category: category, store: store, settingsStore: settingsStore) else { return }
        let plan = FastCheckInHelper.makePlan(category: category, store: store, settingsStore: settingsStore)
        if plan.needsTierTrackingWarning {
            pendingTierWarningPlan = plan
            showTierTrackingWarning = true
        } else {
            FastCheckInHelper.performFastCheckIn(plan: plan, store: store, settingsStore: settingsStore)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.35))
            .frame(width: 1, height: 26)
    }

    @ViewBuilder
    private func fastZone(_ category: SessionGameCategory, emoji: String, title: String) -> some View {
        let canFastStart = FastCheckInHelper.canFastCheckIn(category: category, store: store, settingsStore: settingsStore)
        Button {
            guard canFastStart else { return }
            if store.liveSession != nil {
                pendingFastCategory = category
                showActiveSessionAlert = true
            } else {
                startFastCheckInOrWarn(for: category)
            }
        } label: {
            HStack(spacing: 4) {
                Text(emoji)
                    .font(.system(size: 20))
                L10nText(title)
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .opacity(canFastStart ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!canFastStart)
    }
}
