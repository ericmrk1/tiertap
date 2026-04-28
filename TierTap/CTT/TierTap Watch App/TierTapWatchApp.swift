import SwiftUI
import UserNotifications
#if os(watchOS)
import WatchKit
#endif

@main
struct TierTapWatchApp: App {
    @StateObject private var store = SessionStore()
    @State private var appLanguage: AppLanguage = .english
    @StateObject private var notificationDelegate = WatchNotificationDelegate()

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(store)
                .environment(\.locale, appLanguage.locale)
                .environment(\.layoutDirection, appLanguage.layoutDirection)
                .environment(\.appLanguage, appLanguage)
                .onOpenURL { url in
                    // Keep deep links idempotent on watch: opening this URL should land on the remote pane.
                    _ = url
                }
                .onAppear {
                    let raw = UserDefaults(suiteName: "group.com.app.tiertap")?.string(forKey: "ctt_app_language")
                    if let raw, let lang = AppLanguage(rawValue: raw) {
                        appLanguage = lang
                    }
                    notificationDelegate.installIfNeeded()
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
