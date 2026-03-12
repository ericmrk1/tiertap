import AuthenticationServices
import CryptoKit
import Foundation
import Supabase
import SwiftUI

/// Manages Supabase auth state for the Community tab. Sign in via magic link (email OTP) or Sign in with Apple.
@MainActor
final class AuthStore: ObservableObject {
    @Published private(set) var session: Auth.Session?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    /// Generic informational message for non-error auth states (e.g. "Check your email").
    @Published var infoMessage: String?
    @Published var otpSent = false

    private var authStateTask: Task<Void, Never>?
    private var appleAuthDelegate: AppleSignInDelegate?
    private var oauthPresentationProvider: OAuthPresentationContextProvider?

    var isSignedIn: Bool { session != nil }
    var userEmail: String? { session?.user.email }

    /// First/given name from user metadata (Google, Apple, or custom).
    var userGivenName: String? { stringFromUserMetadata("given_name") }
    /// Last/family name from user metadata.
    var userFamilyName: String? { stringFromUserMetadata("family_name") }
    /// Full name from user metadata, or "given_name family_name" if only those are set.
    var userFullName: String? {
        if let full = stringFromUserMetadata("full_name"), !full.isEmpty { return full }
        if let name = stringFromUserMetadata("name"), !name.isEmpty { return name } // e.g. Google
        let given = userGivenName ?? ""
        let family = userFamilyName ?? ""
        let combined = [given, family].filter { !$0.isEmpty }.joined(separator: " ")
        return combined.isEmpty ? nil : combined
    }

    /// User-editable display name (stored in metadata). Falls back to provider name if not set.
    var userDisplayName: String? {
        if let custom = stringFromUserMetadata("display_name"), !custom.isEmpty { return custom }
        return userFullName
    }

    /// Profile emojis set by the user (stored in metadata).
    var userProfileEmojis: String? { stringFromUserMetadata("profile_emojis") }

    /// Profile photo stored as base64-encoded JPEG in user metadata.
    var userProfilePhotoBase64: String? { stringFromUserMetadata("profile_photo_base64") }

    /// Decoded profile photo data (if available).
    var userProfilePhotoData: Data? {
        guard let base64 = userProfilePhotoBase64 else { return nil }
        return Data(base64Encoded: base64)
    }

    /// Short label for UI: display name or "email@example.com" when no name is available.
    var signedInSummary: String? {
        if let name = userDisplayName, !name.isEmpty { return name }
        guard let email = session?.user.email, !email.isEmpty else { return nil }
        return email
    }

