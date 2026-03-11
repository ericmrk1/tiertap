import SwiftUI

struct WelcomeAuthGatewayView: View {
    @EnvironmentObject var authStore: AuthStore
    @EnvironmentObject var settingsStore: SettingsStore

    /// Controls whether this full-screen welcome is visible.
    @Binding var isPresented: Bool

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""

    private enum EmailAuthMode: String, CaseIterable, Identifiable {
        case signIn
        case signUp

        var id: String { rawValue }

        var title: String {
            switch self {
            case .signIn: return "Sign in"
            case .signUp: return "Sign up"
            }
        }

        var buttonTitle: String {
            switch self {
            case .signIn: return "Sign in with email"
            case .signUp: return "Create email account"
            }
        }
    }

    @State private var emailAuthMode: EmailAuthMode = .signUp

    private var logoImage: Image {
        if let processed = TransparentLogoCache.image {
            return Image(uiImage: processed)
        }
        return Image("LogoSplash")
    }

    var body: some View {
        ZStack {
            settingsStore.primaryGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    headerSection
                    benefitsSection
                    authSection
                    continueWithoutAccountSection
                }
                .padding(24)
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 16) {
            logoImage
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 160)
                .shadow(radius: 12)

            Text("Welcome to TierTap")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .multilineTextAlignment(.center)
                .foregroundColor(.white)

            Text("Track your casino sessions, understand your tier points, and let advanced AI help you make smarter decisions about your play.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)
        }
        .padding(.top, 32)
    }

    private var benefitsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Why create a TierTap account?")
                .font(.headline)
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 8) {
                Label("Unlock advanced AI summaries and suggestions for your sessions.", systemImage: "wand.and.stars")
                Label("Sync your bankroll and session history safely across devices.", systemImage: "icloud")
                Label("Join community sessions — see what others are playing and publish your own.", systemImage: "person.3.sequence.fill")
                Label("Back up your data so you never lose your history.", systemImage: "clock.arrow.circlepath")
            }
            .font(.footnote)
            .foregroundColor(.white.opacity(0.9))
        }
        .padding(16)
        .background(Color.black.opacity(0.35))
        .cornerRadius(18)
    }

    private var authSection: some View {
        VStack(spacing: 14) {
            if !SupabaseConfig.isConfigured {
                Text("To enable sign-in, add your Supabase keys. You can still use TierTap without an account.")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 4)
            } else if !authStore.isSignedIn {
                VStack(spacing: 14) {
                    Button {
                        authStore.signInWithApple()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "apple.logo")
                            Text("Sign in with Apple")
                                .fontWeight(.semibold)
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.black)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    .disabled(authStore.isLoading || !SupabaseConfig.isConfigured)

                    Button {
                        authStore.signInWithGoogle()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "globe")
                            Text("Sign in with Google")
                                .fontWeight(.semibold)
                        }
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.white)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    .disabled(authStore.isLoading || !SupabaseConfig.isConfigured)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Email account")
                            .font(.headline)
                            .foregroundColor(.white)

                        Picker("Email auth mode", selection: $emailAuthMode) {
                            ForEach(EmailAuthMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(12)
                            .background(Color.white.opacity(0.15))
                            .cornerRadius(10)
                            .foregroundColor(.white)

                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(12)
                            .background(Color.white.opacity(0.15))
                            .cornerRadius(10)
                            .foregroundColor(.white)

                        if emailAuthMode == .signUp {
                            SecureField("Confirm password", text: $confirmPassword)
                                .textContentType(.password)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(12)
                                .background(Color.white.opacity(0.15))
                                .cornerRadius(10)
                                .foregroundColor(.white)
                        }

                        if let info = authStore.infoMessage {
                            Text(info)
                                .font(.caption)
                                .foregroundColor(.green)
                                .multilineTextAlignment(.leading)
                        }

                        if let error = authStore.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.leading)
                        }

                        Button {
                            let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
                            switch emailAuthMode {
                            case .signIn:
                                Task { await authStore.signInWithEmailPassword(email: trimmedEmail, password: password) }
                            case .signUp:
                                Task { await authStore.signUpWithEmailPassword(email: trimmedEmail, password: password) }
                            }
                        } label: {
                            if authStore.isLoading {
                                ProgressView()
                                    .tint(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                            } else {
                                Text(emailAuthMode.buttonTitle)
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .disabled(
                            authStore.isLoading ||
                            !SupabaseConfig.isConfigured ||
                            email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            password.isEmpty ||
                            (emailAuthMode == .signUp && confirmPassword.isEmpty) ||
                            (emailAuthMode == .signUp && confirmPassword != password)
                        )
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.green)

                    Text("You're signed in to TierTap.")
                        .font(.headline)
                        .foregroundColor(.white)

                    if let name = authStore.userDisplayName, !name.isEmpty {
                        Text(name)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                    } else if let email = authStore.userEmail {
                        Text(email)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                    }

                    Text("You’re ready to unlock advanced AI features and community sessions.")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                }
                .padding(16)
                .background(Color.black.opacity(0.35))
                .cornerRadius(18)
            }
        }
    }

    private var continueWithoutAccountSection: some View {
        VStack(spacing: 8) {
            Button {
                isPresented = false
            } label: {
                Text("Continue without an account")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.white.opacity(0.12))
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)

            Text("You can keep using TierTap without signing in. For advanced AI features and Community sessions, you’ll need to create and log in to your account.")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }
}

