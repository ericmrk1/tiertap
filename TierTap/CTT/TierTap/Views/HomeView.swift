import SwiftUI
import UIKit

private let kTapLevelLastKey = "ctt_tap_level_last"
private func tapLevelLastSaved() -> Int {
    (UserDefaults(suiteName: "group.com.app.tiertap") ?? .standard).object(forKey: kTapLevelLastKey) as? Int ?? 0
}
private func tapLevelSaveLast(_ level: Int) {
    (UserDefaults(suiteName: "group.com.app.tiertap") ?? .standard).set(level, forKey: kTapLevelLastKey)
}

struct HomeView: View {
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @EnvironmentObject var authStore: AuthStore
    @EnvironmentObject var rewardWalletStore: RewardWalletStore
    @State private var showCheckIn = false
    /// Pre-selects Table / Slots / Poker when opening Check In from fast check-in settings.
    @State private var checkInPresetGameCategory: SessionGameCategory?
    /// When true, Check In is configuring a saved fast check-in (no live session start).
    @State private var checkInSaveFastConfigurationMode = false
    @State private var showFastCheckInSettings = false
    @State private var pendingOpenCheckInFromFastSettings: SessionGameCategory?
    @State private var reopenFastCheckInSettingsAfterCheckInDismiss = false
    @State private var showLive = false
    @State private var showBuyInSheet = false
    @State private var showFreePlaySheet = false
    @State private var showUpdateStackSheet = false
    @State private var showCompSheet = false
    @State private var showAddPast = false
    @State private var showHistory = false
    @State private var showBankroll = false
    @State private var showWallet = false
    @State private var showSubscriptionPaywall = false
    @State private var showSessionReminderSettings = false
    @State private var showLevelUpCelebration = false
    @State private var showMissingInfoAlert = false
    @State private var levelUpReached: TapLevel?
    /// In-memory last computed level; popup only when level increases from this (not on first load).
    @State private var lastComputedLevel: Int?

    /// Quick-add buy-in denominations for the live buy-in sheet.
    private var quickBuyIns: [Int] {
        [50, 100, 200, 500, 1_000, 5_000, 10_000, 20_000, 50_000, 100_000]
    }

    private var hasProAccess: Bool {
        subscriptionStore.isPro || settingsStore.isSubscriptionOverrideActive
    }

    private var isSlotsLiveSession: Bool {
        store.liveSession?.isSlotsSession == true
    }

    /// Required fields that must be set before fast close-out.
    private var missingInfoFields: [String] {
        guard let live = store.liveSession else { return [] }
        var missing: [String] = []
        if live.game.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { missing.append("Game") }
        if live.casino.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { missing.append("Casino / Location") }
        if live.totalBuyIn == 0 && live.totalFreePlay == 0 {
            missing.append("Buy-in or free play")
        }
        return missing
    }

    private var hasMissingInfo: Bool { !missingInfoFields.isEmpty }

    private func performFastCloseOut() {
        if hasMissingInfo {
            showMissingInfoAlert = true
            return
        }
        if let live = store.liveSession {
            settingsStore.recordLastPlayedGameChoices(from: live)
        }
        store.fastCloseSessionWithDefaultsUnverified()
    }

