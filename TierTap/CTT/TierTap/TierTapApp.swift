import SwiftUI
import UIKit
import StoreKit
import UserNotifications

@main
struct TierTapApp: App {
    @UIApplicationDelegateAdaptor(TierTapAppDelegate.self) private var appDelegate
    @StateObject private var store = SessionStore()
    @StateObject private var tripStore = TripStore()
    @StateObject private var settingsStore = SettingsStore()
    @StateObject private var authStore = AuthStore()
    @StateObject private var subscriptionStore = SubscriptionStore()
    @StateObject private var rewardWalletStore = RewardWalletStore()

    init() {
        BankrollDatabase.shared.open()
        AirportCatalog.preloadAtLaunch()
        UNUserNotificationCenter.current().delegate = ForegroundNotificationDelegate.shared
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

final class TierTapAppDelegate: NSObject, UIApplicationDelegate {}

private final class ForegroundNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ForegroundNotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge, .list])
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
            if newPhase == .active {
                // Ensure watch receives a fresh bootstrap snapshot whenever iPhone foregrounds.
                SessionSyncManager.shared.pushContext(
                    sessions: store.sessions,
                    liveSession: store.liveSession
                )
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
            guard let scheme = url.scheme?.lowercased(), scheme == "com.app.tiertap" else { return }
            let host = (url.host ?? "").lowercased()
            let path = url.path.lowercased()
            if host == "watch", path == "/live" {
                NotificationCenter.default.post(name: NSNotification.Name("OpenSessionsTabFromDeepLink"), object: nil)
            }
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

    private static let holdBeforeZoom: TimeInterval = 0.85
    private static let blowUpDuration: TimeInterval = 0.6
    private static let collapseDuration: TimeInterval = 0.28
    private static let blowUpTargetScale: CGFloat = 50
    private static let collapseTargetScale: CGFloat = 0.01

    private var logoImage: Image {
        if let processed = TransparentLogoCache.image {
            return Image(uiImage: processed)
        }
        return Image("LogoSplash")
    }

    var body: some View {
        GeometryReader { geo in
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
                    scheduleSplashAnimation()
                }
        }
    }

    private func scheduleSplashAnimation() {
        let afterZoom = Self.holdBeforeZoom + Self.blowUpDuration
        let afterCollapse = afterZoom + Self.collapseDuration

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdBeforeZoom) {
            withAnimation(.easeIn(duration: Self.blowUpDuration)) {
                logoScale = Self.blowUpTargetScale
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + afterZoom) {
            withAnimation(.easeOut(duration: Self.collapseDuration)) {
                logoScale = Self.collapseTargetScale
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + afterCollapse) {
            onFinished()
        }
    }
}
