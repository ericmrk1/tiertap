import CryptoKit
import SwiftUI

// MARK: - App language

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case english = "en"
    case chineseSimplified = "zh-Hans"
    case japanese = "ja"
    case korean = "ko"
    case vietnamese = "vi"
    case spanish = "es"
    case arabic = "ar"
    case hebrew = "he"
    case german = "de"
    case french = "fr"
    case hindi = "hi"

    var id: String { rawValue }

    /// Keys in `Strings.json` / `LocalizationCatalog`.
    var catalogCode: String { rawValue }

    /// Locale for formatters and `SwiftUI.Environment.locale`.
    var locale: Locale { Locale(identifier: rawValue) }

    var layoutDirection: LayoutDirection {
        switch self {
        case .arabic, .hebrew: return .rightToLeft
        default: return .leftToRight
        }
    }

    /// Shown in the language picker (each option in its own language).
    var pickerLabel: String {
        switch self {
        case .english: return "English"
        case .chineseSimplified: return "简体中文"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .vietnamese: return "Tiếng Việt"
        case .spanish: return "Español"
        case .arabic: return "العربية"
        case .hebrew: return "עברית"
        case .german: return "Deutsch"
        case .french: return "Français"
        case .hindi: return "हिन्दी"
        }
    }

    /// English name for Gemini / edge routing instructions.
    var englishNameForGemini: String {
        switch self {
        case .english: return "English"
        case .chineseSimplified: return "Simplified Chinese"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        case .vietnamese: return "Vietnamese"
        case .spanish: return "Spanish"
        case .arabic: return "Arabic"
        case .hebrew: return "Hebrew"
        case .german: return "German"
        case .french: return "French"
        case .hindi: return "Hindi"
        }
    }
}

// MARK: - Bundle JSON table

final class LocalizationCatalog: @unchecked Sendable {
    static let shared = LocalizationCatalog()

    private let lock = NSLock()
    private var table: [String: [String: String]] = [:]

    private init() {
        reloadFromBundle()
    }

    func reloadFromBundle() {
        guard let url = Bundle.main.url(forResource: "Strings", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: [String: String]].self, from: data)
        else {
            #if DEBUG
            print("[LocalizationCatalog] Missing or invalid Strings.json in bundle")
            #endif
            return
        }
        lock.lock()
        table = decoded
        lock.unlock()
    }

    func text(for key: String, language: AppLanguage, fallback: String?) -> String {
        let code = language.catalogCode
        lock.lock()
        let row = table[key]
        lock.unlock()
        if let row {
            if let v = row[code], !v.isEmpty { return v }
            if let en = row["en"], !en.isEmpty { return en }
            if let first = row.values.first(where: { !$0.isEmpty }) { return first }
        }
        return fallback ?? key
    }
}

// MARK: - Hash keys (must match scripts/tiertap_extract_l10n.py)

extension String {
    /// Stable lookup key for English source text.
    var tiertapL10nKey: String {
        let digest = SHA256.hash(data: Data(utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "ui." + String(hex.prefix(24))
    }
}

enum L10n {
    static func tr(_ english: String, language: AppLanguage) -> String {
        let key = english.tiertapL10nKey
        return LocalizationCatalog.shared.text(for: key, language: language, fallback: english)
    }
}

// MARK: - SwiftUI

private struct AppLanguageKey: EnvironmentKey {
    static var defaultValue: AppLanguage { .english }
}

extension EnvironmentValues {
    var appLanguage: AppLanguage {
        get { self[AppLanguageKey.self] }
        set { self[AppLanguageKey.self] = newValue }
    }
}

/// Static `Text` using the JSON string table and `appLanguage`.
struct L10nText: View {
    let english: String
    @Environment(\.appLanguage) private var language

    init(_ english: String) {
        self.english = english
    }

    var body: some View {
        Text(L10n.tr(english, language: language))
    }
}

extension View {
    /// Localized navigation title using `Strings.json` and `\.appLanguage`.
    func localizedNavigationTitle(_ english: String) -> some View {
        modifier(LocalizedNavigationTitleModifier(english: english))
    }
}

private struct LocalizedNavigationTitleModifier: ViewModifier {
    let english: String
    @Environment(\.appLanguage) private var appLanguage

    func body(content: Content) -> some View {
        content.navigationTitle(L10n.tr(english, language: appLanguage))
    }
}

/// Tab / toolbar label with SF Symbol.
struct LocalizedLabel: View {
    let title: String
    let systemImage: String
    @Environment(\.appLanguage) private var language

    var body: some View {
        Label {
            Text(L10n.tr(title, language: language))
        } icon: {
            Image(systemName: systemImage)
        }
    }
}

// MARK: - Gemini (client + edge)

enum GeminiPromptLanguage {
    /// JSON field stripped by `gemini-router` and prepended to the first user text part.
    static let preambleFieldName = "tierTapLanguagePreamble"

    static func instructionPreamble(for language: AppLanguage) -> String {
        if language == .english { return "" }
        let name = language.englishNameForGemini
        return """
        [TierTap language directive — follow strictly]
        Write all natural-language explanations, advice, headings, labels inside your reply, and the `reason` field text (when JSON allows prose) in \(name). Keep a natural \(name) style.
        When the user prompt requires an exact machine-readable token (only the word UNKNOWN, a bare integer with no extra text, or JSON with English keys exactly as specified), output those tokens/keys in English as instructed — do not translate JSON keys, UUIDs, or those special tokens.
        """
    }
}

/// Wraps a Gemini `contents` payload and optionally adds `tierTapLanguagePreamble` for the edge function.
struct GeminiProxyBody<Contents: Encodable>: Encodable {
    private let tierTapLanguagePreamble: String?
    private let contents: Contents

    init(contents: Contents, language: AppLanguage) {
        self.contents = contents
        let p = GeminiPromptLanguage.instructionPreamble(for: language)
        self.tierTapLanguagePreamble = p.isEmpty ? nil : p
    }

    enum CodingKeys: String, CodingKey {
        case tierTapLanguagePreamble
        case contents
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(contents, forKey: .contents)
        if let pre = tierTapLanguagePreamble {
            try c.encode(pre, forKey: .tierTapLanguagePreamble)
        }
    }
}
