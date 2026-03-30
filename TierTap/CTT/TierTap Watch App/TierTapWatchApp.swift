import SwiftUI

@main
struct TierTapWatchApp: App {
    @StateObject private var store = SessionStore()
    @State private var appLanguage: AppLanguage = .english

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(store)
                .environment(\.locale, appLanguage.locale)
                .environment(\.layoutDirection, appLanguage.layoutDirection)
                .environment(\.appLanguage, appLanguage)
                .onAppear {
                    let raw = UserDefaults(suiteName: "group.com.app.tiertap")?.string(forKey: "ctt_app_language")
                    if let raw, let lang = AppLanguage(rawValue: raw) {
                        appLanguage = lang
                    }
                }
        }
    }
}
