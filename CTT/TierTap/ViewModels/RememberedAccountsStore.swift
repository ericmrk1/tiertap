import Foundation
import Supabase

/// How the user last signed in — used to pick the right re-auth flow on the login screen.
enum RememberedSignInMethod: String, Codable, CaseIterable {
    case apple
    case google
    case email
}

/// A TierTap account that previously signed in on this device (display only — no tokens stored).
struct RememberedTierTapAccount: Identifiable, Codable, Equatable {
    let id: UUID
    var email: String?
    var displayLabel: String
    var profileEmojis: String?
    var signInMethod: RememberedSignInMethod
    var lastUsedAt: Date

    var subtitle: String? {
        if let email, !email.isEmpty, email != displayLabel { return email }
        switch signInMethod {
        case .apple: return "Signed in with Apple"
        case .google: return "Signed in with Google"
        case .email: return nil
        }
    }
}

/// Persists recent Supabase accounts on this device for the signed-out login screen.
@MainActor
final class RememberedAccountsStore: ObservableObject {
    @Published private(set) var accounts: [RememberedTierTapAccount] = []

    private static let storageKey = "tiertap_remembered_accounts_v1"
    private static let maxAccounts = 5

    init() {
        load()
    }

    func recordAccount(from session: Auth.Session) {
        guard let account = Self.makeAccount(from: session) else { return }
        var updated = accounts.filter { $0.id != account.id }
        updated.insert(account, at: 0)
        if updated.count > Self.maxAccounts {
            updated = Array(updated.prefix(Self.maxAccounts))
        }
        accounts = updated
        save()
    }

    func removeAccount(id: UUID) {
        guard accounts.contains(where: { $0.id == id }) else { return }
        accounts.removeAll { $0.id == id }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else {
            accounts = []
            return
        }
        do {
            accounts = try JSONDecoder().decode([RememberedTierTapAccount].self, from: data)
        } catch {
            accounts = []
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private static func makeAccount(from session: Auth.Session) -> RememberedTierTapAccount? {
        let user = session.user
        let displayLabel = displayLabel(for: user)
        guard displayLabel != nil || user.email != nil else { return nil }

        return RememberedTierTapAccount(
            id: user.id,
            email: user.email,
            displayLabel: displayLabel ?? user.email ?? "TierTap account",
            profileEmojis: stringFromUserMetadata("profile_emojis", user: user),
            signInMethod: primarySignInMethod(for: user),
            lastUsedAt: Date()
        )
    }

    private static func displayLabel(for user: User) -> String? {
        if let custom = stringFromUserMetadata("display_name", user: user), !custom.isEmpty { return custom }
        if let full = stringFromUserMetadata("full_name", user: user), !full.isEmpty { return full }
        if let name = stringFromUserMetadata("name", user: user), !name.isEmpty { return name }
        let given = stringFromUserMetadata("given_name", user: user) ?? ""
        let family = stringFromUserMetadata("family_name", user: user) ?? ""
        let combined = [given, family].filter { !$0.isEmpty }.joined(separator: " ")
        if !combined.isEmpty { return combined }
        if let email = user.email, !email.isEmpty { return email }
        return nil
    }

    private static func stringFromUserMetadata(_ key: String, user: User) -> String? {
        if let s = user.userMetadata[key]?.stringValue, !s.isEmpty { return s }
        return nil
    }

    private static func primarySignInMethod(for user: User) -> RememberedSignInMethod {
        if let identities = user.identities {
            for identity in identities {
                let provider = identity.provider.lowercased()
                if provider.contains("apple") { return .apple }
                if provider.contains("google") { return .google }
            }
        }
        if let provider = user.appMetadata["provider"]?.stringValue?.lowercased() {
            if provider.contains("apple") { return .apple }
            if provider.contains("google") { return .google }
        }
        return .email
    }
}
