import SwiftUI

/// Shared fast check-in logic (used from the home screen).
enum FastCheckInHelper {
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

    static func performFastCheckIn(category: SessionGameCategory, store: SessionStore, settingsStore: SettingsStore) {
        let template = store.mostRecentSession(forGameCategory: category)

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
            startingTier = t.startingTierPoints > 0 ? t.startingTierPoints : 1
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
            startingTier = 1
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

        store.startSession(
            game: gameName,
            casino: casinoValue,
            startingTier: startingTier,
            initialBuyIn: initialBuyIn,
            rewardsProgramName: rewardsProgramName,
            casinoLatitude: lat,
            casinoLongitude: lon
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
                selectedGame: gameName,
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
                    selectedGame: gameName,
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
                    selectedGame: gameName,
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
                    selectedGame: gameName,
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
}

/// Three-zone fast check-in control (table / slots / poker) for the home screen.
struct FastCheckInBar: View {
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @State private var showActiveSessionAlert = false
    @State private var pendingFastCategory: SessionGameCategory?

    var body: some View {
        VStack(spacing: 4) {
            L10nText("Fast Check-In")
                .font(.subheadline.bold())
                .foregroundColor(.white.opacity(0.95))
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
                    FastCheckInHelper.performFastCheckIn(category: cat, store: store, settingsStore: settingsStore)
                }
            }
        } message: {
            L10nText("You have a live session. Resume it or end it to start a new one?")
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.35))
            .frame(width: 1, height: 26)
    }

    @ViewBuilder
    private func fastZone(_ category: SessionGameCategory, emoji: String, title: String) -> some View {
        Button {
            if store.liveSession != nil {
                pendingFastCategory = category
                showActiveSessionAlert = true
            } else {
                FastCheckInHelper.performFastCheckIn(category: category, store: store, settingsStore: settingsStore)
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
        }
        .buttonStyle(.plain)
    }
}
