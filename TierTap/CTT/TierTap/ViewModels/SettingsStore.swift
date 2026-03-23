import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#endif

private let keyBankroll = "ctt_bankroll"
private let keyUnitSize = "ctt_unit_size"
private let keyTargetAverage = "ctt_target_average"
private let keyCurrencyCode = "ctt_currency_code"
private let keyAppleSignedIn = "ctt_apple_signed_in"
private let keyGoogleSignedIn = "ctt_google_signed_in"
private let keyCommonDenominations = "ctt_common_denominations"
private let keyUseEighteenX = "ctt_use_eighteen_x"
private let keyFavoriteGames = "ctt_favorite_games"
private let keyFavoriteCasinos = "ctt_favorite_casinos"
private let keyPrimaryColorName = "ctt_primary_color_name"
private let keySecondaryColorName = "ctt_secondary_color_name"
private let keyPrimaryColorHex = "ctt_primary_color_hex"
private let keySecondaryColorHex = "ctt_secondary_color_hex"
private let keySelectedLocationFilter = "ctt_selected_location_filter"
private let keyThemePresets = "ctt_theme_presets"
private let keyPromptSessionMood = "ctt_prompt_session_mood"
private let keyAITone = "ctt_ai_tone"
private let keyAICallsDate = "ctt_ai_calls_date"
private let keyAICallsCount = "ctt_ai_calls_count"
private let keyEnableCasinoFeedback = "ctt_enable_casino_feedback"
private let keySoundProfile = "ctt_sound_profile"
private let keySubscriptionOverrideCode = "ctt_subscription_override_code"
private let keyDefaultGameCategory = "ctt_default_game_category"

struct ThemePreset: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var primaryHex: String
    var secondaryHex: String
}

/// Supported currency for bankroll, units, and money displays.
/// Backed by a 3-letter ISO code, a primary symbol, and an optional country/region name.
struct Currency: Identifiable, Codable, Equatable {
    let id: String
    let code: String
    let symbol: String
    let name: String
    let country: String?

    init(code: String, symbol: String, name: String, country: String? = nil) {
        self.id = code
        self.code = code
        self.symbol = symbol
        self.name = name
        self.country = country
    }
}

extension Currency {
    static let usd = Currency(code: "USD", symbol: "$", name: "US Dollar", country: "United States")