    @ViewBuilder
    private func homeActionsStack(tapLevelSpacing: CGFloat) -> some View {
        VStack(spacing: tapLevelSpacing) {
            if store.liveSession == nil {
                TapLevelCard(tapLevel: TapLevel.compute(from: store.sessions))
                    .environmentObject(settingsStore)
            }
            if store.liveSession != nil {
                HStack(spacing: 12) {
                    Button { showAddPast = true } label: {
                        LocalizedLabel(title: "Add Past Session", systemImage: "clock.arrow.circlepath")
                            .frame(maxWidth: .infinity).padding()
                            .background(Color(.systemGray6).opacity(0.25))
                            .foregroundColor(.white).cornerRadius(14).font(.subheadline)
                    }
                    Button { showHistory = true } label: {
                        LocalizedLabel(title: "History", systemImage: "list.bullet.rectangle")
                            .frame(maxWidth: .infinity).padding()
                            .background(Color(.systemGray6).opacity(0.25))
                            .foregroundColor(.white).cornerRadius(14).font(.subheadline)
                    }
                }
                HStack(spacing: 12) {
                    homeSecondaryActionButton(title: "Bankroll", systemImage: "dollarsign.circle.fill") {
                        showBankroll = true
                    }
                    homeSecondaryActionButton(title: "Wallet", systemImage: "wallet.pass.fill") {
                        showWallet = true
                    }
                }
                Button { showLive = true } label: {
                    LocalizedLabel(title: "Finish Live Session", systemImage: "play.circle.fill")
                        .frame(maxWidth: .infinity).padding()
                        .font(.headline)
                        .foregroundColor(.white)
                        .background(GameCategoryBubbleBackground(cornerRadius: 14))
                }
                HStack(spacing: 10) {
                    Button {
                        showCompSheet = true
                    } label: {
                        LocalizedLabel(title: "Comp", systemImage: "gift.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .padding(.horizontal, 4)
                            .background(Color(.systemGray6).opacity(0.25))
                            .foregroundColor(.green)
                            .cornerRadius(16)
                            .font(.body.weight(.semibold))
                            .minimumScaleFactor(0.75)
                            .lineLimit(1)
                    }
                    Button {
                        if isSlotsLiveSession {
                            performFastCloseOut()
                        } else {
                            showUpdateStackSheet = true
                        }
                    } label: {
                        Group {
                            if isSlotsLiveSession {
                                LocalizedFastCloseOutLabel()
                            } else {
                                LocalizedChipStackLabel(title: "Stack")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .padding(.horizontal, 4)
                        .background(Color(.systemGray6).opacity(0.25))
                        .foregroundColor(.green)
                        .cornerRadius(16)
                        .font(.body.weight(.semibold))
                        .minimumScaleFactor(0.75)
                        .lineLimit(isSlotsLiveSession ? 2 : 1)
                    }
                    Button {
                        showBuyInSheet = true
                    } label: {
                        LocalizedLabel(title: "Buy-In", systemImage: "plus.circle")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .padding(.horizontal, 4)
                            .background(Color(.systemGray6).opacity(0.25))
                            .foregroundColor(.green)
                            .cornerRadius(16)
                            .font(.body.weight(.semibold))
                            .minimumScaleFactor(0.75)
                            .lineLimit(1)
                    }
                }
            } else {
                HStack(spacing: 12) {
                    homeSecondaryActionButton(title: "Bankroll", systemImage: "dollarsign.circle.fill") {
                        showBankroll = true
                    }
                    homeSecondaryActionButton(title: "Wallet", systemImage: "wallet.pass.fill") {
                        showWallet = true
                    }
                }
            }
            if store.liveSession == nil {
                HStack(spacing: 12) {
                    Button { showAddPast = true } label: {
                        LocalizedLabel(title: "Add Past Session", systemImage: "clock.arrow.circlepath")
                            .frame(maxWidth: .infinity).padding()
                            .background(Color(.systemGray6).opacity(0.25))
                            .foregroundColor(.white).cornerRadius(14).font(.subheadline)
                    }
                    Button { showHistory = true } label: {
                        LocalizedLabel(title: "History", systemImage: "list.bullet.rectangle")
                            .frame(maxWidth: .infinity).padding()
                            .background(Color(.systemGray6).opacity(0.25))
                            .foregroundColor(.white).cornerRadius(14).font(.subheadline)
                    }
                }
            }
            if store.liveSession == nil {
                Button {
                    checkInSaveFastConfigurationMode = false
                    checkInPresetGameCategory = nil
                    showCheckIn = true
                } label: {
                    LocalizedLabel(title: "Check In", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .padding(.horizontal)
                        .font(.title2.bold())
                        .foregroundColor(.white)
                        .background(GameCategoryBubbleBackground(cornerRadius: 16))
                }
                FastCheckInBar(showSettingsSheet: $showFastCheckInSettings)
                    .environmentObject(store)
                    .environmentObject(settingsStore)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 44)
    }

    private func homeSecondaryActionButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            LocalizedLabel(title: title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemGray6).opacity(0.25))
                .foregroundColor(.white)
                .cornerRadius(14)
                .font(.subheadline)
        }
    }

    /// When the user has session history, keep Tap Level under the hero so Pro-height screens don't clip the metrics header.
    private var stacksTapLevelUnderHero: Bool {
        store.liveSession == nil && !store.sessions.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                VStack(spacing: store.liveSession != nil ? 16 : (stacksTapLevelUnderHero ? 12 : 24)) {
                    if store.liveSession == nil {
                        HomeHeroMetricsSection(
                            sessions: store.sessions,
                            isLive: false,
                            onOpenHistory: { showHistory = true }
                        )
                    } else {
                        Color.clear
                            .frame(height: 96)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 24)
                            .padding(.top, 8)
                    }

                    if let live = store.liveSession {
                        LiveNowCard(session: live)
                            .onTapGesture { showLive = true }
                            .padding(.horizontal)
                    }

                    if stacksTapLevelUnderHero {
                        homeActionsStack(tapLevelSpacing: 8)
                    } else {
                        Spacer(minLength: 0)

                        homeActionsStack(tapLevelSpacing: 12)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 14) {
                        Button {
                            showSessionReminderSettings = true
                        } label: {
                            Image(systemName: settingsStore.sessionRemindersEnabled ? "bell.fill" : "bell")
                                .font(.body.weight(.medium))
                                .foregroundColor(.white)
                        }
                        .accessibilityLabel("Play Reminders")

                        NavigationLink {
                            UserGuideView()
                                .environmentObject(settingsStore)
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.body.weight(.medium))
                                .foregroundColor(.white)
                        }
                        .accessibilityLabel("User guide")

                        NavigationLink {
                            HistoryPhotoFeedView()
                                .environmentObject(store)
                                .environmentObject(settingsStore)
                                .environmentObject(rewardWalletStore)
                                .environmentObject(subscriptionStore)
                                .environmentObject(authStore)
                        } label: {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.body.weight(.medium))
                                .foregroundColor(.white)
                        }
                        .accessibilityLabel("Photo Feed")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if hasProAccess {
                        Button {
                            showSubscriptionPaywall = true
                        } label: {
                            Text("PRO")
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                        }
                        .accessibilityLabel("TierTap Pro subscription")
                    } else {
                        Button {
                            NotificationCenter.default.post(name: NSNotification.Name("ShowAccountSheet"), object: nil)
                        } label: {
                            Image(systemName: authStore.isSignedIn ? "person.crop.circle.fill" : "person.crop.circle")
                                .font(.body.weight(.medium))
                                .foregroundColor(.white)
                        }
                        .accessibilityLabel("TierTap Account")
                    }
                }
            }
            .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .overlay {
                if showLevelUpCelebration, let tap = levelUpReached {
                    TapLevelLevelUpCelebrationView(tapLevel: tap) {
                        showLevelUpCelebration = false
                        levelUpReached = nil
                    }
                }
            }
            .onAppear {
                guard store.liveSession == nil else { return }
                let tap = TapLevel.compute(from: store.sessions)
                if let prev = lastComputedLevel {
                    if tap.level > prev {
                        tapLevelSaveLast(tap.level)
                        levelUpReached = tap
                        showLevelUpCelebration = true
                    }
                    lastComputedLevel = tap.level
                } else {
                    lastComputedLevel = tap.level
                }
            }
            .onChange(of: store.sessions) { _ in
                guard store.liveSession == nil else { return }
                let tap = TapLevel.compute(from: store.sessions)
                if let prev = lastComputedLevel {
                    if tap.level > prev {
                        tapLevelSaveLast(tap.level)
                        levelUpReached = tap
                        showLevelUpCelebration = true
                    }
                }
                lastComputedLevel = tap.level
            }
        }
        #if os(iOS)
        .adaptiveSheet(isPresented: $showFastCheckInSettings, onDismiss: {
            if let cat = pendingOpenCheckInFromFastSettings {
                pendingOpenCheckInFromFastSettings = nil
                checkInPresetGameCategory = cat
                checkInSaveFastConfigurationMode = true
                showCheckIn = true
            }
        }) {
            FastCheckInSettingsSheet(onRequestOpenCheckIn: { cat in
                pendingOpenCheckInFromFastSettings = cat
            })
            .environmentObject(store)
            .environmentObject(settingsStore)
        }
        #endif
        .adaptiveSheet(isPresented: $showCheckIn, onDismiss: {
            let reopen = reopenFastCheckInSettingsAfterCheckInDismiss
            reopenFastCheckInSettingsAfterCheckInDismiss = false
            checkInSaveFastConfigurationMode = false
            checkInPresetGameCategory = nil
            if reopen {
                showFastCheckInSettings = true
            }
        }) {
            CheckInView(
                initialGameCategory: checkInPresetGameCategory,
                saveFastCheckInOnly: checkInSaveFastConfigurationMode,
                onFastCheckInSaved: {
                    reopenFastCheckInSettingsAfterCheckInDismiss = true
                }
            )
                .environmentObject(store)
                .environmentObject(settingsStore)
                .environmentObject(rewardWalletStore)
                .environmentObject(authStore)
                .environmentObject(subscriptionStore)
        }
        .adaptiveSheet(isPresented: $showLive) {
            LiveSessionView()
                .environmentObject(store)
                .environmentObject(settingsStore)
                .environmentObject(subscriptionStore)
                .environmentObject(authStore)
                .environmentObject(rewardWalletStore)
        }
        .adaptiveSheet(isPresented: $showBuyInSheet) {
            BuyInQuickAddSheet(quickBuyIns: quickBuyIns, onAdd: { amount in
                store.addBuyIn(amount)
            }, onAddFreePlay: {
                showFreePlaySheet = true
            })
            .environmentObject(settingsStore)
        }
        .adaptiveSheet(isPresented: $showFreePlaySheet) {
            FreePlayQuickAddSheet(existingSessionFreePlayTotal: store.liveSession?.totalFreePlay ?? 0) { amount, playType, photoJPEG, photoContextTags, photoCustomLabels in
                store.addFreePlay(
                    amount: amount,
                    playType: playType,
                    photoJPEG: photoJPEG,
                    photoContextTags: photoContextTags,
                    photoCustomContextLabels: photoCustomLabels
                )
            }
            .environmentObject(settingsStore)
        }
        .adaptiveSheet(isPresented: $showUpdateStackSheet) {
            if let live = store.liveSession, !live.isSlotsSession {
                UpdateStackSheet(
                    sessionID: live.id,
                    game: live.game,
                    casino: live.casino,
                    stackBaseline: live.totalStackBaseline,
                    currentTrackedStack: live.liveTrackedStackAmount,
                    hoursPlayed: live.hoursPlayed,
                    onUpdate: { store.updateLiveTrackedStack($0) },
                    onAddFreePlay: { showFreePlaySheet = true }
                )
                .environmentObject(store)
                .environmentObject(settingsStore)
                .environmentObject(authStore)
                .environmentObject(subscriptionStore)
                .environment(\.appLanguage, settingsStore.appLanguage)
            }
        }
        .adaptiveSheet(isPresented: $showCompSheet) {
            CompQuickAddSheet(
                existingSessionCompTotal: store.liveSession?.totalComp ?? 0,
                existingSessionFreePlayTotal: store.liveSession?.totalFreePlay ?? 0,
                sessionGame: store.liveSession?.game ?? "",
                sessionCasino: store.liveSession?.casino ?? "",
                sessionCasinoLatitude: store.liveSession?.casinoLatitude,
                sessionCasinoLongitude: store.liveSession?.casinoLongitude
            ) { kind, amount, details, foodKind, otherDesc, photoJPEG, asFreePlay in
                store.addComp(
                    amount: amount,
                    kind: kind,
                    details: details,
                    foodBeverageKind: foodKind,
                    foodBeverageOtherDescription: otherDesc,
                    photoJPEG: photoJPEG,
                    recordAsFreePlay: asFreePlay
                )
            }
            .environmentObject(settingsStore)
            .environmentObject(subscriptionStore)
            .environmentObject(authStore)
        }
        .adaptiveSheet(isPresented: $showAddPast) {
            AddPastSessionView()
                .environmentObject(store)
                .environmentObject(settingsStore)
                .environmentObject(rewardWalletStore)
                .environmentObject(authStore)
                .environmentObject(subscriptionStore)
        }
        .adaptiveSheet(isPresented: $showHistory) {
            HistoryView()
                .environmentObject(store)
                .environmentObject(settingsStore)
                .environmentObject(authStore)
                .environmentObject(subscriptionStore)
        }
        .adaptiveSheet(isPresented: $showBankroll) { BankrollView().environmentObject(store).environmentObject(settingsStore) }
        .adaptiveSheet(isPresented: $showWallet) {
            TierTapWalletView()
                .environmentObject(settingsStore)
                .environmentObject(rewardWalletStore)
        }
        .adaptiveSheet(isPresented: $showSubscriptionPaywall) {
            TierTapPaywallView()
                .environmentObject(subscriptionStore)
                .environmentObject(settingsStore)
                .environmentObject(authStore)
        }
        .adaptiveSheet(isPresented: $showSessionReminderSettings) {
            SessionReminderSettingsSheet()
                .environmentObject(settingsStore)
                .environmentObject(store)
        }
        .alert("Missing Information", isPresented: $showMissingInfoAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please complete the following before closing out: \(missingInfoFields.joined(separator: ", ")). You can add buy-ins here, but game and location must be set when you check in.")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenCheckInFromDeepLink"))) { _ in
            showCheckIn = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenLiveFromDeepLink"))) { _ in
            if store.liveSession != nil {
                showLive = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenHistoryFromDeepLink"))) { _ in
            showHistory = true
        }
    }
}

