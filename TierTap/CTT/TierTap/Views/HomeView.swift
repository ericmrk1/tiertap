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
    @State private var showCheckIn = false
    @State private var showLive = false
    @State private var showBuyInSheet = false
    @State private var showCompSheet = false
    @State private var showAddPast = false
    @State private var showHistory = false
    @State private var showBankroll = false
    @State private var showSubscriptionPaywall = false
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
                            Button { showBankroll = true } label: {
                                LocalizedLabel(title: "Bankroll", systemImage: "dollarsign.circle.fill")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 20)
                                    .background(Color(.systemGray6).opacity(0.25))
                                    .foregroundColor(.white)
                                    .cornerRadius(16)
                                    .font(.title3.bold())
                            }
                            Button { showLive = true } label: {
                                LocalizedLabel(title: "Finish Live Session", systemImage: "play.circle.fill")
                                    .frame(maxWidth: .infinity).padding()
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .background(GameCategoryBubbleBackground(cornerRadius: 14))
                            }
                            HStack(spacing: 12) {
                                Button {
                                    showCompSheet = true
                                } label: {
                                    LocalizedLabel(title: "Add Comp", systemImage: "gift.fill")
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 18)
                                        .padding(.horizontal)
                                        .background(Color(.systemGray6).opacity(0.25))
                                        .foregroundColor(.green)
                                        .cornerRadius(16).font(.title3.bold())
                                }
                                Button {
                                    showBuyInSheet = true
                                } label: {
                                    LocalizedLabel(title: "Add Buy-In", systemImage: "plus.circle")
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 18)
                                        .padding(.horizontal)
                                        .background(Color(.systemGray6).opacity(0.25))
                                        .foregroundColor(.green)
                                        .cornerRadius(16).font(.title3.bold())
                                }
                            }
                        } else {
                            Button { showBankroll = true } label: {
                                LocalizedLabel(title: "Bankroll", systemImage: "dollarsign.circle.fill")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 20)
                                    .background(Color(.systemGray6).opacity(0.25))
                                    .foregroundColor(.white)
                                    .cornerRadius(16)
                                    .font(.title3.bold())
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
                            Button { showCheckIn = true } label: {
                                LocalizedLabel(title: "Check In", systemImage: "plus.circle.fill")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 20)
                                    .padding(.horizontal)
                                    .font(.title2.bold())
                                    .foregroundColor(.white)
                                    .background(GameCategoryBubbleBackground(cornerRadius: 16))
                            }
                            FastCheckInBar()
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
                    NavigationLink {
                        UserGuideView()
                            .environmentObject(settingsStore)
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.body.weight(.medium))
                            .foregroundColor(.white)
                    }
                    .accessibilityLabel("User guide")
                }
                if hasProAccess {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showSubscriptionPaywall = true
                        } label: {
                            Text("PRO")
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                        }
                        .accessibilityLabel("TierTap Pro subscription")
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
        .adaptiveSheet(isPresented: $showCheckIn) {
            CheckInView()
                .environmentObject(store)
                .environmentObject(settingsStore)
                .environmentObject(authStore)
                .environmentObject(subscriptionStore)
        }
        .adaptiveSheet(isPresented: $showLive) {
            LiveSessionView()
                .environmentObject(store)
                .environmentObject(settingsStore)
                .environmentObject(subscriptionStore)
                .environmentObject(authStore)
        }
        .adaptiveSheet(isPresented: $showBuyInSheet) {
            BuyInQuickAddSheet(quickBuyIns: quickBuyIns) { amount in
                store.addBuyIn(amount)
            }
            .environmentObject(settingsStore)
        }
        .adaptiveSheet(isPresented: $showCompSheet) {
            CompQuickAddSheet(
                existingSessionCompTotal: store.liveSession?.totalComp ?? 0,
                sessionGame: store.liveSession?.game ?? "",
                sessionCasino: store.liveSession?.casino ?? "",
                sessionCasinoLatitude: store.liveSession?.casinoLatitude,
                sessionCasinoLongitude: store.liveSession?.casinoLongitude
            ) { kind, amount, details, foodKind, otherDesc, photoJPEG in
                store.addComp(amount: amount, kind: kind, details: details, foodBeverageKind: foodKind, foodBeverageOtherDescription: otherDesc, photoJPEG: photoJPEG)
            }
            .environmentObject(settingsStore)
            .environmentObject(subscriptionStore)
            .environmentObject(authStore)
        }
        .adaptiveSheet(isPresented: $showAddPast) {
            AddPastSessionView()
                .environmentObject(store)
                .environmentObject(settingsStore)
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
        .adaptiveSheet(isPresented: $showSubscriptionPaywall) {
            TierTapPaywallView()
                .environmentObject(subscriptionStore)
                .environmentObject(settingsStore)
                .environmentObject(authStore)
        }
    }
}