    /// Master list of currencies shown in the picker.
    /// Includes major and many minor/region-specific currencies.
    static let all: [Currency] = [
        // North America
        .init(code: "USD", symbol: "$", name: "US Dollar", country: "United States"),
        .init(code: "CAD", symbol: "$", name: "Canadian Dollar", country: "Canada"),
        .init(code: "MXN", symbol: "$", name: "Mexican Peso", country: "Mexico"),
        .init(code: "GTQ", symbol: "Q", name: "Quetzal", country: "Guatemala"),
        .init(code: "CRC", symbol: "₡", name: "Costa Rican Colón", country: "Costa Rica"),
        .init(code: "HNL", symbol: "L", name: "Lempira", country: "Honduras"),
        .init(code: "NIO", symbol: "C", name: "Córdoba", country: "Nicaragua"),
        .init(code: "PAB", symbol: "B", name: "Balboa", country: "Panama"),
        .init(code: "DOP", symbol: "$", name: "Dominican Peso", country: "Dominican Republic"),
        .init(code: "JMD", symbol: "$", name: "Jamaican Dollar", country: "Jamaica"),
        .init(code: "BBD", symbol: "$", name: "Barbadian Dollar", country: "Barbados"),
        .init(code: "TTD", symbol: "$", name: "Trinidad & Tobago Dollar", country: "Trinidad and Tobago"),

        // South America
        .init(code: "BRL", symbol: "R", name: "Brazilian Real", country: "Brazil"),
        .init(code: "ARS", symbol: "$", name: "Argentine Peso", country: "Argentina"),
        .init(code: "CLP", symbol: "$", name: "Chilean Peso", country: "Chile"),
        .init(code: "COP", symbol: "$", name: "Colombian Peso", country: "Colombia"),
        .init(code: "PEN", symbol: "S", name: "Sol", country: "Peru"),
        .init(code: "UYU", symbol: "$", name: "Uruguayan Peso", country: "Uruguay"),
        .init(code: "PYG", symbol: "₲", name: "Guaraní", country: "Paraguay"),
        .init(code: "BOB", symbol: "B", name: "Boliviano", country: "Bolivia"),

        // Europe
        .init(code: "EUR", symbol: "€", name: "Euro", country: "Eurozone"),
        .init(code: "GBP", symbol: "£", name: "Pound Sterling", country: "United Kingdom"),
        .init(code: "CHF", symbol: "₣", name: "Swiss Franc", country: "Switzerland"),
        .init(code: "NOK", symbol: "k", name: "Norwegian Krone", country: "Norway"),
        .init(code: "SEK", symbol: "k", name: "Swedish Krona", country: "Sweden"),
        .init(code: "DKK", symbol: "k", name: "Danish Krone", country: "Denmark"),
        .init(code: "PLN", symbol: "z", name: "Złoty", country: "Poland"),
        .init(code: "CZK", symbol: "K", name: "Czech Koruna", country: "Czech Republic"),
        .init(code: "HUF", symbol: "F", name: "Forint", country: "Hungary"),
        .init(code: "RON", symbol: "L", name: "Romanian Leu", country: "Romania"),
        .init(code: "RSD", symbol: "дин", name: "Serbian Dinar", country: "Serbia"),
        .init(code: "HRK", symbol: "k", name: "Kuna", country: "Croatia"),
        .init(code: "ISK", symbol: "k", name: "Icelandic Króna", country: "Iceland"),
        .init(code: "UAH", symbol: "₴", name: "Hryvnia", country: "Ukraine"),
        .init(code: "RUB", symbol: "₽", name: "Russian Ruble", country: "Russia"),
        .init(code: "TRY", symbol: "₺", name: "Turkish Lira", country: "Türkiye"),

        // Middle East & Africa
        .init(code: "AED", symbol: "د", name: "UAE Dirham", country: "United Arab Emirates"),
        .init(code: "SAR", symbol: "ر", name: "Saudi Riyal", country: "Saudi Arabia"),
        .init(code: "QAR", symbol: "ر", name: "Qatari Riyal", country: "Qatar"),
        .init(code: "KWD", symbol: "د", name: "Kuwaiti Dinar", country: "Kuwait"),
        .init(code: "OMR", symbol: "ر", name: "Omani Rial", country: "Oman"),
        .init(code: "BHD", symbol: "د", name: "Bahraini Dinar", country: "Bahrain"),
        .init(code: "EGP", symbol: "£", name: "Egyptian Pound", country: "Egypt"),
        .init(code: "NGN", symbol: "₦", name: "Naira", country: "Nigeria"),
        .init(code: "GHS", symbol: "₵", name: "Cedi", country: "Ghana"),
        .init(code: "KES", symbol: "S", name: "Kenyan Shilling", country: "Kenya"),
        .init(code: "TZS", symbol: "S", name: "Tanzanian Shilling", country: "Tanzania"),
        .init(code: "UGX", symbol: "S", name: "Ugandan Shilling", country: "Uganda"),
        .init(code: "ZAR", symbol: "R", name: "Rand", country: "South Africa"),
        .init(code: "MAD", symbol: "د", name: "Moroccan Dirham", country: "Morocco"),

        // Asia-Pacific
        .init(code: "JPY", symbol: "¥", name: "Yen", country: "Japan"),
        .init(code: "CNY", symbol: "¥", name: "Yuan", country: "China"),
        .init(code: "HKD", symbol: "$", name: "Hong Kong Dollar", country: "Hong Kong"),
        .init(code: "TWD", symbol: "$", name: "New Taiwan Dollar", country: "Taiwan"),
        .init(code: "KRW", symbol: "₩", name: "Won", country: "South Korea"),
        .init(code: "SGD", symbol: "$", name: "Singapore Dollar", country: "Singapore"),
        .init(code: "THB", symbol: "฿", name: "Baht", country: "Thailand"),
        .init(code: "MYR", symbol: "R", name: "Ringgit", country: "Malaysia"),
        .init(code: "IDR", symbol: "R", name: "Rupiah", country: "Indonesia"),
        .init(code: "PHP", symbol: "₱", name: "Philippine Peso", country: "Philippines"),
        .init(code: "VND", symbol: "₫", name: "Dong", country: "Vietnam"),
        .init(code: "INR", symbol: "₹", name: "Indian Rupee", country: "India"),
        .init(code: "PKR", symbol: "₨", name: "Pakistani Rupee", country: "Pakistan"),
        .init(code: "BDT", symbol: "৳", name: "Taka", country: "Bangladesh"),
        .init(code: "LKR", symbol: "₨", name: "Sri Lankan Rupee", country: "Sri Lanka"),
        .init(code: "NPR", symbol: "₨", name: "Nepalese Rupee", country: "Nepal"),
        .init(code: "AUD", symbol: "$", name: "Australian Dollar", country: "Australia"),
        .init(code: "NZD", symbol: "$", name: "New Zealand Dollar", country: "New Zealand"),
        .init(code: "FJD", symbol: "$", name: "Fijian Dollar", country: "Fiji"),
        .init(code: "PGK", symbol: "K", name: "Kina", country: "Papua New Guinea"),

        // Crypto-style/common virtual currencies (for convenience; non-fiat)
        .init(code: "BTC", symbol: "₿", name: "Bitcoin", country: nil),
        .init(code: "ETH", symbol: "Ξ", name: "Ethereum", country: nil),
        .init(code: "USDT", symbol: "₮", name: "Tether", country: nil)
    ]

