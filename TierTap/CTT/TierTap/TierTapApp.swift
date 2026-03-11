import SwiftUI
import UIKit

@main
struct TierTapApp: App {
    @StateObject private var store = SessionStore()
    @StateObject private var settingsStore = SettingsStore()
    @StateObject private var authStore = AuthStore()
    @State private var showSplash = true
    @State private var showWelcome = false
    @State private var welcomeEmailInput = ""

    init() {
        BankrollDatabase.shared.open()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootTabView()
                    .preferredColorScheme(ColorScheme.dark)

                if showSplash {
                    SplashScreen(gradient: settingsStore.primaryGradient)
                        .transition(.opacity)
                        .zIndex(2)
                }
            }
            .environmentObject(store)
            .environmentObject(settingsStore)
            .environmentObject(authStore)
            .animation(.easeOut(duration: 0.4), value: showSplash)
            .animation(.easeOut(duration: 0.35), value: showWelcome)
            .onAppear {
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("ShowAccountSheet"),
                    object: nil,
                    queue: .main
                ) { _ in
                    showWelcome = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    showSplash = false
                    if !authStore.isSignedIn {
                        showWelcome = true
                    }
                }
            }
            .onOpenURL { url in
                authStore.handleOpenURL(url)
            }
            .sheet(isPresented: $showWelcome) {
                CommunityAuthSheet(
                    emailInput: $welcomeEmailInput,
                    onDismiss: { showWelcome = false }
                )
                .environmentObject(authStore)
                .environmentObject(settingsStore)
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