struct LiveNowCard: View {
    let session: Session
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @State private var elapsed: TimeInterval = 0
    @State private var showStrategyOdds = false
    @State private var showPrivateNotes = false
    let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                    L10nText("LIVE NOW").font(.caption.bold()).foregroundColor(.red)
                }
                Text(session.casino).font(.subheadline.weight(.semibold)).foregroundColor(.white)
                Text(session.game).font(.caption).foregroundColor(.gray)
                Text("Starting tier \(session.startingTierPoints.formatted(.number.grouping(.automatic)))")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.85))
                if let prog = session.rewardsProgramName?.trimmingCharacters(in: .whitespacesAndNewlines), !prog.isEmpty {
                    Text(prog)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(2)
                }
                Text("Total buy-in \(settingsStore.currencySymbol)\(session.totalBuyIn.formatted(.number.grouping(.automatic)))")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.75))
                if session.totalComp > 0 {
                    Text("Total comps \(settingsStore.currencySymbol)\(session.totalComp.formatted(.number.grouping(.automatic)))")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.75))
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Text(Session.durationString(elapsed))
                    .font(.system(.caption, design: .monospaced)).foregroundColor(.green)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
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
                        L10nText("Strategy/Odds")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.green)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(.systemGray6).opacity(0.3))
                            .cornerRadius(8)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.2))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.red.opacity(0.4), lineWidth: 1))
        .onReceive(ticker) { _ in elapsed = Date().timeIntervalSince(session.startTime) }
        .onAppear { elapsed = Date().timeIntervalSince(session.startTime) }
        .adaptiveSheet(isPresented: $showStrategyOdds) {
            StrategyOddsSheet(gameName: session.game)
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
    }
}

struct TapLevelCard: View {
    let tapLevel: TapLevel
    @EnvironmentObject var settingsStore: SettingsStore
    @State private var showLevelsExplainer = false
    @State private var showShareSheet = false
    @State private var shareURL: URL?

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
                    Text("\(tapLevel.sessionCount) sessions · \(tapLevel.sessionMilestoneLabel)")
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
                        shareLevelAsImage()
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
        .adaptiveSheet(isPresented: $showShareSheet) {
            if let url = shareURL {
                ShareSheet(items: [url])
            }
        }
        .onChange(of: showShareSheet) { newValue in
            if !newValue, let url = shareURL {
                try? FileManager.default.removeItem(at: url)
                shareURL = nil
            }
        }
        #endif
    }

    #if os(iOS)
    @MainActor
    private func shareLevelAsImage() {
        let card = TapLevelShareCard(
            tapLevel: tapLevel,
            gradient: settingsStore.primaryGradient
        )
        guard let image = renderTapLevelCardToImage(card) else { return }
        let df = DateFormatter()
        df.dateFormat = "yyyyMMddHHmmss"
        let name = "TierTapLevel\(tapLevel.level)_\(df.string(from: Date())).png"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        guard let data = image.pngData(), (try? data.write(to: url)) != nil else { return }
        shareURL = url
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            showShareSheet = true
        }
    }

    @MainActor
    private func renderTapLevelCardToImage(_ view: TapLevelShareCard) -> UIImage? {
        let width = UIScreen.main.bounds.width * 0.9
        let height: CGFloat = 200
        let wrapped = view
            .frame(width: width, height: height)
        if #available(iOS 16.0, *) {
            let renderer = ImageRenderer(content: wrapped)
            renderer.scale = UIScreen.main.scale
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
    #endif
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
struct TapLevelShareCard: View {
    let tapLevel: TapLevel
    let gradient: LinearGradient

    var body: some View {
        ZStack {
            gradient.ignoresSafeArea()
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Text(tapLevel.sessionMilestoneEmoji)
                        .font(.system(size: 52))
                    Text(tapLevel.emoji)
                        .font(.system(size: 40))
                }
                Text("Tap Level \(tapLevel.level)")
                    .font(.title.bold())
                    .foregroundColor(.white)
                Text(tapLevel.title)
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.9))
                Text("\(tapLevel.sessionCount) sessions · \(tapLevel.sessionMilestoneLabel)")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                L10nText("TierTap")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.vertical, 28)
            .padding(.horizontal, 24)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