private struct LiveSessionMetricSnapshot: Equatable {
    var tier: Int
    var buyIn: Int
    var freePlay: Int
    var comps: Int
    var stack: Int?

    init(session: Session) {
        tier = session.startingTierPoints
        buyIn = session.totalBuyIn
        freePlay = session.totalFreePlay
        comps = session.totalComp
        stack = session.liveTrackedStackAmount
    }
}

/// Splash logo with black pixels made transparent so the gradient shows through.
private enum HomeBrandLogo {
    static var image: Image {
        if let processed = TransparentLogoCache.image {
            return Image(uiImage: processed)
        }
        return Image("LogoSplash")
    }
}

/// Home hero: logo dissolves into closing-metrics rings when sessions exist and nothing is live.
private struct HomeHeroMetricsSection: View {
    let sessions: [Session]
    let isLive: Bool
    var onOpenHistory: () -> Void = {}

    @State private var showClosingMetrics = false
    @State private var isSectionExpanded = true
    @State private var dissolveTask: Task<Void, Never>?

    private var hasSessions: Bool { !sessions.isEmpty }
    private var shouldShowMetrics: Bool { hasSessions && !isLive }

    /// Pro-height phones have less vertical room below the nav bar than Max models.
    private var usesCompactHomeHeight: Bool {
        UIScreen.main.bounds.height < 920
    }

