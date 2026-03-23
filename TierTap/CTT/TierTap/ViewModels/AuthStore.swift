import AuthenticationServices
import CryptoKit
import Foundation
import Supabase
import SwiftUI
import UIKit

/// Manages Supabase auth state for the Community tab. Sign in via magic link (email OTP) or Sign in with Apple.
@MainActor
final class AuthStore: ObservableObject {
    @Published private(set) var session: Auth.Session?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    /// Generic informational message for non-error auth states (e.g. "Check your email").
    @Published var infoMessage: String?
    @Published var otpSent = false

    /// On-disk JPEG for the profile avatar (Application Support). Not synced to Supabase metadata.
    @Published private(set) var localProfilePhoto: URL?

    private var authStateTask: Task<Void, Never>?
    private var appleAuthDelegate: AppleSignInDelegate?
    private var oauthPresentationProvider: OAuthPresentationContextProvider?
    /// Prevents concurrent `auth.update` calls that remove legacy `profile_photo_url` from metadata.
    private var profilePhotoMetadataWipeInFlight = false

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

    /// Public URL of the profile photo in the `avatars` bucket (`{userId}/avatar.jpg`).
    /// Intentionally **not** read from `user_metadata.profile_photo_url` so the JWT stays small.
    var userProfilePhotoURL: URL? {
        guard let client = supabase, let userId = session?.user.id else { return nil }
        let path = "\(userId)/avatar.jpg"
        return try? client.storage.from("avatars").getPublicURL(path: path)
    }

    /// Image loaded from `localProfilePhoto` when the file exists.
    var localProfilePhotoImage: UIImage? {
        guard let url = localProfilePhoto, url.isFileURL else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    /// Short label for UI: display name or "email@example.com" when no name is available.
    var signedInSummary: String? {
        if let name = userDisplayName, !name.isEmpty { return name }
        guard let email = session?.user.email, !email.isEmpty else { return nil }
        return email
    }

    /// Update profile display name and/or emojis in Supabase user metadata.
    /// To update the profile photo, call `uploadProfilePhoto(_:)` separately.
    func updateProfile(displayName: String?, emojis: String?) async {
        guard let client = supabase else { return }
        var data: [String: AnyJSON] = [:]
        if let name = displayName { data["display_name"] = .string(name) }
        if let e = emojis { data["profile_emojis"] = .string(e) }
        guard !data.isEmpty else { return }
        do {
            _ = try await client.auth.update(user: .init(data: data))
            if let newSession = try? await client.auth.session {
                await MainActor.run { session = newSession }
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    /// Upload a profile photo to Supabase Storage at `{userId}/avatar.jpg`.
    /// Does **not** write `profile_photo_url` (or any photo field) to user metadata — use
    /// ``userProfilePhotoURL`` for the deterministic public URL.
    ///
    /// - Parameter imageData: JPEG data for the profile photo (compress before calling).
    func uploadProfilePhoto(_ imageData: Data) async throws {
        guard let client = supabase else { return }
        guard let userId = session?.user.id else {
            throw AuthError.notSignedIn
        }

        let path = "\(userId)/avatar.jpg"

        // Upload to the `avatars` bucket (upsert = replace existing photo).
        _ = try await client.storage
            .from("avatars")
            .upload(
                path,
                data: imageData,
                options: FileOptions(
                    cacheControl: "3600",
                    contentType: "image/jpeg",
                    upsert: true
                )
            )
    }

    /// Remove the profile photo object from Storage only (no user metadata updates).
    func deleteProfilePhoto() async throws {
        guard let client = supabase else { return }
        guard let userId = session?.user.id else {
            throw AuthError.notSignedIn
        }

        let path = "\(userId)/avatar.jpg"
        _ = try? await client.storage.from("avatars").remove(paths: [path])
    }

    /// Writes JPEG data next to app support and sets `localProfilePhoto` to that file URL.
    func saveProfilePhotoLocally(_ data: Data) throws {
        guard let userId = session?.user.id else {
            throw AuthError.notSignedIn
        }
        let url = try localProfilePhotoFileURL(for: userId)
        try data.write(to: url, options: .atomic)
        localProfilePhoto = url
    }

    /// Removes the on-disk profile photo and clears `localProfilePhoto`.
    func deleteLocalProfilePhoto() throws {
        guard let userId = session?.user.id else {
            throw AuthError.notSignedIn
        }
        let url = try localProfilePhotoFileURL(for: userId)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        localProfilePhoto = nil
    }

    private func localProfilePhotoFileURL(for userId: UUID) throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent("TierTapProfilePhotos", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(userId.uuidString).jpg")
    }

    private func refreshLocalProfilePhotoFromDisk() {
        guard let userId = session?.user.id else {
            localProfilePhoto = nil
            return
        }
        guard let url = try? localProfilePhotoFileURL(for: userId),
              FileManager.default.fileExists(atPath: url.path) else {
            localProfilePhoto = nil
            return
        }
        localProfilePhoto = url
    }

    /// Removes legacy `profile_photo_url` from Supabase `user_metadata` so it is not embedded in the JWT.
    private func scheduleWipeProfilePhotoURLFromMetadataIfNeeded() {
        guard let client = supabase, let user = session?.user else { return }
        guard user.userMetadata["profile_photo_url"] != nil else { return }
        guard !profilePhotoMetadataWipeInFlight else { return }
        profilePhotoMetadataWipeInFlight = true
        Task {
            do {
                _ = try await client.auth.update(user: .init(data: [
                    "profile_photo_url": .null
                ]))
                if let newSession = try? await client.auth.session {
                    await MainActor.run { self.session = newSession }
                }
            } catch {
                // If the server rejects null, the next auth event can retry; inFlight prevents a tight loop.
            }
            await MainActor.run { self.profilePhotoMetadataWipeInFlight = false }
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
                    self.refreshLocalProfilePhotoFromDisk()
                    self.scheduleWipeProfilePhotoURLFromMetadataIfNeeded()
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
            try await client.auth.signInWithOTP(email: trimmed, redirectTo: SupabaseConfig.authRedirectURL)
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

    /// Handle OAuth and magic link callback (call from `.onOpenURL`).
    /// Expects the custom TierTap URL scheme from `SupabaseConfig.authRedirectURL`, not a web localhost redirect.
    func handleOpenURL(_ url: URL) {
        guard let scheme = SupabaseConfig.authRedirectURL.scheme,
              url.scheme?.caseInsensitiveCompare(scheme) == .orderedSame else { return }
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
        let userId = session?.user.id
        Task {
            if let userId, let url = try? localProfilePhotoFileURL(for: userId),
               FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }
            try? await client.auth.signOut()
            await MainActor.run {
                session = nil
                localProfilePhoto = nil
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
        Task {
            do {
                _ = try await client.auth.signInWithOAuth(provider: .google, redirectTo: SupabaseConfig.authRedirectURL) { [weak self] webSession in
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

            // Apple only provides full name on first sign-in; save to user metadata.
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

// MARK: - Auth Errors

enum AuthError: LocalizedError {
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "You must be signed in to perform this action."
        }
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
