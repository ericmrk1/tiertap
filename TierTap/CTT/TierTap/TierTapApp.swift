import SwiftUI

@main
struct TierTapApp: App {
    @StateObject private var store = SessionStore()
    @StateObject private var settingsStore = SettingsStore()

    init() {
        BankrollDatabase.shared.open()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(store)
                .environmentObject(settingsStore)
                .preferredColorScheme(ColorScheme.dark)
        }
    }
}
