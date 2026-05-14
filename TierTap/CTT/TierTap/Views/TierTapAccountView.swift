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

struct TierTapAccountSignInSection: View {
    @EnvironmentObject var authStore: AuthStore
    @Binding var emailInput: String
    var compact: Bool = false
    var showsBenefitsPitch: Bool = false
    var onContinueWithoutAccount: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 12) {
            if showsBenefitsPitch {
                VStack(alignment: .leading, spacing: 6) {
                    L10nText("Why create an account?")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)

                    VStack(alignment: .leading, spacing: 4) {
                        LocalizedLabel(title: "Advanced AI summaries and guidance for your sessions.", systemImage: "wand.and.stars")
                        LocalizedLabel(title: "Sync your sessions and bankroll safely across devices.", systemImage: "icloud")
                        LocalizedLabel(title: "See and publish Community sessions with other players.", systemImage: "person.3.sequence.fill")
                        LocalizedLabel(title: "Back up your data so you never lose your history.", systemImage: "clock.arrow.circlepath")
                    }
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.9))
                    .labelStyle(.titleAndIcon)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.black.opacity(0.35))
                .cornerRadius(14)
            }

            Button {
                authStore.signInWithApple()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "apple.logo")
                    L10nText("Sign in with Apple")
                }
                .font(.subheadline.bold())
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: compact ? 44 : 44)
                .background(Color.black)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .disabled(authStore.isLoading)

            Button {
                authStore.signInWithGoogle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                    L10nText("Sign in with Google")
                }
                .font(.subheadline.bold())
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .frame(height: compact ? 44 : 44)
                .background(Color.white)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .disabled(authStore.isLoading)

            VStack(alignment: .leading, spacing: 6) {
                L10nText("Email")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)

                L10nText("We'll email a one-time sign-in link — no password.")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)

                TextField("you@example.com", text: $emailInput)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .font(.subheadline)
                    .padding(10)
                    .background(Color.white.opacity(0.15))
                    .cornerRadius(10)
                    .foregroundColor(.white)

                if let info = authStore.infoMessage {
                    Text(info)
                        .font(.caption)
                        .foregroundColor(.green)
                        .multilineTextAlignment(.leading)
                }

                if let msg = authStore.errorMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.leading)
                }

                Button {
                    let trimmedEmail = emailInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    Task { await authStore.signInWithOTP(email: trimmedEmail) }
                } label: {
                    if authStore.isLoading {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(authStore.otpSent ? "Magic link sent" : "Send magic link")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    authStore.isLoading ||
                    emailInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )

                if authStore.otpSent {
                    L10nText("Open the link in the email on this device to finish signing in. You can leave this screen open or close it.")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(4)
                        .minimumScaleFactor(0.85)
                }
            }

            if let onContinueWithoutAccount {
                Button(action: onContinueWithoutAccount) {
                    L10nText("Continue without an account")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Color.white.opacity(0.1))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }

                L10nText("You can continue using TierTap without signing in. For advanced AI features and Community sessions, you’ll need to create and log in to your account.")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .minimumScaleFactor(0.88)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct TierTapAccountView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var authStore: AuthStore
    @EnvironmentObject var subscriptionStore: SubscriptionStore

    @State private var isConfirmingSignOut = false
    @State private var signInEmailInput = ""

    private var hasProAccess: Bool {
        subscriptionStore.isPro || settingsStore.isSubscriptionOverrideActive
    }

    var body: some View {
        ZStack {
            settingsStore.primaryGradient.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 24) {
                    accountCard
                    if authStore.isSignedIn, hasProAccess {
                        tierTapPlusBalancesCard
                    }
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
                VStack(alignment: .leading, spacing: 12) {
                    L10nText("You're not signed in. Sign in with Apple, Google, or a magic link email.")
                        .font(.subheadline)
                        .foregroundColor(.gray)

                    TierTapAccountSignInSection(emailInput: $signInEmailInput)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6).opacity(0.15))
        .cornerRadius(16)
    }

    private var tierTapPlusBalancesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    TierTapPlusMark(
                        font: .headline,
                        weight: .bold,
                        foreground: .white,
                        accessibilitySummarySuppressed: true
                    )
                    Text(L10n.tr("tokens", language: settingsStore.appLanguage))
                        .font(.headline)
                        .foregroundColor(.white)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(L10n.tr("TierTap Plus tokens", language: settingsStore.appLanguage))
            } icon: {
                Image(systemName: "sparkles")
                    .foregroundStyle(settingsStore.primaryGradient)
            }
            TierTapPlusTokenStatBubbles(
                packBalance: settingsStore.aiPurchasedTokenBalance,
                lifetimePurchased: settingsStore.lifetimeTierTapPlusTokensPurchased,
                packUsage: settingsStore.tierTapPlusTokensConsumedFromPurchases
            )

            Text(
                String(
                    format: L10n.tr("Pro plan tokens left this month: %@", language: settingsStore.appLanguage),
                    settingsStore.proPlanIncludedTokensRemainingThisMonth.formatted(.number.grouping(.automatic))
                )
            )
            .font(.caption2)
            .foregroundColor(.gray)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6).opacity(0.15))
        .cornerRadius(16)
    }
}

