import SwiftUI

/// Lock Down TierTap (app lock) — same card everywhere account is shown full-screen.
struct LockDownTierTapSection: View {
    @EnvironmentObject var settingsStore: SettingsStore
    /// Tighter copy and spacing for sheets (e.g. Community Account) so content fits one screen.
    var compact: Bool = false

    @State private var lockConfigAlert: String?

    var body: some View {
        lockDownCard
            .alert("Lock", isPresented: Binding(
                get: { lockConfigAlert != nil },
                set: { if !$0 { lockConfigAlert = nil } }
            )) {
                Button("OK", role: .cancel) { lockConfigAlert = nil }
            } message: {
                Text(lockConfigAlert ?? "")
            }
    }

    private var lockDownCard: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 14) {
            HStack(alignment: .center, spacing: compact ? 6 : 10) {
                Text(settingsStore.appLockEnabled ? "\u{1F512}" : "\u{1F513}")
                    .font(.system(size: compact ? 22 : 28))
                L10nText("Lock Down TierTap")
                    .font(compact ? .subheadline.bold() : .headline)
                    .foregroundColor(.white)
            }

            Group {
                if compact {
                    L10nText("Require Face ID, Touch ID, or your device passcode to reopen TierTap after you leave the app.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    L10nText("When lock down is on, you must use Face ID, Touch ID, or your device passcode to open TierTap after you leave the app or when you launch it again. This adds a layer of privacy on top of your phone’s lock.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.88))
                }
            }

            Toggle(isOn: Binding(
                get: { settingsStore.appLockEnabled },
                set: { newValue in
                    if newValue {
                        enableLockDown()
                    } else {
                        settingsStore.appLockEnabled = false
                        AppLockPINLegacy.clearFromKeychain()
                    }
                }
            )) {
                L10nText("Require unlock to open TierTap")
            }
            .tint(.green)

            if settingsStore.appLockEnabled {
                VStack(alignment: .leading, spacing: compact ? 6 : 10) {
                    L10nText("Unlock method")
                        .font(compact ? .caption.bold() : .subheadline.bold())
                        .foregroundColor(.white)
                    Picker("Unlock method", selection: $settingsStore.appLockAuthMethod) {
                        L10nText("Face ID / Touch ID").tag(SettingsStore.AppLockAuthMethod.faceID)
                        L10nText("Device passcode").tag(SettingsStore.AppLockAuthMethod.pin)
                    }
                    .pickerStyle(.segmented)
                    .controlSize(compact ? .small : .regular)

                    if settingsStore.appLockAuthMethod == .pin {
                        if compact {
                            L10nText("Uses the system passcode screen; biometrics may be offered first.")
                                .font(.caption2)
                                .foregroundColor(.gray)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            L10nText("Uses the same system screen as your iPhone passcode. iOS may offer Face ID or Touch ID first; you can choose the passcode option if you prefer.")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    } else {
                        if compact {
                            L10nText("Face ID or Touch ID when available, with passcode as backup.")
                                .font(.caption2)
                                .foregroundColor(.gray)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            L10nText("Uses Face ID or Touch ID when available, with your device passcode as a backup.")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
        }
        .padding(compact ? 12 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6).opacity(0.15))
        .cornerRadius(16)
    }

    private func enableLockDown() {
        guard AppLockSystemAuth.canUseDeviceAuthentication() else {
            lockConfigAlert = "Turn on a device passcode (and Face ID or Touch ID if you like) in iOS Settings before locking TierTap."
            return
        }
        settingsStore.appLockEnabled = true
    }
}

struct TierTapAccountView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var authStore: AuthStore

    @State private var isConfirmingSignOut = false

    var body: some View {
        ZStack {
            settingsStore.primaryGradient.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 24) {
                    accountCard
                    LockDownTierTapSection()
                }
                .padding()
            }
        }
        .localizedNavigationTitle("TierTap Account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .confirmationDialog(
            "Sign out of TierTap?",
            isPresented: $isConfirmingSignOut,
            titleVisibility: .visible
        ) {
            Button("Sign out", role: .destructive) {
                authStore.signOut()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            L10nText("You’ll need to sign in again for account features. This does not delete your sessions or settings stored on this device.")
        }
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                L10nText("Account")
                    .font(.headline)
                    .foregroundColor(.white)
            } icon: {
                Image(systemName: "person.crop.circle.fill")
                    .foregroundStyle(settingsStore.primaryGradient)
            }

            if !SupabaseConfig.isConfigured {
                L10nText("Add Supabase keys to enable sign-in and sync.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            } else if authStore.isSignedIn {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(settingsStore.primaryGradient)
                    VStack(alignment: .leading, spacing: 2) {
                        L10nText("Signed in")
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                        if let name = authStore.userFullName, !name.isEmpty {
                            Text(name)
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.95))
                        }
                        if let email = authStore.userEmail {
                            Text(email)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                    Spacer()
                    Button("Sign out", role: .destructive) {
                        isConfirmingSignOut = true
                    }
                    .font(.subheadline)
                }
                .padding(.vertical, 4)
            } else {
                L10nText("You're not signed in. Open the **Community** tab to sign in with Apple, Google, or a magic link email.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6).opacity(0.15))
        .cornerRadius(16)
    }
}

