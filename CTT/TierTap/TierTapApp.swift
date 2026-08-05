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

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        _ = TierTapProductEnhancements.handleNotificationResponse(response)
        completionHandler()
    }
}

private struct TierTapAppRoot: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var tripStore: TripStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @EnvironmentObject private var rewardWalletStore: RewardWalletStore

    @State private var showSplash = true
    @State private var showWelcome = false
    @State private var welcomeEmailInput = ""
    @State private var appSessionUnlocked = true
    /// Matches previous behavior: auto-present sign-in sheet at most once per launch (unless triggered by notification).
    @State private var didOfferWelcomeThisSession = false
    @State private var showAppFeedbackPrompt = false
    @State private var showMonthlyWrapped = false
    @ObservedObject private var celebrationController = TierTapCelebrationController.shared

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

            if let message = store.communityPublishToastMessage {
                CommunityPublishSuccessToast(message: message)
                    .zIndex(16)
                    .transition(.opacity)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + CommunityPublishSuccessToast.autoDismissDuration) {
                            if store.communityPublishToastMessage == message {
                                store.communityPublishToastMessage = nil
                            }
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
        .task {
            await settingsStore.refreshRemoteAppDefaults()
        }
        .task(id: authStore.session?.user.id) {
            guard authStore.isSignedIn else { return }
            await settingsStore.syncAITokenBalancesFromSupabaseSession()
        }
        .onAppear {
            store.watchActionAuthStore = authStore
            store.watchActionSettingsStore = settingsStore
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
                Task { await settingsStore.refreshRemoteAppDefaults() }
                handlePendingWidgetDestination()
                handlePendingSessionDetailFromWidget()
                LiveActivityManager.shared.reconcile(liveSession: store.liveSession)
                // Ensure watch receives a fresh bootstrap snapshot whenever iPhone foregrounds.
                SessionSyncManager.shared.pushContext(
                    sessions: store.sessions,
                    liveSession: store.liveSession
                )
                TierTapProductEnhancements.scheduleMonthlyWrappedNotificationIfNeeded(sessions: store.sessions)
                TierTapProductEnhancements.scheduleBetweenSessionNudgesIfNeeded(
                    sessions: store.sessions,
                    trips: tripStore.trips,
                    walletCards: rewardWalletStore.cards
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: TierTapProductEnhancements.showMonthlyWrappedNotificationName)) { _ in
            guard TierTapProductEnhancements.isEnabled else { return }
            showMonthlyWrapped = true
        }
        .adaptiveSheet(isPresented: $showMonthlyWrapped) {
            TierTapWrappedView()
                .environmentObject(store)
                .environmentObject(settingsStore)
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
            handleTierTapDeepLink(url)
        }
        .onAppear {
            handlePendingWidgetDestination()
            handlePendingSessionDetailFromWidget()
            TierTapProductEnhancements.scheduleMonthlyWrappedNotificationIfNeeded(sessions: store.sessions)
            TierTapProductEnhancements.scheduleBetweenSessionNudgesIfNeeded(
                sessions: store.sessions,
                trips: tripStore.trips,
                walletCards: rewardWalletStore.cards
            )
            celebrationController.checkTapLevel(
                from: store.sessions,
                liveSessionActive: store.liveSession != nil
            )
        }
        .onChange(of: store.sessions) { _ in
            celebrationController.checkTapLevel(
                from: store.sessions,
                liveSessionActive: store.liveSession != nil
            )
        }
        .onChange(of: store.liveSession?.id) { _ in
            celebrationController.checkTapLevel(
                from: store.sessions,
                liveSessionActive: store.liveSession != nil
            )
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
        #if os(iOS)
        .halfScreenSheet(isPresented: $showAppFeedbackPrompt) {
            AppFeedbackSheet()
                .environmentObject(settingsStore)
                .environment(\.appLanguage, settingsStore.appLanguage)
        }
        .onReceive(NotificationCenter.default.publisher(for: .tierTapSessionCompletedForReviewPrompt)) { _ in
            guard settingsStore.recordCompletedSessionAndShouldPromptFeedback() else { return }
            // Wait for close-out / mood / share sheets to finish so this can appear over any tab.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                guard !showSplash, appSessionUnlocked, !settingsStore.hasLeftAppReview else { return }
                showAppFeedbackPrompt = true
            }
        }
        #endif
        #if os(iOS)
        .fullScreenCover(item: celebrationPresentationBinding) { celebration in
            TierTapCelebrationScreen(celebration: celebration) {
                celebrationController.dismissActive()
            }
            .environmentObject(settingsStore)
        }
        #endif
    }

    private var celebrationPresentationBinding: Binding<TierTapCelebration?> {
        Binding(
            get: {
                guard !showSplash, appSessionUnlocked else { return nil }
                return celebrationController.activeCelebration
            },
            set: { newValue in
                if newValue == nil {
                    celebrationController.dismissActive()
                }
            }
        )
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

    private func handleTierTapDeepLink(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "com.app.tiertap" else { return }
        let host = (url.host ?? "").lowercased()
        let path = url.path.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if host == "watch", path == "live" {
            postWidgetNavigation(.live)
            return
        }
        if host == "watch" {
            postWidgetNavigation(.home)
            return
        }
        if host == "analytics" || path == "analytics" {
            postWidgetNavigation(.analytics)
            return
        }
        if host == "sessions" {
            if path.hasPrefix("detail/") {
                let idString = String(path.dropFirst("detail/".count))
                if let uuid = UUID(uuidString: idString) {
                    TierTapWidgetSessionDetailRouter.pendingSessionID = uuid
                    postWidgetNavigation(.home)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        handlePendingSessionDetailFromWidget()
                    }
                    return
                }
            }
            switch path {
            case "checkin":
                postWidgetNavigation(.checkIn)
            case "live":
                postWidgetNavigation(.live)
            case "history":
                postWidgetNavigation(.history)
            case "bankroll":
                postWidgetNavigation(.bankroll)
            case "wallet":
                postWidgetNavigation(.wallet)
            default:
                postWidgetNavigation(.home)
            }
        }
    }

    private func handlePendingWidgetDestination() {
        guard let destination = TierTapWidgetIntentRouter.consumePendingDestination() else { return }
        switch destination {
        case .checkIn: postWidgetNavigation(.checkIn)
        case .live: postWidgetNavigation(.live)
        case .analytics: postWidgetNavigation(.analytics)
        case .history: postWidgetNavigation(.history)
        case .bankroll: postWidgetNavigation(.bankroll)
        case .wallet: postWidgetNavigation(.wallet)
        case .home: postWidgetNavigation(.home)
        }
    }

    private func handlePendingSessionDetailFromWidget() {
        guard let sessionID = TierTapWidgetSessionDetailRouter.consumePendingSessionID() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            NotificationCenter.default.post(
                name: NSNotification.Name("OpenSessionDetailFromDeepLink"),
                object: sessionID
            )
        }
    }

    private func postWidgetNavigation(_ destination: TierTapWidgetIntentRouter.Destination) {
        switch destination {
        case .analytics:
            NotificationCenter.default.post(name: NSNotification.Name("OpenAnalyticsTabFromDeepLink"), object: nil)
        case .checkIn, .live, .history, .home, .bankroll, .wallet:
            NotificationCenter.default.post(name: NSNotification.Name("OpenSessionsTabFromDeepLink"), object: nil)
            let actionName: String
            switch destination {
            case .checkIn: actionName = "OpenCheckInFromDeepLink"
            case .live: actionName = "OpenLiveFromDeepLink"
            case .history: actionName = "OpenHistoryFromDeepLink"
            case .bankroll: actionName = "OpenBankrollFromDeepLink"
            case .wallet: actionName = "OpenWalletFromDeepLink"
            default: actionName = ""
            }
            if !actionName.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    NotificationCenter.default.post(name: NSNotification.Name(actionName), object: nil)
                }
            }
        }
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