    private var heroTopPadding: CGFloat {
        if shouldShowMetrics && showClosingMetrics {
            return usesCompactHomeHeight ? 36 : 28
        }
        return usesCompactHomeHeight ? 16 : 24
    }

    var body: some View {
        Group {
            if shouldShowMetrics && showClosingMetrics {
                collapsibleMetricsSection
            } else {
                logoView
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.horizontal, 24)
        .padding(.top, heroTopPadding)
        .padding(.bottom, shouldShowMetrics && showClosingMetrics ? 4 : 0)
        .animation(.easeInOut(duration: 0.9), value: showClosingMetrics)
        .animation(.easeInOut(duration: 0.25), value: isSectionExpanded)
        .onAppear { resetDissolveSchedule() }
        .onChange(of: isLive) { live in
            if live {
                cancelDissolveSchedule()
                showClosingMetrics = false
            } else {
                resetDissolveSchedule()
            }
        }
        .onChange(of: sessions) { _ in
            if !hasSessions {
                cancelDissolveSchedule()
                showClosingMetrics = false
            } else if !isLive && !showClosingMetrics {
                resetDissolveSchedule()
            }
        }
    }

    private var logoView: some View {
        HomeBrandLogo.image
            .resizable()
            .scaledToFit()
            .frame(maxHeight: shouldShowMetrics && showClosingMetrics ? 0 : (usesCompactHomeHeight ? 200 : 240))
            .opacity(shouldShowMetrics && showClosingMetrics ? 0 : 1)
            .scaleEffect(shouldShowMetrics && showClosingMetrics ? 0.86 : 1)
            .blur(radius: shouldShowMetrics && showClosingMetrics ? 8 : 0)
    }

    private var collapsibleMetricsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isSectionExpanded.toggle()
                }
            } label: {
                HStack {
                    Label("TierTap Sessions", systemImage: "chart.pie")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: isSectionExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.75))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("TierTap Sessions")
            .accessibilityValue(isSectionExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint(isSectionExpanded ? "Collapse section" : "Expand section")

            if isSectionExpanded {
                SessionClosingMetricsRingsView(
                    sessions: sessions,
                    isRevealed: showClosingMetrics,
                    onRingTap: onOpenHistory
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemGray6).opacity(0.18))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
    }

    private func resetDissolveSchedule() {
        cancelDissolveSchedule()
        guard shouldShowMetrics else {
            showClosingMetrics = false
            return
        }
        showClosingMetrics = false
        isSectionExpanded = true
        dissolveTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, shouldShowMetrics else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.9)) {
                    showClosingMetrics = true
                }
            }
        }
    }

    private func cancelDissolveSchedule() {
        dissolveTask?.cancel()
        dissolveTask = nil
    }
}

/// Main-screen Live Now summary: full-width game, tier + location, then 2×2 financial grid.
private struct LiveNowHomeSummaryLayout: View {
    let metrics: [LiveSessionSummaryMetric]
    let metricTrends: [String: LiveSessionMetricTrend]

    private static let twoColumnGrid = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    private func metric(_ id: String) -> LiveSessionSummaryMetric? {
        metrics.first { $0.id == id }
    }

    private func trend(for id: String) -> LiveSessionMetricTrend? {
        metricTrends[id]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let game = metric("game") {
                GeometryReader { proxy in
                    let textWidth = max(1, proxy.size.width - 20)
                    let charCount = max(1, CGFloat(game.value.count))
                    let fittedSize = min(34, max(16, textWidth / (charCount * 0.52)))
                    Text(game.value)
                        .font(.system(size: fittedSize, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.35)
                        .allowsTightening(true)
                        .frame(width: textWidth, alignment: .leading)
                }
                .frame(height: 36)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.08))
                .cornerRadius(8)
            }

            HStack(spacing: 8) {
                if let tier = metric("tier") {
                    LiveSessionSummaryCell(
                        title: tier.title,
                        value: tier.value,
                        metricId: tier.id,
                        compact: true,
                        trend: trend(for: "tier")
                    )
                }
                if let location = metric("location") {
                    LiveSessionSummaryCell(
                        title: location.title,
                        value: location.value,
                        metricId: location.id,
                        compact: true
                    )
                }
            }

            LazyVGrid(columns: Self.twoColumnGrid, spacing: 8) {
                if let buyIn = metric("buyIn") {
                    LiveSessionSummaryCell(
                        title: buyIn.title,
                        value: buyIn.value,
                        metricId: buyIn.id,
                        compact: true,
                        trend: trend(for: "buyIn")
                    )
                }
                if let freePlay = metric("freePlay") {
                    LiveSessionSummaryCell(
                        title: freePlay.title,
                        value: freePlay.value,
                        metricId: freePlay.id,
                        compact: true,
                        trend: trend(for: "freePlay")
                    )
                }
                if let comps = metric("comps") {
                    LiveSessionSummaryCell(
                        title: comps.title,
                        value: comps.value,
                        metricId: comps.id,
                        compact: true,
                        trend: trend(for: "comps")
                    )
                }
                if let stack = metric("stack") {
                    LiveSessionSummaryCell(
                        title: stack.title,
                        value: stack.value,
                        metricId: stack.id,
                        compact: true,
                        trend: trend(for: "stack")
                    )
                }
            }
        }
    }
}

private struct LiveNowBrandLogo: View {
    var body: some View {
        HomeBrandLogo.image
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 48.4, maxHeight: 30.8)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .accessibilityLabel("TierTap")
    }
}

