import SwiftUI
import UserNotifications
#if os(watchOS)
import WatchKit
#endif

@main
struct TierTapWatchApp: App {
    @StateObject private var store = SessionStore()
    @StateObject private var themeStore = TierTapThemeStore()
    @ObservedObject private var tierGoalCelebration = WatchTierGoalCelebrationController.shared
    @State private var appLanguage: AppLanguage = .english
    @State private var showSplash = true
    @StateObject private var notificationDelegate = WatchNotificationDelegate()
    @AppStorage(
        TierTapWatchAnimationsSettings.userDefaultsKey,
        store: UserDefaults(suiteName: TierTapWatchAnimationsSettings.appGroupSuiteName)
    ) private var watchTierTapAnimationsEnabled = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                WatchContentView()
                    .environmentObject(store)
                    .environmentObject(themeStore)
                    .environment(\.watchTheme, WatchThemePalette(from: themeStore))
                    .environment(\.tierTapWatchAnimationsEnabled, watchTierTapAnimationsEnabled)
                    .environment(\.locale, appLanguage.locale)
                    .environment(\.layoutDirection, appLanguage.layoutDirection)
                    .environment(\.appLanguage, appLanguage)
                    .opacity(showSplash ? 0 : 1)

                if showSplash {
                    WatchSplashScreen {
                        withAnimation(.easeOut(duration: 0.25)) {
                            showSplash = false
                        }
                    }
                    .environmentObject(themeStore)
                    .environment(\.watchTheme, WatchThemePalette(from: themeStore))
                    .environment(\.tierTapWatchAnimationsEnabled, watchTierTapAnimationsEnabled)
                }

                if let event = tierGoalCelebration.activeEvent, !showSplash {
                    WatchTierGoalCelebrationOverlay(event: event) {
                        tierGoalCelebration.dismissActive()
                    }
                    .environment(\.watchTheme, WatchThemePalette(from: themeStore))
                    .environment(\.tierTapWatchAnimationsEnabled, watchTierTapAnimationsEnabled)
                    .transition(.opacity)
                    .zIndex(100)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: tierGoalCelebration.activeEvent?.id)
            .onOpenURL { url in
                // Keep deep links idempotent on watch: opening this URL should land on the remote pane.
                _ = url
            }
            .onAppear {
                themeStore.reload()
                let raw = UserDefaults(suiteName: "group.com.app.tiertap")?.string(forKey: "ctt_app_language")
                if let raw, let lang = AppLanguage(rawValue: raw) {
                    appLanguage = lang
                }
                notificationDelegate.installIfNeeded()
                tierGoalCelebration.installHandlers()
            }
        }
    }
}

final class WatchNotificationDelegate: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    private var isInstalled = false

    func installIfNeeded() {
        guard !isInstalled else { return }
        UNUserNotificationCenter.current().delegate = self
        isInstalled = true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        playTierTapHaptic()
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        _ = response
        playTierTapHaptic()
        completionHandler()
    }

    private func playTierTapHaptic() {
        #if os(watchOS)
        DispatchQueue.main.async {
            WKInterfaceDevice.current().play(.notification)
        }
        #endif
    }
}

private struct TierTapWatchAnimationsEnvironmentKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// When false (or Reduce Motion on), TierTap Watch skips decorative motion (press scale, ripples, symbol effects).
    var tierTapWatchAnimationsEnabled: Bool {
        get { self[TierTapWatchAnimationsEnvironmentKey.self] }
        set { self[TierTapWatchAnimationsEnvironmentKey.self] = newValue }
    }
}
