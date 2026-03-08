import SwiftUI
import UIKit

@main
struct TierTapApp: App {
    @StateObject private var store = SessionStore()
    @StateObject private var settingsStore = SettingsStore()
    @StateObject private var authStore = AuthStore()
    @State private var showSplash = true

    init() {
        BankrollDatabase.shared.open()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootTabView()
                    .environmentObject(store)
                    .environmentObject(settingsStore)
                    .environmentObject(authStore)
                    .preferredColorScheme(ColorScheme.dark)

                if showSplash {
                    SplashScreen(gradient: settingsStore.primaryGradient)
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .animation(.easeOut(duration: 0.4), value: showSplash)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    showSplash = false
                }
            }
            .onOpenURL { url in
                authStore.handleOpenURL(url)
            }
        }
    }
}

struct SplashScreen: View {
    let gradient: LinearGradient

    private var logoImage: Image {
        if let processed = TransparentLogoCache.image {
            return Image(uiImage: processed)
        }
        return Image("LogoSplash")
    }

    var body: some View {
        gradient
            .ignoresSafeArea()
            .overlay {
                logoImage
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 320)
                    .padding(40)
            }
    }
}