private struct LiveNowIconActionButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    private var iconFont: Font {
        let base = UIFont.preferredFont(forTextStyle: .caption1).pointSize
        return .system(size: base * 1.55, weight: .semibold)
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(iconFont)
                .foregroundColor(.green)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct LiveNowCard: View {
    let session: Session
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var authStore: AuthStore
    @State private var elapsed: TimeInterval = 0
    @State private var showStrategyOdds = false
    @State private var showPrivateNotes = false
    @State private var metricTrendReference: LiveSessionMetricSnapshot?
    @State private var displayedMetricTrends: [String: LiveSessionMetricTrend] = [:]
    #if os(iOS)
    @State private var liveSessionShareRef: PostCloseoutSessionRef?
    @State private var showSessionPhotos = false
    #endif
    let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// Use freshest live session from store so watch-originated updates appear immediately.
    private var currentSession: Session {
        store.liveSession ?? session
    }

    private var summaryMetrics: [LiveSessionSummaryMetric] {
        LiveSessionSummaryMetricsBuilder.metrics(
            casino: currentSession.casino,
            game: currentSession.game,
            startingTierPoints: currentSession.startingTierPoints,
            totalBuyIn: currentSession.totalBuyIn,
            totalFreePlay: currentSession.totalFreePlay,
            totalComp: currentSession.totalComp,
            liveTrackedStackAmount: currentSession.liveTrackedStackAmount,
            currencySymbol: settingsStore.currencySymbol,
            isSlotsSession: currentSession.isSlotsSession
        )
    }

    private var currentMetricSnapshot: LiveSessionMetricSnapshot {
        LiveSessionMetricSnapshot(session: currentSession)
    }

    private func refreshMetricTrends(from prior: LiveSessionMetricSnapshot, to current: LiveSessionMetricSnapshot) {
        var trends = displayedMetricTrends
        if current.tier != prior.tier {
            trends["tier"] = LiveSessionMetricTrend.from(current: current.tier, prior: prior.tier)
        }
        if current.buyIn != prior.buyIn {
            trends["buyIn"] = LiveSessionMetricTrend.from(current: current.buyIn, prior: prior.buyIn)
        }
        if current.freePlay != prior.freePlay {
            trends["freePlay"] = LiveSessionMetricTrend.from(current: current.freePlay, prior: prior.freePlay)
        }
        if current.comps != prior.comps {
            trends["comps"] = LiveSessionMetricTrend.from(current: current.comps, prior: prior.comps)
        }
        if current.stack != prior.stack, let stackTrend = LiveSessionMetricTrend.fromStack(current: current.stack, prior: prior.stack) {
            trends["stack"] = stackTrend
        }
        displayedMetricTrends = trends
    }

    private func syncMetricTrendReference(with snapshot: LiveSessionMetricSnapshot) {
        if let prior = metricTrendReference, prior != snapshot {
            refreshMetricTrends(from: prior, to: snapshot)
        }
        metricTrendReference = snapshot
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                    L10nText("LIVE NOW").font(.caption.bold()).foregroundColor(.red)
                }
                Spacer(minLength: 8)
                Text(Session.durationString(elapsed))
                    .font(.system(
                        size: UIFont.preferredFont(forTextStyle: .caption1).pointSize * 1.55,
                        design: .monospaced
                    ))
                    .foregroundColor(.green)
            }

            LiveNowHomeSummaryLayout(metrics: summaryMetrics, metricTrends: displayedMetricTrends)

            HStack(spacing: 0) {
                LiveNowIconActionButton(systemImage: "note.text", accessibilityLabel: "Private notes") {
                    showPrivateNotes = true
                }
                LiveNowIconActionButton(systemImage: "info.circle", accessibilityLabel: "Strategy and odds") {
                    showStrategyOdds = true
                }
                LiveNowBrandLogo()
                #if os(iOS)
                LiveNowIconActionButton(systemImage: "square.and.arrow.up", accessibilityLabel: "Share session") {
                    liveSessionShareRef = PostCloseoutSessionRef(id: currentSession.id)
                }
                LiveNowIconActionButton(systemImage: "photo.on.rectangle.angled", accessibilityLabel: "Session photos") {
                    showSessionPhotos = true
                }
                #endif
            }
        }
        .padding(12)
        .background(Color(.systemGray6).opacity(0.2), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.red.opacity(0.4), lineWidth: 1)
        }
        .layoutPriority(1)
        .onReceive(ticker) { _ in elapsed = currentSession.duration }
        .onAppear {
            elapsed = currentSession.duration
            let snapshot = currentMetricSnapshot
            metricTrendReference = snapshot
            displayedMetricTrends = [:]
        }
        .onChange(of: currentMetricSnapshot) { snapshot in
            syncMetricTrendReference(with: snapshot)
        }
        .onChange(of: currentSession.id) { _ in
            let snapshot = currentMetricSnapshot
            metricTrendReference = snapshot
            displayedMetricTrends = [:]
        }
        .adaptiveSheet(isPresented: $showStrategyOdds) {
            StrategyOddsSheet(gameName: currentSession.game)
                .environmentObject(settingsStore)
        }
        .halfScreenSheet(isPresented: $showPrivateNotes) {
            PrivateNotesSheet(
                notes: Binding(
                    get: { store.liveSession?.privateNotes ?? "" },
                    set: { store.updateLiveSessionNotes($0) }
                ),
                onDismiss: { showPrivateNotes = false }
            )
            .environmentObject(settingsStore)
        }
        #if os(iOS)
        .sheet(item: $liveSessionShareRef) { ref in
            PostCloseoutShareFlowView(sessionId: ref.id)
                .environmentObject(store)
                .environmentObject(settingsStore)
                .environmentObject(authStore)
        }
        .adaptiveSheet(isPresented: $showSessionPhotos) {
            SessionPhotosSheet(sessionID: currentSession.id)
                .environmentObject(store)
                .environmentObject(settingsStore)
        }
        #endif
    }
}