    /// Find a currency by ISO code, defaulting to USD if not present.
    static func byCode(_ code: String) -> Currency {
        all.first { $0.code == code } ?? .usd
    }
}

/// Recorded bankroll reset (date and new value). Used for bankroll-over-time graph and history.
struct BankrollResetEvent: Codable, Equatable {
    let date: Date
    let value: Int
}

final class SettingsStore: ObservableObject {
    @Published var bankroll: Int {
        didSet { UserDefaults.standard.set(bankroll, forKey: keyBankroll) }
    }

    /// Resets of the bankroll (date and new value). Stored in dedicated SQLite DB for analytics.
    @Published var bankrollResets: [BankrollResetEvent] = []
    @Published var unitSize: Int {
        didSet { UserDefaults.standard.set(unitSize, forKey: keyUnitSize) }
    }

    /// Selected currency for bankroll, unit size, and monetary amounts (ISO code; default USD).
    @Published var currencyCode: String {
        didSet { UserDefaults.standard.set(currencyCode, forKey: keyCurrencyCode) }
    }
    /// Target average win per session ($). Nil = not set.
    @Published var targetAveragePerSession: Double? {
        didSet {
            if let v = targetAveragePerSession {
                UserDefaults.standard.set(v, forKey: keyTargetAverage)
            } else {
                UserDefaults.standard.removeObject(forKey: keyTargetAverage)
            }
        }
    }
    @Published var isAppleSignedIn: Bool {
        didSet { UserDefaults.standard.set(isAppleSignedIn, forKey: keyAppleSignedIn) }
    }
    @Published var isGoogleSignedIn: Bool {
        didSet { UserDefaults.standard.set(isGoogleSignedIn, forKey: keyGoogleSignedIn) }
    }

    /// Base quick-selection denominations (e.g., [20, 100, 500, 1000, 10000]).
    @Published var commonDenominations: [Int] {
        didSet { UserDefaults.standard.set(commonDenominations, forKey: keyCommonDenominations) }
    }