    /// Update profile display name, emojis, and/or photo in Supabase user metadata.
    func updateProfile(displayName: String?, emojis: String?, photoBase64: String?) async {
        guard let client = supabase else { return }
        var data: [String: AnyJSON] = [:]
        if let name = displayName { data["display_name"] = .string(name) }
        if let e = emojis { data["profile_emojis"] = .string(e) }
        if let photo = photoBase64 { data["profile_photo_base64"] = .string(photo) }
        guard !data.isEmpty else { return }
        do {
            _ = try await client.auth.update(user: .init(data: data))
            // Auth state observer will receive .userUpdated and update session
            if let newSession = try? await client.auth.session {
                await MainActor.run { session = newSession }
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    private func stringFromUserMetadata(_ key: String) -> String? {
        guard let meta = session?.user.userMetadata else { return nil }
        if let s = meta[key]?.stringValue, !s.isEmpty { return s }
        return nil
    }

    init() {
        session = nil
        authStateTask = Task { await observeAuthState() }
    }

    deinit {
        authStateTask?.cancel()
    }

    private func observeAuthState() async {
        guard let client = supabase else { return }
        for await state in client.auth.authStateChanges {
            guard !Task.isCancelled else { return }
            if [.initialSession, .signedIn, .signedOut, .userUpdated].contains(state.event) {
                await MainActor.run {
                    self.session = state.session
                    self.otpSent = false
                    self.errorMessage = nil
                }
            }
        }
    }

    /// Send magic link to the given email.
    func signInWithOTP(email: String) async {
        guard let client = supabase else {
            errorMessage = "Supabase is not configured. Add SUPABASE_URL and SUPABASE_ANON_KEY to Info.plist."
            return
        }
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Please enter your email."
            return
        }
        isLoading = true
        errorMessage = nil
        infoMessage = nil
        otpSent = false
        defer { isLoading = false }
        do {
            let redirectTo = URL(string: "com.app.tiertap://login-callback")!
            try await client.auth.signInWithOTP(email: trimmed, redirectTo: redirectTo)
            otpSent = true
            infoMessage = "Check your inbox for the sign-in link."
        } catch {
            if let urlError = error as? URLError, urlError.code == .badURL {
                errorMessage = "Invalid URL (common in Simulator). Check SupabaseKeys.plist has a valid https URL."
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Create a new account using email + password.
    func signUpWithEmailPassword(email: String, password: String) async {
        guard let client = supabase else {
            errorMessage = "Supabase is not configured. Add SUPABASE_URL and SUPABASE_ANON_KEY to Info.plist."
            return
        }
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty else {
            errorMessage = "Please enter your email."
            return
        }
        guard !password.isEmpty else {
            errorMessage = "Please enter a password."
            return
        }

        isLoading = true
        errorMessage = nil
        infoMessage = nil
        otpSent = false
        defer { isLoading = false }

        do {
            _ = try await client.auth.signUp(
                email: trimmedEmail,
                password: password
            )
            // Depending on your Supabase email confirmation settings, this may immediately create a session
            // or require the user to confirm via email first. Either way, the auth state observer will keep
            // `session` in sync; we just show a helpful message here.
            infoMessage = "If required, check your email to confirm your TierTap account."
        } catch {
            if let urlError = error as? URLError, urlError.code == .badURL {
                errorMessage = "Invalid URL (common in Simulator). Check SupabaseKeys.plist has a valid https URL."
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Sign in using email + password for users who already created an account.
    func signInWithEmailPassword(email: String, password: String) async {
        guard let client = supabase else {
            errorMessage = "Supabase is not configured. Add SUPABASE_URL and SUPABASE_ANON_KEY to Info.plist."
            return
        }
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty else {
            errorMessage = "Please enter your email."
            return
        }
        guard !password.isEmpty else {
            errorMessage = "Please enter your password."
            return
        }

        isLoading = true
        errorMessage = nil
        infoMessage = nil
        otpSent = false
        defer { isLoading = false }

        do {
            let authSession = try await client.auth.signIn(
                email: trimmedEmail,
                password: password
            )
            session = authSession
        } catch {
            if let urlError = error as? URLError, urlError.code == .badURL {
                errorMessage = "Invalid URL (common in Simulator). Check SupabaseKeys.plist has a valid https URL."
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Handle OAuth and magic link callback (call from .onOpenURL).
    /// Uses the SDK’s session(from:) so the client persists the session and auth state updates.
    func handleOpenURL(_ url: URL) {
        guard url.scheme == "com.app.tiertap" else { return }
        guard let client = supabase else { return }
        Task {
            do {
                let authSession = try await client.auth.session(from: url)
                await MainActor.run {
                    self.session = authSession
                    self.otpSent = false
                    self.errorMessage = nil
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func signOut() {
        guard let client = supabase else { return }
        Task {
            try? await client.auth.signOut()
            await MainActor.run {
                session = nil
                otpSent = false
                errorMessage = nil
            }
        }
    }

    /// Sign in with Google via OAuth (opens in-app browser). Callback is handled by handleOpenURL.
    func signInWithGoogle() {
        guard let client = supabase else {
            errorMessage = "Supabase is not configured."
            return
        }
        isLoading = true
        errorMessage = nil
        let redirectTo = URL(string: "com.app.tiertap://login-callback")!
        Task {
            do {
                _ = try await client.auth.signInWithOAuth(provider: .google, redirectTo: redirectTo) { [weak self] webSession in
                    let provider = OAuthPresentationContextProvider()
                    webSession.presentationContextProvider = provider
                    // Use a fresh browser session each time so re-login after sign out works reliably.
                    webSession.prefersEphemeralWebBrowserSession = true
                    Task { @MainActor in
                        self?.oauthPresentationProvider = provider
                    }
                }
                await MainActor.run { self.isLoading = false }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    /// Sign in with Apple (native). Call from a view that has window access; uses key window if needed.
    func signInWithApple() {
        guard let client = supabase else {
            errorMessage = "Supabase is not configured."
            return
        }
        isLoading = true
        let rawNonce = randomNonceString()
        let hashedNonce = sha256(rawNonce)

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = hashedNonce

        let controller = ASAuthorizationController(authorizationRequests: [request])
        let delegate = AppleSignInDelegate(
            rawNonce: rawNonce,
            onSuccess: { [weak self] credential in
                Task { @MainActor in
                    await self?.handleAppleCredential(credential, client: client)
                }
            },
            onFailure: { [weak self] error in
                Task { @MainActor in
                    self?.errorMessage = error.localizedDescription
                    self?.isLoading = false
                }
            }
        )
        appleAuthDelegate = delegate
        controller.delegate = delegate
        controller.presentationContextProvider = delegate

        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        delegate.presentingWindow = window
        controller.performRequests()
    }

    private func handleAppleCredential(_ credential: ASAuthorizationAppleIDCredential, client: SupabaseClient) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let idTokenData = credential.identityToken,
              let idToken = String(data: idTokenData, encoding: .utf8) else {
            errorMessage = "Unable to get identity token from Apple."
            return
        }

        let rawNonce = appleAuthDelegate?.rawNonce ?? ""
        do {
            let authSession = try await client.auth.signInWithIdToken(
                credentials: .init(provider: .apple, idToken: idToken, nonce: rawNonce)
            )
            session = authSession

            // Apple only provides full name on first sign-in; save to user metadata
            if let nameComponents = credential.fullName {
                var fullName = [nameComponents.givenName, nameComponents.familyName]
                    .compactMap { $0 }
                    .joined(separator: " ")
                if fullName.isEmpty { fullName = nameComponents.givenName ?? nameComponents.familyName ?? "" }
                if !fullName.isEmpty {
                    try? await client.auth.update(user: .init(data: [
                        "full_name": .string(fullName),
                        "given_name": .string(nameComponents.givenName ?? ""),
                        "family_name": .string(nameComponents.familyName ?? "")
                    ]))
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        appleAuthDelegate = nil
    }

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz")
        var result = ""
        var remainingLength = length
        while remainingLength > 0 {
            let randoms: [UInt8] = (0 ..< 16).map { _ in UInt8.random(in: 0 ..< UInt8.max) }
            for random in randoms {
                if remainingLength == 0 { break }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        return result
    }

    private func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Sign in with Apple delegate
private final class AppleSignInDelegate: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    let rawNonce: String
    var presentingWindow: UIWindow?
    private let onSuccess: (ASAuthorizationAppleIDCredential) -> Void
    private let onFailure: (Error) -> Void

    init(rawNonce: String, onSuccess: @escaping (ASAuthorizationAppleIDCredential) -> Void, onFailure: @escaping (Error) -> Void) {
        self.rawNonce = rawNonce
        self.onSuccess = onSuccess
        self.onFailure = onFailure
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            onFailure(NSError(domain: "AuthStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid Apple credential"]))
            return
        }
        onSuccess(credential)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        if (error as NSError).code == ASAuthorizationError.canceled.rawValue {
            return // User cancelled, don't show error
        }
        onFailure(error)
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        if let window = presentingWindow { return window }
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        return keyWindow ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first!
    }
}

// MARK: - OAuth (Google) presentation context
private final class OAuthPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first!
    }
}
