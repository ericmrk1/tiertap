import SwiftUI

@main
struct TierTapWatchApp: App {
    @StateObject private var store = SessionStore()

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(store)
        }
    }
}