struct TapLevelCard: View {
    let tapLevel: TapLevel
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @State private var showLevelsExplainer = false
    @State private var showShareOptions = false
    @State private var shareURLItem: ShareURLItem?
    @State private var sharePreviewItem: ShareableImageItem?
    @State private var pendingShareURL: URL?
    @State private var lastSharedURL: URL?
    @State private var shouldPresentShareAfterPreviewDismiss = false
    @State private var selectedPreset: LevelSharePreset = .performance
    @State private var customStats: Set<LevelShareOverlayStat> = [.sessionsThisMonth, .lifetimeWinLoss, .winRatePerHour, .bestSession]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 6) {
                    Text(tapLevel.sessionMilestoneEmoji)
                        .font(.system(size: 36))
                    Text(tapLevel.emoji)
                        .font(.system(size: 28))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tap Level \(tapLevel.level)")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(tapLevel.title)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                    Text("\(tapLevel.sessionCount) sessions")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.65))
                }
                Spacer()
                HStack(spacing: 8) {
                    Button {
                        showLevelsExplainer = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.title3)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .accessibilityLabel("Levels explained")
                    #if os(iOS)
                    Button {
                        showShareOptions = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title3)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .accessibilityLabel("Share level")
                    #endif
                }
            }
            if tapLevel.level < TapLevel.maxLevel {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.2))
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.green)
                            .frame(width: geo.size.width * tapLevel.progressToNext, height: 6)
                    }
                }
                .frame(height: 6)
            }
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.2))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.15), lineWidth: 1))
        .adaptiveSheet(isPresented: $showLevelsExplainer) {
            TapLevelLevelsExplainerSheet(tapLevel: tapLevel)
                .environmentObject(settingsStore)
        }
        #if os(iOS)
        .adaptiveSheet(isPresented: $showShareOptions) {
            shareOptionsSheet
        }
        .sheet(item: $sharePreviewItem, onDismiss: {
            guard shouldPresentShareAfterPreviewDismiss else { return }
            shouldPresentShareAfterPreviewDismiss = false
            guard let url = pendingShareURL else { return }
            lastSharedURL = url
            shareURLItem = ShareURLItem(url: url)
        }) { preview in
            NavigationStack {
                ZStack {
                    settingsStore.primaryGradient.ignoresSafeArea()
                    VStack(spacing: 14) {
                        Text("Share Preview")
                            .font(.headline)
                            .foregroundColor(.white)
                        Image(uiImage: preview.image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                        Button {
                            guard pendingShareURL != nil else { return }
                            shouldPresentShareAfterPreviewDismiss = true
                            sharePreviewItem = nil
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .foregroundColor(.black)
                                .cornerRadius(12)
                        }
                    }
                    .padding()
                }
                .localizedNavigationTitle("Share Level")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            shouldPresentShareAfterPreviewDismiss = false
                            if let url = pendingShareURL, lastSharedURL == nil {
                                try? FileManager.default.removeItem(at: url)
                            }
                            pendingShareURL = nil
                            sharePreviewItem = nil
                        }
                            .foregroundColor(.green)
                    }
                }
            }
        }
        .sheet(item: $shareURLItem) { shareItem in
            ShareSheet(items: [shareItem.url])
        }
        .onChange(of: shareURLItem) { newValue in
            if newValue == nil, let url = lastSharedURL {
                try? FileManager.default.removeItem(at: url)
                lastSharedURL = nil
                pendingShareURL = nil
            }
        }
        #endif
    }

    #if os(iOS)
    private var shareOptionsSheet: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Share Overlay")
                            .font(.headline)
                            .foregroundColor(.white)

                        ForEach(LevelSharePreset.allCases, id: \.self) { preset in
                            Button {
                                selectedPreset = preset
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(preset.displayName)
                                            .font(.subheadline.bold())
                                            .foregroundColor(.white)
                                        Text(preset.description)
                                            .font(.caption2)
                                            .foregroundColor(.white.opacity(0.75))
                                    }
                                    Spacer()
                                    Image(systemName: selectedPreset == preset ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedPreset == preset ? .green : .white.opacity(0.5))
                                }
                                .padding(10)
                                .background(Color(.systemGray6).opacity(0.18))
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                        }

                        if selectedPreset == .custom {
                            Text("Custom stats (up to 4)")
                                .font(.caption.bold())
                                .foregroundColor(.gray)
                                .padding(.top, 4)
                            ForEach(LevelShareOverlayStat.allCases, id: \.self) { stat in
                                let isOn = customStats.contains(stat)
                                Button {
                                    if isOn {
                                        customStats.remove(stat)
                                    } else if customStats.count < 4 {
                                        customStats.insert(stat)
                                    }
                                } label: {
                                    HStack {
                                        Text(stat.displayName)
                                            .font(.subheadline)
                                            .foregroundColor(.white)
                                        Spacer()
                                        Image(systemName: isOn ? "checkmark.square.fill" : "square")
                                            .foregroundColor(isOn ? .green : .white.opacity(0.6))
                                    }
                                    .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Button {
                            shareLevelAsImage()
                            showShareOptions = false
                        } label: {
                            Label("Preview Share Image", systemImage: "photo")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .foregroundColor(.black)
                                .cornerRadius(12)
                        }
                    }
                    .padding()
                }
            }
            .localizedNavigationTitle("Share Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showShareOptions = false }
                        .foregroundColor(.green)
                }
            }
        }
    }

    @MainActor
    private func shareLevelAsImage() {
        let metrics = resolvedShareMetrics()
        let card = TapLevelShareCard(
            tapLevel: tapLevel,
            gradient: settingsStore.primaryGradient,
            overlayMetrics: metrics
        )
        guard let image = renderTapLevelCardToImage(card) else { return }
        let df = DateFormatter()
        df.dateFormat = "yyyyMMddHHmmss"
        let name = "TierTapLevel\(tapLevel.level)_\(df.string(from: Date())).png"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        guard let data = image.pngData(), (try? data.write(to: url)) != nil else { return }
        pendingShareURL = url
        sharePreviewItem = ShareableImageItem(image: image)
    }

    @MainActor
    private func renderTapLevelCardToImage(_ view: TapLevelShareCard) -> UIImage? {
        let width = ShareImageExportQuality.wideCardWidthPoints
        let height: CGFloat = 440
        let wrapped = view
            .frame(width: width, height: height)
        if #available(iOS 16.0, *) {
            let renderer = ImageRenderer(content: wrapped)
            renderer.scale = ShareImageExportQuality.imageRendererScale
            renderer.proposedSize = ProposedViewSize(width: width, height: height)
            return renderer.uiImage
        } else {
            let controller = UIHostingController(rootView: wrapped)
            controller.view.bounds = CGRect(origin: .zero, size: CGSize(width: width, height: height))
            controller.view.backgroundColor = .clear
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
            return renderer.image { _ in
                controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
            }
        }
    }

    private func resolvedShareMetrics() -> [ShareOverlayMetric] {
        let chosen: [LevelShareOverlayStat]
        switch selectedPreset {
        case .performance:
            chosen = [.lifetimeWinLoss, .winRatePerHour, .bestSession, .winPercent]
        case .grind:
            chosen = [.sessionsThisMonth, .avgSessionHours, .totalTierPoints, .sessionCount]
        case .rewards:
            chosen = [.totalComps, .compsPerSession, .avgWinLossPerSession, .topGame]
        case .minimal:
            chosen = [.lifetimeWinLoss]
        case .custom:
            chosen = Array(customStats.prefix(4))
        }
        return chosen.compactMap { overlayMetric(for: $0) }
    }

    private func overlayMetric(for stat: LevelShareOverlayStat) -> ShareOverlayMetric? {
        let sessions = store.sessions
        let closedWithWL = sessions.compactMap { s -> Session? in
            s.winLoss == nil ? nil : s
        }
        switch stat {
        case .sessionCount:
            return ShareOverlayMetric(title: "Sessions", value: "\(sessions.count)")
        case .sessionsThisMonth:
            let calendar = Calendar.current
            let now = Date()
            let count = sessions.filter { calendar.isDate($0.startTime, equalTo: now, toGranularity: .month) && calendar.isDate($0.startTime, equalTo: now, toGranularity: .year) }.count
            return ShareOverlayMetric(title: "This Month", value: "\(count)")
        case .lifetimeWinLoss:
            let total = closedWithWL.compactMap(\.winLoss).reduce(0, +)
            let sign = total >= 0 ? "+" : "-"
            return ShareOverlayMetric(title: "Lifetime W/L", value: "\(sign)\(settingsStore.currencySymbol)\(abs(total).formatted(.number.grouping(.automatic)))")
        case .avgWinLossPerSession:
            guard !closedWithWL.isEmpty else { return nil }
            let avg = Double(closedWithWL.compactMap(\.winLoss).reduce(0, +)) / Double(closedWithWL.count)
            let rounded = Int(avg.rounded())
            let sign = rounded >= 0 ? "+" : "-"
            return ShareOverlayMetric(title: "Avg W/L", value: "\(sign)\(settingsStore.currencySymbol)\(abs(rounded).formatted(.number.grouping(.automatic)))")
        case .bestSession:
            guard let best = closedWithWL.compactMap(\.winLoss).max() else { return nil }
            return ShareOverlayMetric(title: "Best Session", value: "+\(settingsStore.currencySymbol)\(best.formatted(.number.grouping(.automatic)))")
        case .winRatePerHour:
            let totalWl = closedWithWL.compactMap(\.winLoss).reduce(0, +)
            let totalHours = closedWithWL.reduce(0.0) { $0 + $1.hoursPlayed }
            guard totalHours > 0 else { return nil }
            let rate = Int((Double(totalWl) / totalHours).rounded())
            let sign = rate >= 0 ? "+" : "-"
            return ShareOverlayMetric(title: "Win Rate", value: "\(sign)\(settingsStore.currencySymbol)\(abs(rate).formatted(.number.grouping(.automatic)))/hr")
        case .avgSessionHours:
            guard !sessions.isEmpty else { return nil }
            let avg = sessions.reduce(0.0) { $0 + $1.hoursPlayed } / Double(sessions.count)
            return ShareOverlayMetric(title: "Avg Session", value: String(format: "%.1f hrs", avg))
        case .winPercent:
            guard !closedWithWL.isEmpty else { return nil }
            let wins = closedWithWL.compactMap(\.winLoss).filter { $0 > 0 }.count
            let pct = Int((Double(wins) / Double(closedWithWL.count) * 100).rounded())
            return ShareOverlayMetric(title: "Win %", value: "\(pct)%")
        case .totalTierPoints:
            let total = sessions.compactMap(\.tierPointsEarned).reduce(0, +)
            return ShareOverlayMetric(title: "Tier Earned", value: "\(total.formatted(.number.grouping(.automatic)))")
        case .totalComps:
            let total = sessions.reduce(0) { $0 + $1.totalComp }
            return ShareOverlayMetric(title: "Total Comps", value: "\(settingsStore.currencySymbol)\(total.formatted(.number.grouping(.automatic)))")
        case .compsPerSession:
            guard !sessions.isEmpty else { return nil }
            let avg = Double(sessions.reduce(0) { $0 + $1.totalComp }) / Double(sessions.count)
            return ShareOverlayMetric(title: "Comps/Session", value: "\(settingsStore.currencySymbol)\(Int(avg.rounded()).formatted(.number.grouping(.automatic)))")
        case .topGame:
            let grouped = Dictionary(grouping: sessions.map(\.game).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { $0 }
            guard let top = grouped.max(by: { $0.value.count < $1.value.count }) else { return nil }
            return ShareOverlayMetric(title: "Top Game", value: top.key)
        }
    }
    #endif
}