    /// When true, quick-selection denominations are multiplied by 18 for $18 increment style play.
    @Published var useEighteenXMultipliers: Bool {
        didSet { UserDefaults.standard.set(useEighteenXMultipliers, forKey: keyUseEighteenX) }
    }

    /// User-favorited casino games shown on the main game grid.
    @Published var favoriteGames: [String] {
        didSet { UserDefaults.standard.set(favoriteGames, forKey: keyFavoriteGames) }
    }

    /// User-favorited casino locations for quick selection.
    @Published var favoriteCasinos: [String] {
        didSet { UserDefaults.standard.set(favoriteCasinos, forKey: keyFavoriteCasinos) }
    }

    /// Default game category to show in game pickers and analytics (Table or Poker).
    @Published var defaultGameCategory: SessionGameCategory {
        didSet { UserDefaults.standard.set(defaultGameCategory.rawValue, forKey: keyDefaultGameCategory) }
    }

    /// Optional shared location filter used across History/Analytics.
    @Published var selectedLocationFilter: String? {
        didSet {
            if let value = selectedLocationFilter, !value.isEmpty {
                UserDefaults.standard.set(value, forKey: keySelectedLocationFilter)
            } else {
                UserDefaults.standard.removeObject(forKey: keySelectedLocationFilter)
            }
        }
    }

    /// Stored names for primary/secondary theme colors.
    @Published var primaryColorName: String {
        didSet { UserDefaults.standard.set(primaryColorName, forKey: keyPrimaryColorName) }
    }
    @Published var secondaryColorName: String {
        didSet { UserDefaults.standard.set(secondaryColorName, forKey: keySecondaryColorName) }
    }

    /// Stored hex strings for primary/secondary theme colors (takes precedence over name when present).
    @Published var primaryColorHex: String? {
        didSet {
            if let hex = primaryColorHex {
                UserDefaults.standard.set(hex, forKey: keyPrimaryColorHex)
            } else {
                UserDefaults.standard.removeObject(forKey: keyPrimaryColorHex)
            }
        }
    }
    @Published var secondaryColorHex: String? {
        didSet {
            if let hex = secondaryColorHex {
                UserDefaults.standard.set(hex, forKey: keySecondaryColorHex)
            } else {
                UserDefaults.standard.removeObject(forKey: keySecondaryColorHex)
            }
        }
    }

    /// Saved theme presets (built-in + user-defined).
    @Published var themePresets: [ThemePreset] {
        didSet {
            if let data = try? JSONEncoder().encode(themePresets) {
                UserDefaults.standard.set(data, forKey: keyThemePresets)
            }
        }
    }

    /// When true (default), show the session mood picker after ending a session. When false, skip the emotion grid.
    @Published var promptSessionMood: Bool {
        didSet { UserDefaults.standard.set(promptSessionMood, forKey: keyPromptSessionMood) }
    }

    /// When true (default), play casino-style chimes and haptics for key actions like check-in, buy-ins, closing out, and sharing.
    @Published var enableCasinoFeedback: Bool {
        didSet { UserDefaults.standard.set(enableCasinoFeedback, forKey: keyEnableCasinoFeedback) }
    }

