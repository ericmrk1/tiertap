import SwiftUI
import UIKit
import StoreKit

@main
struct TierTapApp: App {
    @StateObject private var store = SessionStore()
    @StateObject private var tripStore = TripStore()
    @StateObject private var settingsStore = SettingsStore()
    @StateObject private var authStore = AuthStore()
    @StateObject private var subscriptionStore = SubscriptionStore()
    @StateObject private var rewardWalletStore = RewardWalletStore()

    init() {
        BankrollDatabase.shared.open()
        AirportCatalog.preloadAtLaunch()
    }

    var body: some Scene {
        WindowGroup {
            TierTapAppRoot()
                .environmentObject(store)
                .environmentObject(tripStore)
                .environmentObject(settingsStore)
                .environmentObject(authStore)
                .environmentObject(subscriptionStore)
                .environmentObject(rewardWalletStore)
        }
    }
}

private struct TierTapAppRoot: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var subscriptionStore: SubscriptionStore

    @State private var showSplash = true
    @State private var showWelcome = false
    @State private var welcomeEmailInput = ""
    @State private var appSessionUnlocked = true
    /// Matches previous behavior: auto-present sign-in sheet at most once per launch (unless triggered by notification).
    @State private var didOfferWelcomeThisSession = false

    var body: some View {
        ZStack {
            RootTabView()
                .preferredColorScheme(ColorScheme.dark)

            if shouldShowLockGate {
                AppLockGateView {
                    appSessionUnlocked = true
                    maybeShowWelcomeAfterUnlock()
                }
                .environmentObject(settingsStore)
                .transition(.opacity)
                .zIndex(3)
            }

            if showSplash {
                SplashScreen(gradient: settingsStore.primaryGradient) {
                    showSplash = false
                    if settingsStore.appLockEnabled {
                        appSessionUnlocked = false
                    }
                    maybeShowWelcomeAfterUnlock()
                }
                .transition(.opacity)
                .zIndex(2)
            }

            if let toast = store.walletTierCloseoutToast {
                WalletTierCloseoutToastBanner(fromPoints: toast.fromPoints, toPoints: toast.toPoints)
                    .zIndex(15)
                    .transition(.opacity)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + WalletTierCloseoutTiming.totalAutoDismiss) {
                            store.walletTierCloseoutToast = nil
                        }
                    }
            }
        }
        .environment(\.locale, settingsStore.appLanguage.locale)
        .environment(\.layoutDirection, settingsStore.appLanguage.layoutDirection)
        .environment(\.appLanguage, settingsStore.appLanguage)
        .animation(.easeOut(duration: 0.4), value: showSplash)
        .animation(.easeOut(duration: 0.35), value: showWelcome)
        .animation(.easeOut(duration: 0.25), value: shouldShowLockGate)
        .onAppear {
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("ShowAccountSheet"),
                object: nil,
                queue: .main
            ) { _ in
                showWelcome = true
            }
            if settingsStore.appLockEnabled {
                appSessionUnlocked = false
            }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background && settingsStore.appLockEnabled {
                appSessionUnlocked = false
            }
        }
        .onChange(of: settingsStore.appLockEnabled) { enabled in
            if enabled {
                appSessionUnlocked = false
            } else {
                appSessionUnlocked = true
                maybeShowWelcomeAfterUnlock()
            }
        }
        .onOpenURL { url in
            authStore.handleOpenURL(url)
        }
        .adaptiveSheet(isPresented: $showWelcome) {
            CommunityAuthSheet(
                emailInput: $welcomeEmailInput,
                onDismiss: { showWelcome = false }
            )
            .environmentObject(authStore)
            .environmentObject(settingsStore)
            .environmentObject(subscriptionStore)
            .environment(\.appLanguage, settingsStore.appLanguage)
        }
        .sheet(item: postCloseoutShareSheetBinding) { ref in
            PostCloseoutShareFlowView(sessionId: ref.id)
                .environmentObject(store)
                .environmentObject(settingsStore)
                .environmentObject(authStore)
        }
    }

    private var postCloseoutShareSheetBinding: Binding<PostCloseoutSessionRef?> {
        Binding(
            get: { store.postCloseoutSharePromptSessionId.map(PostCloseoutSessionRef.init(id:)) },
            set: { newValue in
                if newValue == nil {
                    store.clearPostCloseoutSharePrompt()
                }
            }
        )
    }

    private var shouldShowLockGate: Bool {
        !showSplash && settingsStore.appLockEnabled && !appSessionUnlocked
    }

    private func maybeShowWelcomeAfterUnlock() {
        guard !showSplash, appSessionUnlocked, !authStore.isSignedIn, !didOfferWelcomeThisSession else { return }
        didOfferWelcomeThisSession = true
        showWelcome = true
    }
}

struct SplashScreen: View {
    let gradient: LinearGradient
    var onFinished: () -> Void

    @State private var logoScale: CGFloat = 1
    @State private var didScheduleSequence = false

    private var logoImage: Image {
        if let processed = TransparentLogoCache.image {
            return Image(uiImage: processed)
        }
        return Image("LogoSplash")
    }

    var body: some View {
        GeometryReader { geo in
            let padded = max(100, min(geo.size.width - 80, 320))
            let minSide = min(geo.size.width, geo.size.height)
            let peakScale = min(10, max(1.3, minSide * 1.22 / padded))
            let collapseScale = max(1 / padded, 1e-4)

            gradient
                .ignoresSafeArea()
                .overlay {
                    logoImage
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 320)
                        .padding(40)
                        .scaleEffect(logoScale)
                }
                .onAppear {
                    guard !didScheduleSequence, geo.size.width > 10 else { return }
                    didScheduleSequence = true
                    scheduleSplashAnimation(peakScale: peakScale, collapseScale: collapseScale)
                }
        }
    }

    private func scheduleSplashAnimation(peakScale: CGFloat, collapseScale: CGFloat) {
        let growDuration: TimeInterval = 2
        let shrinkDuration: TimeInterval = 0.10
        let holdBeforeGrow: TimeInterval = 2

        DispatchQueue.main.asyncAfter(deadline: .now() + holdBeforeGrow) {
            withAnimation(.easeInOut(duration: growDuration)) {
                logoScale = peakScale
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + growDuration) {
                withAnimation(.easeIn(duration: shrinkDuration)) {
                    logoScale = collapseScale
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + shrinkDuration) {
                    onFinished()
                }
            }
        }
    }
}
