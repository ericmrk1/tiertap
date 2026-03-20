import Foundation
import Supabase
import CoreLocation

/// When true, a specific developer override code in Settings can unlock
/// all subscription-gated functionality without requiring a live StoreKit subscription.
let SUBSCRIPTION_OVERRIDE_FLAG: Bool = true

/// Shared Supabase client. Keys are read from SupabaseKeys.plist (gitignored).
/// Copy SupabaseKeys.example.plist to SupabaseKeys.plist and add your project URL and anon key.
enum SupabaseConfig {
    private static let keysPlistName = "SupabaseKeys"

    static var url: URL? {
        guard let s = string(forKey: "SUPABASE_URL"), !s.isEmpty else { return nil }
        return URL(string: s)
    }

    static var anonKey: String? {
        guard let s = string(forKey: "SUPABASE_ANON_KEY"), !s.isEmpty else { return nil }
        return s
    }

    static var isConfigured: Bool {
        url != nil && anonKey != nil
    }

    /// Redirect for magic links and OAuth. Must be listed under Supabase Auth → URL Configuration → **Redirect URLs**.
    /// Use this custom scheme for TierTap — do not rely on `http://localhost` as the email link target.
    static var authRedirectURL: URL {
        URL(string: "com.app.tiertap://login-callback")!
    }

    /// True when the app is running as a TestFlight build (on device). Used to relax limits for testers.
    static var isTestFlight: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return currentDistributionChannel() == .testFlight
        #endif
    }

    private static func string(forKey key: String) -> String? {
        guard let url = Bundle.main.url(forResource: keysPlistName, withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: Any],
              let value = dict[key] as? String else { return nil }
        return value
    }
}

/// URLSession used for Supabase in the simulator. The simulator can report URL errors (e.g. -1000)
/// when auth redirect URLs (custom schemes) appear in query params; using a custom session with
/// TLS 1.2 max can improve stability (see supabase/supabase-swift#708).
private let simulatorURLSession: URLSession = {
    let config = URLSessionConfiguration.default
    #if targetEnvironment(simulator)
    if #available(iOS 15.0, *) {
        config.tlsMaximumSupportedProtocolVersion = .TLSv12
    }
    #endif
    return URLSession(configuration: config)
}()

/// Global Supabase client instance, created once so that auth state,
/// sessions, and storage are shared consistently across the app.
let supabase: SupabaseClient? = {
    guard let url = SupabaseConfig.url, let key = SupabaseConfig.anonKey else { return nil }
    let options: SupabaseClientOptions
    #if targetEnvironment(simulator)
    options = SupabaseClientOptions(
        auth: .init(emitLocalSessionAsInitialSession: true),
        global: .init(headers: [:], session: simulatorURLSession)
    )
    #else
    options = SupabaseClientOptions(auth: .init(emitLocalSessionAsInitialSession: true))
    #endif
    return SupabaseClient(
        supabaseURL: url,
        supabaseKey: key,
        options: options
    )
}()

// MARK: - App distribution detection

private enum AppDistributionChannel {
    case appStore
    case testFlight
    case development
}

private func currentDistributionChannel() -> AppDistributionChannel {
    #if targetEnvironment(simulator)
    return .development
    #else
    let receiptURL = Bundle.main.appStoreReceiptURL
    let receiptName = receiptURL?.lastPathComponent ?? ""
    let hasEmbeddedProvision = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision") != nil

    if receiptName == "sandboxReceipt" {
        return hasEmbeddedProvision ? .development : .testFlight
    } else {
        return .appStore
    }
    #endif
}

/// Returns true when Supabase should use the `_Test` tables.
/// This is the case for TestFlight builds and when running in the simulator.
private func shouldUseTestSupabaseTables() -> Bool {
    #if targetEnvironment(simulator)
    return true
    #else
    return currentDistributionChannel() == .testFlight
    #endif
}

enum SupabaseTables {
    /// Table for community table game posts.
    /// Uses a separate `_Test` table when running in TestFlight or the simulator.
    static var tableGamePosts: String {
        return shouldUseTestSupabaseTables() ? "TableGamePosts_Test" : "TableGamePosts"
    }

    /// Master list of table games (used to power game pickers).
    /// Uses a separate `_Test` table when running in TestFlight or the simulator.
    static var tableGames: String {
        return shouldUseTestSupabaseTables() ? "TableGames_Test" : "TableGames"
    }

    /// Known casino locations chosen by the user.
    /// Uses a separate `_Test` table when running in TestFlight or the simulator.
    static var casinoLocations: String {
        return shouldUseTestSupabaseTables() ? "CasinoLocations_Test" : "CasinoLocations"
    }
}

// MARK: - Supabase TableGames helpers

private struct TableGameRow: Codable {
    let id: Int64?
    let created_at: Date?
    let game_id: UUID?
    let name: String?
    let alias: String?
}

enum TableGamesAPI {
    /// Load distinct game names from Supabase. Returns empty array on any failure.
    static func loadDistinctNames() async -> [String] {
        guard let client = supabase else { return [] }
        do {
            let data = try await client.database
                .from(SupabaseTables.tableGames)
                .select("name")
                .execute()
                .data

            let rows = try JSONDecoder().decode([TableGameRow].self, from: data)
            let names = rows.compactMap { $0.name?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return Array(Set(names)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        } catch {
            return []
        }
    }
}

// MARK: - Supabase CasinoLocations helpers

private struct CasinoLocationRow: Codable {
    let id: Int64?
    let created_at: Date?
    let name: String?
    let address: [String: String]?
    let country: String?
    let latitude: Double?
    let longitude: Double?
    let `public`: Bool?
    let user_id: UUID?
}

enum CasinoLocationsAPI {
    /// Best-effort insert of a picked casino with rich metadata. Skips insert without valid GPS coordinates.
    static func insertPicked(
        name: String,
        addressComponents: [String: String]?,
        coordinate: CLLocationCoordinate2D?,
        isPublic: Bool,
        userId: UUID?
    ) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let client = supabase else { return }
        guard let coordinate, CLLocationCoordinate2DIsValid(coordinate) else { return }

        let addressDict = addressComponents ?? [:]

        // Prefer ISO country code, fall back to human-readable country if present.
        let countryValue = addressDict["countryCode"] ?? addressDict["country"]

        let payload = CasinoLocationRow(
            id: nil,
            created_at: nil,
            name: trimmed,
            address: addressDict.isEmpty ? nil : addressDict,
            country: countryValue,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            public: isPublic,
            user_id: userId
        )

        Task {
            do {
                _ = try await client.database
                    .from(SupabaseTables.casinoLocations)
                    .insert(payload)
                    .execute()
            } catch {
                // Best-effort only; ignore failures.
            }
        }
    }
}