    enum SoundProfile: String, CaseIterable, Identifiable, Codable {
        case classicCasino
        case softChimes
        case arcadeLights

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .classicCasino: return "Classic Casino"
            case .softChimes: return "Soft Chimes"
            case .arcadeLights: return "Arcade Lights"
            }
        }
    }

    /// Selected sound profile, which controls which group of external sound files are used for casino feedback.
    @Published var soundProfile: SoundProfile {
        didSet { UserDefaults.standard.set(soundProfile.rawValue, forKey: keySoundProfile) }
    }

    /// Developer override code for bypassing subscription checks (when enabled in code).
    @Published var subscriptionOverrideCode: String {
        didSet { UserDefaults.standard.set(subscriptionOverrideCode, forKey: keySubscriptionOverrideCode) }
    }

    enum AITone: String, CaseIterable, Identifiable, Codable {
        case sarcastic
        case scientific
        case funny
        case serious
        case business

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .sarcastic: return "Sarcastic"
            case .scientific: return "Scientific"
            case .funny: return "Funny"
            case .serious: return "Serious"
            case .business: return "Business"
            }
        }

        var promptLabel: String {
            switch self {
            case .sarcastic: return "a lightly sarcastic, playful tone"
            case .scientific: return "a precise, scientific tone with clear references to probabilities and expectations"
            case .funny: return "a humorous, light, casino-savvy tone"
            case .serious: return "a calm, serious coaching tone"
            case .business: return "a concise, business-style tone focused on numbers"
            }
        }
    }

    @Published var aiTone: AITone {
        didSet { UserDefaults.standard.set(aiTone.rawValue, forKey: keyAITone) }
    }

    /// Daily AI usage tracking for the free tier.
    @Published private(set) var aiCallsToday: Int
    @Published private(set) var aiCallsDate: Date

    /// Maximum number of AI calls allowed per day on the free tier. Higher on TestFlight for testers.
    var maxAICallsPerDay: Int {
        SupabaseConfig.isTestFlight ? 20 : 5
    }

    /// Remaining AI calls the user can make today on the free tier.
    var remainingAICallsToday: Int {
        max(0, maxAICallsPerDay - aiCallsToday)
    }

    /// True when the hard-coded override flag is on *and* the user-entered code matches the expected value.
    var isSubscriptionOverrideActive: Bool {
        guard SUBSCRIPTION_OVERRIDE_FLAG else { return false }
        return Int(subscriptionOverrideCode) == 1234567
    }

    init() {
        let b = UserDefaults.standard.integer(forKey: keyBankroll)
        self.bankroll = b > 0 ? b : 2000
        self.bankrollResets = BankrollDatabase.shared.fetchResets()
        let u = UserDefaults.standard.integer(forKey: keyUnitSize)
        self.unitSize = u > 0 ? u : 50
        let storedCurrency = UserDefaults.standard.string(forKey: keyCurrencyCode) ?? Currency.usd.code
        self.currencyCode = Currency.byCode(storedCurrency).code
        if let v = UserDefaults.standard.object(forKey: keyTargetAverage) as? Double {
            self.targetAveragePerSession = v
        } else {
            self.targetAveragePerSession = nil
        }
        self.isAppleSignedIn = UserDefaults.standard.bool(forKey: keyAppleSignedIn)
        self.isGoogleSignedIn = UserDefaults.standard.bool(forKey: keyGoogleSignedIn)
        if let storedDenoms = UserDefaults.standard.array(forKey: keyCommonDenominations) as? [Int],
           !storedDenoms.isEmpty {
            self.commonDenominations = storedDenoms
        } else {
            self.commonDenominations = [20, 100, 500, 1000, 10_000]
        }
        self.useEighteenXMultipliers = UserDefaults.standard.bool(forKey: keyUseEighteenX)
        self.favoriteGames = UserDefaults.standard.stringArray(forKey: keyFavoriteGames) ?? []
        self.favoriteCasinos = UserDefaults.standard.stringArray(forKey: keyFavoriteCasinos) ?? []
        if let raw = UserDefaults.standard.string(forKey: keyDefaultGameCategory),
           let cat = SessionGameCategory(rawValue: raw) {
            self.defaultGameCategory = cat
        } else {
            self.defaultGameCategory = .table
        }
        self.primaryColorName = UserDefaults.standard.string(forKey: keyPrimaryColorName) ?? "black"
        self.secondaryColorName = UserDefaults.standard.string(forKey: keySecondaryColorName) ?? "blue"
        self.primaryColorHex = UserDefaults.standard.string(forKey: keyPrimaryColorHex)
        self.secondaryColorHex = UserDefaults.standard.string(forKey: keySecondaryColorHex)
        self.selectedLocationFilter = UserDefaults.standard.string(forKey: keySelectedLocationFilter)

        if let data = UserDefaults.standard.data(forKey: keyThemePresets),
           let decoded = try? JSONDecoder().decode([ThemePreset].self, from: data),
           !decoded.isEmpty {
            self.themePresets = decoded
        } else {
            self.themePresets = []
        }
        if UserDefaults.standard.object(forKey: keyPromptSessionMood) != nil {
            self.promptSessionMood = UserDefaults.standard.bool(forKey: keyPromptSessionMood)
        } else {
            self.promptSessionMood = true
        }
        if UserDefaults.standard.object(forKey: keyEnableCasinoFeedback) != nil {
            self.enableCasinoFeedback = UserDefaults.standard.bool(forKey: keyEnableCasinoFeedback)
        } else {
            self.enableCasinoFeedback = true
        }
        if let storedProfile = UserDefaults.standard.string(forKey: keySoundProfile),
           let profile = SoundProfile(rawValue: storedProfile) {
            self.soundProfile = profile
        } else {
            self.soundProfile = .classicCasino
        }
        if let storedTone = UserDefaults.standard.string(forKey: keyAITone),
           let tone = AITone(rawValue: storedTone) {
            self.aiTone = tone
        } else {
            self.aiTone = .sarcastic
        }

        self.subscriptionOverrideCode = UserDefaults.standard.string(forKey: keySubscriptionOverrideCode) ?? ""

        // AI usage tracking (default to "today" with zero calls if nothing stored).
        let calendar = Calendar.current
        let storedDate = UserDefaults.standard.object(forKey: keyAICallsDate) as? Date
        let today = calendar.startOfDay(for: Date())
        if let storedDate = storedDate,
           calendar.isDate(storedDate, inSameDayAs: today) {
            self.aiCallsDate = storedDate
            let storedCount = UserDefaults.standard.integer(forKey: keyAICallsCount)
            self.aiCallsToday = max(0, storedCount)
        } else {
            self.aiCallsDate = today
            self.aiCallsToday = 0
            UserDefaults.standard.set(today, forKey: keyAICallsDate)
            UserDefaults.standard.set(0, forKey: keyAICallsCount)
        }
        if self.themePresets.isEmpty {
            let defaults: [ThemePreset] = [
                ThemePreset(id: UUID(), name: "Casino Blue", primaryHex: Self.hexString(from: .black), secondaryHex: Self.hexString(from: .blue)),
                ThemePreset(id: UUID(), name: "Apple Standard", primaryHex: Self.hexString(from: .blue), secondaryHex: Self.hexString(from: .teal)),
                ThemePreset(id: UUID(), name: "Emerald Night", primaryHex: Self.hexString(from: .green), secondaryHex: Self.hexString(from: .teal)),
                ThemePreset(id: UUID(), name: "Royal Blue", primaryHex: Self.hexString(from: .indigo), secondaryHex: Self.hexString(from: .blue)),
                ThemePreset(id: UUID(), name: "Sunset", primaryHex: Self.hexString(from: .orange), secondaryHex: Self.hexString(from: .pink)),
                ThemePreset(id: UUID(), name: "Gold Rush", primaryHex: Self.hexString(from: .yellow), secondaryHex: Self.hexString(from: .orange)),
                ThemePreset(id: UUID(), name: "Purple Royale", primaryHex: Self.hexString(from: .purple), secondaryHex: Self.hexString(from: .blue)),
                ThemePreset(id: UUID(), name: "Ocean Floor", primaryHex: Self.hexString(from: .teal), secondaryHex: Self.hexString(from: .blue)),
                ThemePreset(id: UUID(), name: "Vegas Neon", primaryHex: Self.hexString(from: .pink), secondaryHex: Self.hexString(from: .green)),
                ThemePreset(id: UUID(), name: "Midnight", primaryHex: Self.hexString(from: .indigo), secondaryHex: Self.hexString(from: .teal)),
                ThemePreset(id: UUID(), name: "High Roller", primaryHex: Self.hexString(from: .green), secondaryHex: Self.hexString(from: .yellow)),
                ThemePreset(id: UUID(), name: "Ice", primaryHex: Self.hexString(from: .mint), secondaryHex: Self.hexString(from: .blue))
            ]
            self.themePresets = defaults
        }
    }

    // MARK: - AI usage helpers

    /// Reset the AI call counter if the stored date is not today.
    private func resetAICallCounterIfNeeded(referenceDate: Date = Date()) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: referenceDate)
        if !calendar.isDate(aiCallsDate, inSameDayAs: today) {
            aiCallsDate = today
            aiCallsToday = 0
            UserDefaults.standard.set(today, forKey: keyAICallsDate)
            UserDefaults.standard.set(0, forKey: keyAICallsCount)
        }
    }

    /// Whether the user can make another AI call today on the free tier.
    func canUseAI() -> Bool {
        if isSubscriptionOverrideActive { return true }
        #if targetEnvironment(simulator)
        // Do not enforce AI limits in the simulator so development is not blocked.
        return true
        #else
        resetAICallCounterIfNeeded()
        return aiCallsToday < maxAICallsPerDay
        #endif
    }

    /// Record a successful AI call usage.
    func registerAICall() {
        #if targetEnvironment(simulator)
        // Skip counting AI calls in the simulator.
        return
        #else
        if isSubscriptionOverrideActive { return }
        resetAICallCounterIfNeeded()
        guard aiCallsToday < maxAICallsPerDay else { return }
        aiCallsToday += 1
        UserDefaults.standard.set(aiCallsDate, forKey: keyAICallsDate)
        UserDefaults.standard.set(aiCallsToday, forKey: keyAICallsCount)
        #endif
    }

    /// Record a bankroll reset to a new value (e.g. from Bankroll screen). Updates `bankroll` and persists to SQLite.
    func resetBankroll(to newValue: Int) {
        bankroll = newValue
        let event = BankrollResetEvent(date: Date(), value: newValue)
        BankrollDatabase.shared.insertReset(date: event.date, value: event.value)
        bankrollResets = BankrollDatabase.shared.fetchResets()
    }

    // MARK: - Derived helpers

    /// Currently selected currency details.
    var currency: Currency {
        Currency.byCode(currencyCode)
    }

    /// Convenience access to the selected currency's symbol.
    var currencySymbol: String {
        currency.symbol
    }

    /// Human-readable label for use in pickers and summaries.
    var currencyDisplayLabel: String {
        if let country = currency.country {
            return "\(currency.code) \(currency.symbol) — \(country)"
        } else {
            return "\(currency.code) \(currency.symbol) — \(currency.name)"
        }
    }

    /// Effective quick-selection denominations after applying optional 18x multiplier.
    var effectiveDenominations: [Int] {
        let base = commonDenominations
        return useEighteenXMultipliers ? base.map { $0 * 18 } : base
    }

    var primaryColor: Color {
        if let hex = primaryColorHex, let c = color(fromHex: hex) {
            return c
        }
        return color(fromName: primaryColorName)
    }

    var secondaryColor: Color {
        if let hex = secondaryColorHex, let c = color(fromHex: hex) {
            return c
        }
        return color(fromName: secondaryColorName)
    }

    var effectivePrimaryHex: String {
        primaryColorHex ?? Self.hexString(from: primaryColor)
    }

    var effectiveSecondaryHex: String {
        secondaryColorHex ?? Self.hexString(from: secondaryColor)
    }

    var primaryGradient: LinearGradient {
        LinearGradient(
            colors: [primaryColor, secondaryColor],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Update and persist the primary theme color.
    func setPrimaryColor(_ color: Color) {
        primaryColorHex = Self.hexString(from: color)
        primaryColorName = nearestColorName(for: color)
    }

    /// Update and persist the secondary theme color.
    func setSecondaryColor(_ color: Color) {
        secondaryColorHex = Self.hexString(from: color)
        secondaryColorName = nearestColorName(for: color)
    }

    /// Apply a given theme preset to the current settings.
    func applyThemePreset(_ preset: ThemePreset) {
        if let primary = color(fromHex: preset.primaryHex),
           let secondary = color(fromHex: preset.secondaryHex) {
            setPrimaryColor(primary)
            setSecondaryColor(secondary)
        }
    }

    /// Persist the current primary/secondary colors as a new preset.
    func saveCurrentThemeAsPreset() {
        let primaryHexValue = effectivePrimaryHex
        let secondaryHexValue = effectiveSecondaryHex

        let primaryName = primaryColorName.capitalized
        let secondaryName = secondaryColorName.capitalized

        let baseName: String
        if primaryName.isEmpty && secondaryName.isEmpty {
            baseName = "Custom Theme"
        } else if primaryName == secondaryName {
            baseName = primaryName
        } else {
            baseName = "\(primaryName) → \(secondaryName)"
        }

        var candidateName = baseName
        let existingNames = Set(themePresets.map { $0.name })
        var index = 2
        while existingNames.contains(candidateName) {
            candidateName = "\(baseName) (\(index))"
            index += 1
        }

        let newPreset = ThemePreset(
            id: UUID(),
            name: candidateName,
            primaryHex: primaryHexValue,
            secondaryHex: secondaryHexValue
        )
        themePresets.insert(newPreset, at: 0)
    }

    /// Convenience for turning a preset into concrete SwiftUI colors.
    func colors(for preset: ThemePreset) -> (Color, Color) {
        let primary = color(fromHex: preset.primaryHex) ?? .black
        let secondary = color(fromHex: preset.secondaryHex) ?? .blue
        return (primary, secondary)
    }

    /// Fallback mapping from legacy color names to SwiftUI colors.
    private func color(fromName name: String) -> Color {
        switch name {
        case "black": return .black
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "mint": return .mint
        case "teal": return .teal
        case "blue": return .blue
        case "indigo": return .indigo
        case "purple": return .purple
        case "pink": return .pink
        case "green": return .green
        default: return .green
        }
    }

    /// Decode a hex RGB string like "#00FF00" into a SwiftUI `Color`.
    private func color(fromHex hex: String) -> Color? {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleaned.hasPrefix("#") {
            cleaned.removeFirst()
        }
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else {
            return nil
        }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }

    /// Encode a SwiftUI `Color` into a hex RGB string for storage.
    private static func hexString(from color: Color) -> String {
        #if os(iOS)
        let uiColor = UIColor(color)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        guard uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) else {
            return "#000000"
        }
        let value = (Int(r * 255) << 16) | (Int(g * 255) << 8) | Int(b * 255)
        return String(format: "#%06X", value)
        #else
        // Reasonable default on non-iOS platforms.
        return "#000000"
        #endif
    }

    /// Roughly classify a color into one of our named buckets.
    private func nearestColorName(for color: Color) -> String {
        #if os(iOS)
        let uiColor = UIColor(color)
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        if uiColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a) {
            let hue = h * 360.0
            if b < 0.25 {
                if s < 0.2 {
                    return "black"
                }
                return "indigo"
            }
            if s < 0.2 {
                return b > 0.8 ? "yellow" : "mint"
            }
            switch hue {
            case 0..<20, 340...360:
                return "red"
            case 20..<50:
                return "orange"
            case 50..<80:
                return "yellow"
            case 80..<150:
                return "mint"
            case 150..<190:
                return "teal"
            case 190..<250:
                return "blue"
            case 250..<290:
                return "indigo"
            case 290..<320:
                return "purple"
            default:
                return "pink"
            }
        }
        #endif
        return "black"
    }
}
