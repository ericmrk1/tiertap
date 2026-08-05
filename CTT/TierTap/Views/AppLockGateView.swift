import SwiftUI

/// Full-screen unlock UI when TierTap is locked (after backgrounding or on launch).
struct AppLockGateView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    let onUnlocked: () -> Void

    @State private var authError: String?
    @State private var isAuthenticating = false

    var body: some View {
        ZStack {
            settingsStore.primaryGradient.ignoresSafeArea()
            VStack(spacing: 24) {
                Text(lockEmoji)
                    .font(.system(size: 56))
                L10nText("TierTap is locked")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                L10nText(unlockHint)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button {
                    runSystemAuth()
                } label: {
                    HStack {
                        Image(systemName: systemButtonIcon)
                        L10nText(systemButtonTitle)
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white.opacity(0.2))
                    .foregroundColor(.white)
                    .cornerRadius(14)
                }
                .buttonStyle(.plain)
                .disabled(isAuthenticating || !AppLockSystemAuth.canUseDeviceAuthentication())
                .padding(.horizontal)

                if let authError {
                    Text(authError)
                        .font(.caption)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .padding()
        }
        .onAppear {
            runSystemAuth()
        }
    }

    private var lockEmoji: String {
        "\u{1F512}"
    }

    private var unlockHint: String {
        switch settingsStore.appLockAuthMethod {
        case .faceID:
            return "Use Face ID, Touch ID, or your device passcode to continue."
        case .pin:
            return "Use your iPhone passcode (or Face ID / Touch ID when offered) to continue."
        }
    }

    private var systemButtonTitle: String {
        switch settingsStore.appLockAuthMethod {
        case .faceID:
            return "Unlock with Face ID / Touch ID"
        case .pin:
            return "Unlock with device passcode"
        }
    }

    private var systemButtonIcon: String {
        switch settingsStore.appLockAuthMethod {
        case .faceID:
            return "faceid"
        case .pin:
            return "lock.fill"
        }
    }

    private func runSystemAuth() {
        guard AppLockSystemAuth.canUseDeviceAuthentication() else {
            authError = "Turn on a device passcode in Settings to use lock."
            return
        }
        isAuthenticating = true
        authError = nil
        AppLockSystemAuth.authenticate(reason: "Unlock TierTap") { ok in
            isAuthenticating = false
            if ok {
                onUnlocked()
            } else {
                authError = "Authentication did not complete."
            }
        }
    }
}