private struct ShareURLItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
}

/// Full-screen level-up celebration: confetti, haptics, sound, and a pop-up card.
struct TapLevelLevelUpCelebrationView: View {
    let tapLevel: TapLevel
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            ConfettiCelebrationView()
            VStack(spacing: 20) {
                Text(tapLevel.sessionMilestoneEmoji)
                    .font(.system(size: 56))
                Text(tapLevel.emoji)
                    .font(.system(size: 44))
                Text("Tap Level \(tapLevel.level)!")
                    .font(.title.bold())
                    .foregroundColor(.white)
                Text(tapLevel.title)
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.9))
                Button {
                    onDismiss()
                } label: {
                    L10nText("Awesome!")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.green)
                        .cornerRadius(14)
                }
                .padding(.horizontal, 40)
                .padding(.top, 8)
            }
            .padding(32)
            .background(Color(.systemGray6).opacity(0.95))
            .cornerRadius(24)
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.green.opacity(0.6), lineWidth: 2))
            .padding(40)
        }
        .allowsHitTesting(true)
    }
}

/// Card view used when sharing Tap Level as an image (gradient, batch emoji, level, title, sessions, TierTap).
private struct TapLevelShareCard: View {
    let tapLevel: TapLevel
    let gradient: LinearGradient
    let overlayMetrics: [ShareOverlayMetric]

