import SwiftUI

@main
struct ForEveryDayApp: App {
    @StateObject private var store = HabitStore()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(store)
        }
    }
}
