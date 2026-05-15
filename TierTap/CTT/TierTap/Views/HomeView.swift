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

    /// Logo with black pixels made transparent so the gradient shows through.
    private var logoImage: Image {
        if let processed = TransparentLogoCache.image {
            return Image(uiImage: processed)
        }
        return Image("LogoSplash")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                VStack(spacing: 24) {
                    logoImage
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 240)
                        .padding(.horizontal, 24)
                        .padding(.top, 8)

                    if let live = store.liveSession {
                        LiveNowCard(session: live)
                            .onTapGesture { showLive = true }
                            .padding(.horizontal)
                    }

                    Spacer()

                    VStack(spacing: 12) {
                        if store.liveSession == nil {
                            TapLevelCard(tapLevel: TapLevel.compute(from: store.sessions))
                                .environmentObject(settingsStore)
                                .padding(.horizontal)
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
                                Button { showBankroll = true } label: {
                                    LocalizedLabel(title: "Bankroll", systemImage: "dollarsign.circle.fill")
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 20)
                                        .background(Color(.systemGray6).opacity(0.25))
                                        .foregroundColor(.white)
                                        .cornerRadius(16)
                                        .font(.title3.bold())
                                }
                                Button { showWallet = true } label: {
                                    LocalizedLabel(title: "Wallet", systemImage: "wallet.pass.fill")
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 20)
                                        .background(Color(.systemGray6).opacity(0.25))
                                        .foregroundColor(.white)
                                        .cornerRadius(16)
                                        .font(.title3.bold())
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
                                    showUpdateStackSheet = true
                                } label: {
                                    LocalizedChipStackLabel(title: "Stack")
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
                                Button { showBankroll = true } label: {
                                    LocalizedLabel(title: "Bankroll", systemImage: "dollarsign.circle.fill")
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 20)
                                        .background(Color(.systemGray6).opacity(0.25))
                                        .foregroundColor(.white)
                                        .cornerRadius(16)
                                        .font(.title3.bold())
                                }
                                Button { showWallet = true } label: {
                                    LocalizedLabel(title: "Wallet", systemImage: "wallet.pass.fill")
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 20)
                                        .background(Color(.systemGray6).opacity(0.25))
                                        .foregroundColor(.white)
                                        .cornerRadius(16)
                                        .font(.title3.bold())
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
                    .padding(.horizontal).padding(.bottom, 44)
                }
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
            if let live = store.liveSession {
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
    #if os(iOS)
    @State private var liveSessionShareRef: PostCloseoutSessionRef?
    @State private var showSessionPhotos = false
    #endif
    let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// Use freshest live session from store so watch-originated updates appear immediately.
    private var currentSession: Session {
        store.liveSession ?? session
    }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                    L10nText("LIVE NOW").font(.caption.bold()).foregroundColor(.red)
                }
                Text(currentSession.casino).font(.subheadline.weight(.semibold)).foregroundColor(.white)
                Text(currentSession.game).font(.caption).foregroundColor(.gray)
                Text("Starting tier \(currentSession.startingTierPoints.formatted(.number.grouping(.automatic)))")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.85))
                if let prog = currentSession.rewardsProgramName?.trimmingCharacters(in: .whitespacesAndNewlines), !prog.isEmpty {
                    Text(prog)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(2)
                }
                Text("Total buy-in \(settingsStore.currencySymbol)\(currentSession.totalBuyIn.formatted(.number.grouping(.automatic)))")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.75))
                Text("Total free play \(settingsStore.currencySymbol)\(currentSession.totalFreePlay.formatted(.number.grouping(.automatic)))")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.75))
                if let stack = currentSession.liveTrackedStackAmount {
                    Text("Stack: \(settingsStore.currencySymbol)\(stack.formatted(.number.grouping(.automatic)))")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.75))
                }
                if currentSession.totalComp > 0 {
                    Text("Total comps \(settingsStore.currencySymbol)\(currentSession.totalComp.formatted(.number.grouping(.automatic)))")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.75))
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Text(Session.durationString(elapsed))
                    .font(.system(
                        size: UIFont.preferredFont(forTextStyle: .caption1).pointSize * 2,
                        design: .monospaced
                    ))
                    .foregroundColor(.green)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    VStack
                    {
                        HStack
                        {
                            Button { showPrivateNotes = true } label: {
                                Image(systemName: "note.text")
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(.green)
                                    .frame(width: 32, height: 28)
                                    .background(Color(.systemGray6).opacity(0.3))
                                    .cornerRadius(8)
                            }
                            .accessibilityLabel("Private notes")
                            Button { showStrategyOdds = true } label: {
                                Image(systemName: "info.circle")
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(.green)
                                    .frame(width: 32, height: 28)
                                    .background(Color(.systemGray6).opacity(0.3))
                                    .cornerRadius(8)
                            }
                        }

                        #if os(iOS)
                        Button {
                            liveSessionShareRef = PostCloseoutSessionRef(id: currentSession.id)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.caption.weight(.medium))
                                L10nText("Share")
                                    .font(.caption.weight(.medium))
                            }
                            .foregroundColor(.green)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(.systemGray6).opacity(0.3))
                            .cornerRadius(8)
                        }
                        .accessibilityLabel("Share session")

                        SessionPhotosEntryButton(compact: true) {
                            showSessionPhotos = true
                        }
                        #endif
                        
                        
                    }

                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.2))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.red.opacity(0.4), lineWidth: 1))
        .onReceive(ticker) { _ in elapsed = currentSession.duration }
        .onAppear { elapsed = currentSession.duration }
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