    var body: some View {
        ZStack {
            gradient.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tap Level Progress")
                            .font(.headline.weight(.bold))
                            .foregroundColor(.white)
                    }
                    Spacer(minLength: 0)
                    Text(Date.now.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                }
                Spacer()

                VStack(spacing: 14) {
                    HStack(spacing: 16) {
                        Text(tapLevel.sessionMilestoneEmoji)
                            .font(.system(size: 84))
                        Text(tapLevel.emoji)
                            .font(.system(size: 64))
                    }

                    Text("Tap Level \(tapLevel.level)")
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .foregroundColor(.white)

                    Text(tapLevel.title)
                        .font(.title2.weight(.semibold))
                        .foregroundColor(.white.opacity(0.95))

                    Text("\(tapLevel.sessionCount) sessions")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.86))
                        .padding(.bottom, 16)
                }
                .multilineTextAlignment(.center)

                if !overlayMetrics.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(Array(overlayMetrics.prefix(4).enumerated()), id: \.offset) { _, metric in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(metric.title)
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.72))
                                    .lineLimit(1)
                                Text(metric.value)
                                    .font(.caption.bold())
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.12))
                            .cornerRadius(8)
                        }
                    }
                }

                Spacer()

                HStack(alignment: .bottom) {
                    Text("")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                    Spacer(minLength: 0)
                    HStack(spacing: 8) {
                        Image("TierTapLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                        Text("TierTap")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.14))
                    .clipShape(Capsule())
                }
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct ShareOverlayMetric {
    let title: String
    let value: String
}

private enum LevelSharePreset: CaseIterable {
    case performance
    case grind
    case rewards
    case minimal
    case custom

    var displayName: String {
        switch self {
        case .performance: return "Performance"
        case .grind: return "Grind"
        case .rewards: return "Rewards"
        case .minimal: return "Minimal"
        case .custom: return "Custom"
        }
    }

    var description: String {
        switch self {
        case .performance: return "W/L, win rate, best session, win percentage."
        case .grind: return "Volume, cadence, and tier progress."
        case .rewards: return "Comps and game profile focus."
        case .minimal: return "Single hero metric only."
        case .custom: return "Pick up to four overlay stats."
        }
    }
}

private enum LevelShareOverlayStat: CaseIterable {
    case sessionCount
    case sessionsThisMonth
    case lifetimeWinLoss
    case avgWinLossPerSession
    case bestSession
    case winRatePerHour
    case avgSessionHours
    case winPercent
    case totalTierPoints
    case totalComps
    case compsPerSession
    case topGame

    var displayName: String {
        switch self {
        case .sessionCount: return "Session Count"
        case .sessionsThisMonth: return "Sessions This Month"
        case .lifetimeWinLoss: return "Lifetime W/L"
        case .avgWinLossPerSession: return "Avg W/L Per Session"
        case .bestSession: return "Best Session"
        case .winRatePerHour: return "Win Rate Per Hour"
        case .avgSessionHours: return "Average Session Hours"
        case .winPercent: return "Win %"
        case .totalTierPoints: return "Total Tier Points"
        case .totalComps: return "Total Comps"
        case .compsPerSession: return "Comps Per Session"
        case .topGame: return "Top Game"
        }
    }
}

struct TapLevelLevelsExplainerSheet: View {
    let tapLevel: TapLevel
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                List {
                    Section {
                        L10nText("Your level (1–1,000) is based on sessions logged, tier point gains, and sessions where you enter both rated and actual avg bet. Each level needs 50 more raw score. Session milestones are on a scale of 10,000.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                            .listRowBackground(Color.white.opacity(0.08))
                    }
                    Section(header: L10nText("Your progress").foregroundColor(.gray)) {
                        HStack(spacing: 8) {
                            Text(tapLevel.sessionMilestoneEmoji)
                                .font(.title)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(tapLevel.sessionCount) sessions logged")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Text("Current batch: \(tapLevel.sessionMilestoneLabel)")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                            Spacer()
                        }
                        .listRowBackground(Color.white.opacity(0.08))
                    }
                    Section(header: L10nText("Session milestones (scale of 10,000)").foregroundColor(.gray)) {
                        ForEach(Array(TapLevel.sessionMilestones.enumerated()), id: \.offset) { _, milestone in
                            let achieved = tapLevel.sessionCount >= milestone.sessions
                            HStack(alignment: .center, spacing: 12) {
                                Text(milestone.emoji)
                                    .font(.title2)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(milestone.label)
                                        .font(.subheadline.bold())
                                        .foregroundColor(.white)
                                    Text("\(milestone.sessions) sessions")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                }
                                Spacer()
                                if achieved {
                                    Image(systemName: "star.fill")
                                        .foregroundColor(.yellow)
                                        .font(.body)
                                }
                            }
                            .listRowBackground(achieved ? Color.white.opacity(0.12) : Color.white.opacity(0.08))
                            .padding(.vertical, 6)
                        }
                    }
                    Section(header: L10nText("Level bands (1–1,000)").foregroundColor(.gray)) {
                        ForEach(Array(TapLevel.levelBandsForExplainer.enumerated()), id: \.offset) { _, band in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text("Levels \(band.range.lowerBound)–\(band.range.upperBound)")
                                        .font(.subheadline.bold())
                                        .foregroundColor(.white)
                                    Text("· \(band.title)")
                                        .font(.subheadline)
                                        .foregroundColor(.green)
                                }
                                Text(band.description)
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            .listRowBackground(Color.white.opacity(0.08))
                            .padding(.vertical, 4)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .localizedNavigationTitle("Tap Levels")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.green)
                }
            }
        }
    }
}
