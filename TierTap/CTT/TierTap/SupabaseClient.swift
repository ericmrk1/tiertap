import Foundation
import Supabase

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

    private static func string(forKey key: String) -> String? {
        guard let url = Bundle.main.url(forResource: keysPlistName, withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: Any],
              let value = dict[key] as? String else { return nil }
        return value
    }
}

/// Global Supabase client. Only valid when SupabaseConfig.isConfigured is true.
var supabase: SupabaseClient? {
    guard let url = SupabaseConfig.url, let key = SupabaseConfig.anonKey else { return nil }
    return SupabaseClient(supabaseURL: url, supabaseKey: key)
}
