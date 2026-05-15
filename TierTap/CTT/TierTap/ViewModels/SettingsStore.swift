import Foundation
import SwiftUI
import Supabase
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
private let keyFavoriteSlotGames = "ctt_favorite_slot_games"
private let keyFavoriteCasinos = "ctt_favorite_casinos"
private let keyCustomRewardPrograms = "ctt_custom_reward_programs"
private let keyPrimaryColorName = "ctt_primary_color_name"
private let keySecondaryColorName = "ctt_secondary_color_name"
private let keyPrimaryColorHex = "ctt_primary_color_hex"
private let keySecondaryColorHex = "ctt_secondary_color_hex"
private let keySelectedLocationFilter = "ctt_selected_location_filter"
private let keyThemePresets = "ctt_theme_presets"
private let keyPromptSessionMood = "ctt_prompt_session_mood"
private let keyAITone = "ctt_ai_tone"
private let keyAITypingSpeed = "ctt_ai_typing_speed"
private let keyAICallsDate = "ctt_ai_calls_date"
private let keyAICallsCount = "ctt_ai_calls_count"
private let keyAIDayTelemetry = "ctt_ai_day_telemetry_v1"
private let keyAIPurchasedTokenBalance = "ctt_ai_purchased_token_balance"
private let keyAITierTapPlusTokensConsumedFromPacks = "ctt_ai_tiertap_plus_tokens_consumed_from_packs"
private let keyAILifetimeTierTapPlusTokensPurchased = "ctt_ai_lifetime_tiertap_plus_tokens_purchased"
private let keyAIProPlanTokenMonth = "ctt_ai_pro_plan_token_month"
private let keyAIProPlanTokensConsumed = "ctt_ai_pro_plan_tokens_consumed"

/// Per-calendar-day aggregates for Settings “Tokens” charts (persisted).
struct AIDayTelemetry: Codable, Equatable {
    var tokens: Int = 0
    var aiFeaturesUsed: Int = 0
    /// TierTap Plus (`Credits`) tokens granted from IAP on this calendar day (for charts).
    var plusTokensPurchased: Int = 0

    enum CodingKeys: String, CodingKey {
        case tokens
        case aiFeaturesUsed
        case plusTokensPurchased
    }

    init(tokens: Int = 0, aiFeaturesUsed: Int = 0, plusTokensPurchased: Int = 0) {
        self.tokens = tokens
        self.aiFeaturesUsed = aiFeaturesUsed
        self.plusTokensPurchased = plusTokensPurchased
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tokens = try c.decodeIfPresent(Int.self, forKey: .tokens) ?? 0
        aiFeaturesUsed = try c.decodeIfPresent(Int.self, forKey: .aiFeaturesUsed) ?? 0
        plusTokensPurchased = try c.decodeIfPresent(Int.self, forKey: .plusTokensPurchased) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(tokens, forKey: .tokens)
        try c.encode(aiFeaturesUsed, forKey: .aiFeaturesUsed)
        try c.encode(plusTokensPurchased, forKey: .plusTokensPurchased)
    }
}
private let keyEnableCasinoFeedback = "ctt_enable_casino_feedback"
private let keySoundProfile = "ctt_sound_profile"
private let keySubscriptionOverrideCode = "ctt_subscription_override_code"
private let keyDefaultGameCategory = "ctt_default_game_category"
private let keyLastAddOnBuyIn = "ctt_last_add_on_buy_in"
private let keyLastFoodBeverageCompKind = "ctt_last_food_beverage_comp_kind"
private let keyLastTableGame = "ctt_last_table_game"
private let keyLastSlotGame = "ctt_last_slot_game"
private let keyLastPokerDefaults = "ctt_last_poker_defaults"
private let keyLastSlotDefaults = "ctt_last_slot_defaults"
private let keyFastCheckInPresets = "ctt_fast_check_in_presets_v1"
private let keyAnalyticsUseExpectedValue = "ctt_analytics_use_expected_value"
private let keyAppLanguage = "ctt_app_language"
private let keyAppLockEnabled = "ctt_app_lock_enabled"
private let keyAppLockAuthMethod = "ctt_app_lock_auth_method"
private let keyAppLockPinModeLegacy = "ctt_app_lock_pin_mode"
private let keySessionRemindersEnabled = "ctt_session_reminders_enabled"
private let keySessionReminderFrequencyMinutes = "ctt_session_reminder_frequency_minutes"
private let keySessionReminderMessagePreset = "ctt_session_reminder_message_preset"
private let keySessionReminderCustomMessage = "ctt_session_reminder_custom_message"
private let keySessionReminderIncludeSessionStats = "ctt_session_reminder_include_session_stats"
private let keyWatchHapticsEnabled = "ctt_watch_haptics_enabled"
private let keyWatchHapticProfile = "ctt_watch_haptic_profile"
private let keyWatchSessionPulseEnabled = "ctt_watch_session_pulse_enabled"
private let keyWatchSessionPulseMinutes = "ctt_watch_session_pulse_minutes"
private let keyWatchWristRaiseSummaryEnabled = "ctt_watch_wrist_raise_summary_enabled"
private let keyWatchBuyInCashDefaults = "ctt_watch_buyin_cash_defaults"
private let keyWatchCompCashDefaults = "ctt_watch_comp_cash_defaults"
private let keyWatchCompContextOptions = "ctt_watch_comp_context_options"
private let keyWatchAnimationsEnabled = TierTapWatchAnimationsSettings.userDefaultsKey
private let appGroupSuiteName = "group.com.app.tiertap"

/// Saved poker choices from the last completed or started session; used to pre-fill check-in.
struct LastPokerSessionDefaults: Codable, Equatable {
    var pokerGameKind: SessionPokerGameKind
    var pokerAllowsRebuy: Bool
    var pokerAllowsAddOn: Bool
    var pokerHasFreezeOut: Bool
    var pokerVariant: String
    var pokerSmallBlind: Int
    var pokerBigBlind: Int
    var pokerAnte: Int
    var pokerLevelMinutesText: String
    var pokerStartingStackText: String
    var pokerTournamentCostText: String
}

/// Last slot notes; pre-fills check-in when game type is Slots.
struct LastSlotSessionDefaults: Codable, Equatable {
    var slotNotes: String
}

/// User-saved fast check-in configuration (no live session). Takes precedence over “last session” when present.
struct FastCheckInSavedPreset: Codable, Equatable {
    var casino: String
    var game: String
    var startingTierPoints: Int
    var initialBuyIn: Int
    var rewardsProgramName: String?
    var casinoLatitude: Double?
    var casinoLongitude: Double?
    var linkedRewardWalletCardId: UUID?
    var pokerGameKind: SessionPokerGameKind?
    var pokerAllowsRebuy: Bool?
    var pokerAllowsAddOn: Bool?
    var pokerHasFreeOut: Bool?
    var pokerVariant: String?
    var pokerSmallBlind: Int?
    var pokerBigBlind: Int?
    var pokerAnte: Int?
    var pokerLevelMinutes: Int?
    var pokerStartingStack: Int?
    var pokerTournamentCostText: String
    var slotFormat: SessionSlotFormat?
    var slotFormatOther: String?
    var slotFeature: SessionSlotFeature?
    var slotFeatureOther: String?
    var slotNotes: String?

    /// In-memory template used by `FastCheckInHelper` (not written to session history).
    func makeTemplateSession(for category: SessionGameCategory) -> Session {
        let now = Date()
        let buyIn = max(1, initialBuyIn)
        let buyInEvent = BuyInEvent(amount: buyIn, timestamp: now)
        switch category {
        case .poker:
            return Session(
                game: game,
                casino: casino,
                casinoLatitude: casinoLatitude,
                casinoLongitude: casinoLongitude,
                startTime: now,
                endTime: now,
                startingTierPoints: startingTierPoints,
                buyInEvents: [buyInEvent],
                isLive: false,
                status: .complete,
                rewardsProgramName: rewardsProgramName,
                linkedRewardWalletCardId: linkedRewardWalletCardId,
                gameCategory: .poker,
                pokerGameKind: pokerGameKind ?? .cash,
                pokerAllowsRebuy: pokerAllowsRebuy,
                pokerAllowsAddOn: pokerAllowsAddOn,
                pokerHasFreeOut: pokerHasFreeOut,
                pokerVariant: pokerVariant,
                pokerSmallBlind: pokerSmallBlind,
                pokerBigBlind: pokerBigBlind,
                pokerAnte: pokerAnte,
                pokerLevelMinutes: pokerLevelMinutes,
                pokerStartingStack: pokerStartingStack
            )
        case .slots:
            return Session(
                game: game,
                casino: casino,
                casinoLatitude: casinoLatitude,
                casinoLongitude: casinoLongitude,
                startTime: now,
                endTime: now,
                startingTierPoints: startingTierPoints,
                buyInEvents: [buyInEvent],
                isLive: false,
                status: .complete,
                rewardsProgramName: rewardsProgramName,
                linkedRewardWalletCardId: linkedRewardWalletCardId,
                gameCategory: .slots,
                slotFormat: slotFormat,
                slotFormatOther: slotFormatOther,
                slotFeature: slotFeature,
                slotFeatureOther: slotFeatureOther,
                slotNotes: slotNotes
            )
        case .table:
            return Session(
                game: game,
                casino: casino,
                casinoLatitude: casinoLatitude,
                casinoLongitude: casinoLongitude,
                startTime: now,
                endTime: now,
                startingTierPoints: startingTierPoints,
                buyInEvents: [buyInEvent],
                isLive: false,
                status: .complete,
                rewardsProgramName: rewardsProgramName,
                linkedRewardWalletCardId: linkedRewardWalletCardId,
                gameCategory: .table
            )
        }
    }
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
    static let sessionReminderMessageOptions: [String] = [
        "Take a break.",
        "Quit while you're ahead.",
        "Protect your bankroll.",
        "Stick to your unit size.",
        "Stay disciplined and avoid tilt.",
        "Set a stop-loss and honor it."
    ]

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

    /// User-favorited slot titles for the slots check-in grid.
    @Published var favoriteSlotGames: [String] {
        didSet { UserDefaults.standard.set(favoriteSlotGames, forKey: keyFavoriteSlotGames) }
    }

    /// User-favorited casino locations for quick selection.
    @Published var favoriteCasinos: [String] {
        didSet { UserDefaults.standard.set(favoriteCasinos, forKey: keyFavoriteCasinos) }
    }

    /// User-added reward program names (shared by check-in pickers and wallet card editors).
    @Published var customRewardPrograms: [String] {
        didSet { UserDefaults.standard.set(customRewardPrograms, forKey: keyCustomRewardPrograms) }
    }

    /// Default game category to show in game pickers and analytics (Table, Slots, or Poker).
    @Published var defaultGameCategory: SessionGameCategory {
        didSet { UserDefaults.standard.set(defaultGameCategory.rawValue, forKey: keyDefaultGameCategory) }
    }

    /// Last amount used in the live-session Add Buy-In flow (e.g. tournament add-on). 0 = none saved.
    @Published var lastAddOnBuyInAmount: Int {
        didSet {
            if lastAddOnBuyInAmount > 0 {
                UserDefaults.standard.set(lastAddOnBuyInAmount, forKey: keyLastAddOnBuyIn)
            } else {
                UserDefaults.standard.removeObject(forKey: keyLastAddOnBuyIn)
            }
        }
    }

    /// Last food & beverage category chosen in Add Comp; pre-fills the next entry.
    @Published var lastFoodBeverageCompKind: FoodBeverageKind {
        didSet { UserDefaults.standard.set(lastFoodBeverageCompKind.rawValue, forKey: keyLastFoodBeverageCompKind) }
    }

    /// Last table game name chosen at check-in (or from a saved session). Empty = no saved default.
    @Published var lastTableGameName: String {
        didSet {
            if lastTableGameName.isEmpty {
                UserDefaults.standard.removeObject(forKey: keyLastTableGame)
            } else {
                UserDefaults.standard.set(lastTableGameName, forKey: keyLastTableGame)
            }
        }
    }

    /// Last slot title chosen at check-in (or from a saved session). Empty = no saved default.
    @Published var lastSlotGameName: String {
        didSet {
            if lastSlotGameName.isEmpty {
                UserDefaults.standard.removeObject(forKey: keyLastSlotGame)
            } else {
                UserDefaults.standard.set(lastSlotGameName, forKey: keyLastSlotGame)
            }
        }
    }

    /// Last poker structure/variant from a completed or in-progress session; used to pre-fill check-in.
    @Published var lastPokerSessionDefaults: LastPokerSessionDefaults? {
        didSet {
            if let d = lastPokerSessionDefaults, let data = try? JSONEncoder().encode(d) {
                UserDefaults.standard.set(data, forKey: keyLastPokerDefaults)
            } else {
                UserDefaults.standard.removeObject(forKey: keyLastPokerDefaults)
            }
        }
    }

    /// Last slot categorization from check-in or a saved session; pre-fills optional slot fields.
    @Published var lastSlotSessionDefaults: LastSlotSessionDefaults? {
        didSet {
            if let d = lastSlotSessionDefaults, let data = try? JSONEncoder().encode(d) {
                UserDefaults.standard.set(data, forKey: keyLastSlotDefaults)
            } else {
                UserDefaults.standard.removeObject(forKey: keyLastSlotDefaults)
            }
        }
    }

    /// Saved fast check-in rows per game type (from “Save fast check-in” on the check-in form).
    @Published var fastCheckInSavedPresets: [SessionGameCategory: FastCheckInSavedPreset] = [:] {
        didSet {
            let encodable = Dictionary(uniqueKeysWithValues: fastCheckInSavedPresets.map { ($0.key.rawValue, $0.value) })
            if encodable.isEmpty {
                UserDefaults.standard.removeObject(forKey: keyFastCheckInPresets)
            } else if let data = try? JSONEncoder().encode(encodable) {
                UserDefaults.standard.set(data, forKey: keyFastCheckInPresets)
            }
        }
    }

    func fastCheckInSavedPreset(for category: SessionGameCategory) -> FastCheckInSavedPreset? {
        fastCheckInSavedPresets[category]
    }

    func setFastCheckInSavedPreset(_ preset: FastCheckInSavedPreset?, for category: SessionGameCategory) {
        var next = fastCheckInSavedPresets
        if let preset {
            next[category] = preset
        } else {
            next.removeValue(forKey: category)
        }
        fastCheckInSavedPresets = next
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
        didSet { syncThemeToSharedStorage() }
    }
    @Published var secondaryColorName: String {
        didSet { syncThemeToSharedStorage() }
    }

    /// Stored hex strings for primary/secondary theme colors (takes precedence over name when present).
    @Published var primaryColorHex: String? {
        didSet { syncThemeToSharedStorage() }
    }
    @Published var secondaryColorHex: String? {
        didSet { syncThemeToSharedStorage() }
    }

    /// Saved theme presets (built-in + user-defined).
    @Published var themePresets: [ThemePreset] {
        didSet { syncThemeToSharedStorage() }
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

    /// Speed of the typewriter effect when AI answers appear (e.g. Ask TierTap).
    enum AITypingSpeed: String, CaseIterable, Identifiable, Codable {
        case slow
        case medium
        case fast

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .slow: return "Slow"
            case .medium: return "Medium"
            case .fast: return "Fast"
            }
        }

        /// Slider position 0…2 for a stepped control.
        var sliderIndex: Double {
            switch self {
            case .slow: return 0
            case .medium: return 1
            case .fast: return 2
            }
        }

        static func fromSliderIndex(_ value: Double) -> AITypingSpeed {
            switch Int(value.rounded()) {
            case 1: return .medium
            case 2: return .fast
            default: return .slow
            }
        }

        /// Nanoseconds between characters; **slow** matches the original fixed delay.
        var nanosecondsPerCharacter: UInt64 {
            switch self {
            case .slow: return 25_000_000
            case .medium: return 10_000_000
            case .fast: return 4_000_000
            }
        }
    }

    @Published var aiTone: AITone {
        didSet { UserDefaults.standard.set(aiTone.rawValue, forKey: keyAITone) }
    }

    @Published var aiTypingSpeed: AITypingSpeed {
        didSet { UserDefaults.standard.set(aiTypingSpeed.rawValue, forKey: keyAITypingSpeed) }
    }

    /// When true, analytics (and matching AI summaries) treat session results as **EV** (cash net + comps). When false, **cash net** only.
    @Published var analyticsUseExpectedValue: Bool {
        didSet { UserDefaults.standard.set(analyticsUseExpectedValue, forKey: keyAnalyticsUseExpectedValue) }
    }

    /// UI language (also synced to the app group for watch extensions).
    @Published var appLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(appLanguage.rawValue, forKey: keyAppLanguage)
            UserDefaults(suiteName: appGroupSuiteName)?.set(appLanguage.rawValue, forKey: keyAppLanguage)
        }
    }

    /// Require Face ID / Touch ID or the device passcode to open the app after backgrounding or launch.
    @Published var appLockEnabled: Bool {
        didSet { UserDefaults.standard.set(appLockEnabled, forKey: keyAppLockEnabled) }
    }

    enum AppLockAuthMethod: String, CaseIterable, Identifiable, Codable {
        case faceID
        case pin

        var id: String { rawValue }
    }

    @Published var appLockAuthMethod: AppLockAuthMethod {
        didSet { UserDefaults.standard.set(appLockAuthMethod.rawValue, forKey: keyAppLockAuthMethod) }
    }

    /// When true, local notifications are sent at a fixed cadence during active live sessions.
    @Published var sessionRemindersEnabled: Bool {
        didSet { UserDefaults.standard.set(sessionRemindersEnabled, forKey: keySessionRemindersEnabled) }
    }

    /// Reminder cadence in minutes for live-session notifications (minimum 1 minute).
    @Published var sessionReminderFrequencyMinutes: Int {
        didSet {
            let clamped = max(1, sessionReminderFrequencyMinutes)
            if clamped != sessionReminderFrequencyMinutes {
                sessionReminderFrequencyMinutes = clamped
                return
            }
            UserDefaults.standard.set(clamped, forKey: keySessionReminderFrequencyMinutes)
        }
    }

    /// Selected canned line appended to Play Reminder notifications.
    @Published var sessionReminderMessagePreset: String {
        didSet {
            let value = sessionReminderMessagePreset.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = Self.sessionReminderMessageOptions.first ?? "Take a break."
            let normalized = Self.sessionReminderMessageOptions.contains(value) ? value : fallback
            if normalized != sessionReminderMessagePreset {
                sessionReminderMessagePreset = normalized
                return
            }
            UserDefaults.standard.set(normalized, forKey: keySessionReminderMessagePreset)
        }
    }

    /// Optional freeform line appended after the selected reminder message.
    @Published var sessionReminderCustomMessage: String {
        didSet {
            let trimmed = sessionReminderCustomMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed != sessionReminderCustomMessage {
                sessionReminderCustomMessage = trimmed
                return
            }
            if trimmed.isEmpty {
                UserDefaults.standard.removeObject(forKey: keySessionReminderCustomMessage)
            } else {
                UserDefaults.standard.set(trimmed, forKey: keySessionReminderCustomMessage)
            }
        }
    }

    /// When true, reminder notifications append live-session stats (buy-in, comps, tier, etc.).
    @Published var sessionReminderIncludeSessionStats: Bool {
        didSet { UserDefaults.standard.set(sessionReminderIncludeSessionStats, forKey: keySessionReminderIncludeSessionStats) }
    }

    enum WatchHapticProfile: String, CaseIterable, Identifiable, Codable {
        case classic
        case subtle
        case assertive
        var id: String { rawValue }
    }

    @Published var watchHapticsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(watchHapticsEnabled, forKey: keyWatchHapticsEnabled)
            UserDefaults(suiteName: appGroupSuiteName)?.set(watchHapticsEnabled, forKey: keyWatchHapticsEnabled)
        }
    }

    @Published var watchHapticProfile: WatchHapticProfile {
        didSet {
            UserDefaults.standard.set(watchHapticProfile.rawValue, forKey: keyWatchHapticProfile)
            UserDefaults(suiteName: appGroupSuiteName)?.set(watchHapticProfile.rawValue, forKey: keyWatchHapticProfile)
        }
    }

    @Published var watchSessionPulseEnabled: Bool {
        didSet {
            UserDefaults.standard.set(watchSessionPulseEnabled, forKey: keyWatchSessionPulseEnabled)
            UserDefaults(suiteName: appGroupSuiteName)?.set(watchSessionPulseEnabled, forKey: keyWatchSessionPulseEnabled)
        }
    }

    @Published var watchSessionPulseMinutes: Int {
        didSet {
            let clamped = max(1, watchSessionPulseMinutes)
            if clamped != watchSessionPulseMinutes {
                watchSessionPulseMinutes = clamped
                return
            }
            UserDefaults.standard.set(clamped, forKey: keyWatchSessionPulseMinutes)
            UserDefaults(suiteName: appGroupSuiteName)?.set(clamped, forKey: keyWatchSessionPulseMinutes)
        }
    }

    @Published var watchWristRaiseSummaryEnabled: Bool {
        didSet {
            UserDefaults.standard.set(watchWristRaiseSummaryEnabled, forKey: keyWatchWristRaiseSummaryEnabled)
            UserDefaults(suiteName: appGroupSuiteName)?.set(watchWristRaiseSummaryEnabled, forKey: keyWatchWristRaiseSummaryEnabled)
        }
    }

    @Published var watchBuyInCashDefaultsText: String {
        didSet {
            let normalized = watchBuyInCashDefaultsText
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: " ")
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            UserDefaults.standard.set(normalized, forKey: keyWatchBuyInCashDefaults)
            UserDefaults(suiteName: appGroupSuiteName)?.set(normalized, forKey: keyWatchBuyInCashDefaults)
        }
    }

    @Published var watchCompCashDefaultsText: String {
        didSet {
            let normalized = watchCompCashDefaultsText
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: " ")
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            UserDefaults.standard.set(normalized, forKey: keyWatchCompCashDefaults)
            UserDefaults(suiteName: appGroupSuiteName)?.set(normalized, forKey: keyWatchCompCashDefaults)
        }
    }

    @Published var watchCompContextOptionsText: String {
        didSet {
            let trimmed = watchCompContextOptionsText.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(trimmed, forKey: keyWatchCompContextOptions)
            UserDefaults(suiteName: appGroupSuiteName)?.set(trimmed, forKey: keyWatchCompContextOptions)
        }
    }

    /// Motion effects on Apple Watch (press feedback, ripples, tier/comp/buy-in flourishes). Synced to the App Group.
    @Published var watchAnimationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(watchAnimationsEnabled, forKey: keyWatchAnimationsEnabled)
            UserDefaults(suiteName: appGroupSuiteName)?.set(watchAnimationsEnabled, forKey: keyWatchAnimationsEnabled)
        }
    }

    /// Optional overrides from Supabase `TierTapAppDefaults` (see ``refreshRemoteAppDefaults``). Empty means use bundled fallbacks.
    @Published private(set) var remoteAppNumericOverrides: [String: Int] = [:]

    /// Daily AI usage tracking for the free tier.
    @Published private(set) var aiCallsToday: Int
    @Published private(set) var aiCallsDate: Date

    /// Per-day AI token usage and feature invocations (all tiers), for Settings charts.
    @Published private(set) var aiDayTelemetry: [String: AIDayTelemetry] = [:]

    /// Remaining TierTap Plus token balance from **Credits** consumable IAP. Drawn down only after the monthly Pro plan allowance is used (see ``consumeAIPurchasedTokensIfNeeded``).
    @Published private(set) var aiPurchasedTokenBalance: Int = 0

    /// Lifetime total of TierTap Plus (`Credits`) tokens granted from IAP (running sum of pack sizes).
    @Published private(set) var lifetimeTierTapPlusTokensPurchased: Int = 0

    /// Tokens charged against the purchasable balance after the Pro plan monthly allowance was exhausted.
    @Published private(set) var tierTapPlusTokensConsumedFromPurchases: Int = 0

    /// TierTap Pro included-token usage for the calendar month in ``proPlanTokenUsageMonthKey``.
    @Published private(set) var proPlanTokensConsumedThisMonth: Int = 0

    /// Maximum number of AI calls allowed per day on the free tier. Higher on TestFlight for testers.
    var maxAICallsPerDay: Int {
        SupabaseConfig.isTestFlight
            ? resolvedRemoteInt(for: .maxAICallsPerDayTestFlight, bundled: TierTapRemoteDefaultFallbacks.maxAICallsPerDayTestFlight)
            : resolvedRemoteInt(for: .maxAICallsPerDay, bundled: TierTapRemoteDefaultFallbacks.maxAICallsPerDay)
    }

    /// TierTap Pro included Gemini token allowance for the calendar month (bundled default or Supabase `TierTapAppDefaults`).
    var effectiveProPlanIncludedTokensPerCalendarMonth: Int {
        resolvedRemoteInt(for: .proPlanIncludedTokensPerCalendarMonth, bundled: TierTapRemoteDefaultFallbacks.proPlanIncludedTokensPerCalendarMonth)
    }

    /// Tokens granted per successful **Credits** purchase (bundled default or Supabase `TierTapAppDefaults`).
    var effectiveCreditsPackTokenAmount: Int {
        resolvedRemoteInt(for: .creditsPackTokenAmount, bundled: TierTapRemoteDefaultFallbacks.creditsPackTokenAmount)
    }

    /// Max TierTap AI session-art images per calendar day when limits apply (bundled default or Supabase `TierTapAppDefaults`).
    var effectiveTierTapAIImagesPerDay: Int {
        resolvedRemoteInt(for: .tierTapAIImagesPerDay, bundled: TierTapRemoteDefaultFallbacks.tierTapAIImagesPerDay)
    }

    /// Remaining TierTap Pro included Gemini tokens for the current calendar month (before pack balance is used).
    var proPlanIncludedTokensRemainingThisMonth: Int {
        max(0, effectiveProPlanIncludedTokensPerCalendarMonth - proPlanTokensConsumedThisMonth)
    }

    /// True when the monthly Pro allowance and any TierTap+ pack balance are both depleted.
    var isProAITokenBudgetExhausted: Bool {
        proPlanIncludedTokensRemainingThisMonth == 0 && aiPurchasedTokenBalance == 0
    }

    /// Whether a signed-in TierTap Pro subscriber is blocked from token-backed AI and advanced features.
    func isProTokenBackedAccessBlocked(hasProAccess: Bool) -> Bool {
        guard hasProAccess else { return false }
        if isSubscriptionOverrideActive { return false }
        #if targetEnvironment(simulator)
        return false
        #else
        return isProAITokenBudgetExhausted
        #endif
    }

    /// Whether the user may invoke TierTap AI features (free daily quota or Pro monthly + pack budget).
    func canInvokeTierTapAIFeatures(hasProAccess: Bool) -> Bool {
        if isSubscriptionOverrideActive { return true }
        #if targetEnvironment(simulator)
        return true
        #else
        if hasProAccess {
            return !isProAITokenBudgetExhausted
        }
        return canUseAI()
        #endif
    }

    /// Whether an AI feature attempt should present `TierTapPaywallView` before calling the model.
    func requiresTierTapAIFeaturePaywall(isSignedIn: Bool, hasProAccess: Bool) -> Bool {
        guard isSignedIn else { return true }
        return !canInvokeTierTapAIFeatures(hasProAccess: hasProAccess)
    }

    /// Remaining AI calls the user can make today on the free tier.
    var remainingAICallsToday: Int {
        max(0, maxAICallsPerDay - effectiveAICallsToday())
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
        self.favoriteSlotGames = UserDefaults.standard.stringArray(forKey: keyFavoriteSlotGames) ?? []
        self.favoriteCasinos = UserDefaults.standard.stringArray(forKey: keyFavoriteCasinos) ?? []
        self.customRewardPrograms = UserDefaults.standard.stringArray(forKey: keyCustomRewardPrograms) ?? []
        if let raw = UserDefaults.standard.string(forKey: keyDefaultGameCategory),
           let cat = SessionGameCategory(rawValue: raw) {
            self.defaultGameCategory = cat
        } else {
            self.defaultGameCategory = .table
        }
        let storedAddOn = UserDefaults.standard.integer(forKey: keyLastAddOnBuyIn)
        self.lastAddOnBuyInAmount = storedAddOn > 0 ? storedAddOn : 0
        if let raw = UserDefaults.standard.string(forKey: keyLastFoodBeverageCompKind),
           let fb = FoodBeverageKind(rawValue: raw) {
            self.lastFoodBeverageCompKind = fb
        } else {
            self.lastFoodBeverageCompKind = .meal
        }
        self.lastTableGameName = UserDefaults.standard.string(forKey: keyLastTableGame) ?? ""
        self.lastSlotGameName = UserDefaults.standard.string(forKey: keyLastSlotGame) ?? ""
        if let data = UserDefaults.standard.data(forKey: keyLastPokerDefaults),
           let decoded = try? JSONDecoder().decode(LastPokerSessionDefaults.self, from: data) {
            self.lastPokerSessionDefaults = decoded
        } else {
            self.lastPokerSessionDefaults = nil
        }
        if let data = UserDefaults.standard.data(forKey: keyLastSlotDefaults),
           let decoded = try? JSONDecoder().decode(LastSlotSessionDefaults.self, from: data) {
            self.lastSlotSessionDefaults = decoded
        } else {
            self.lastSlotSessionDefaults = nil
        }
        if let data = UserDefaults.standard.data(forKey: keyFastCheckInPresets),
           let decoded = try? JSONDecoder().decode([String: FastCheckInSavedPreset].self, from: data) {
            var m: [SessionGameCategory: FastCheckInSavedPreset] = [:]
            for (raw, preset) in decoded {
                if let c = SessionGameCategory(rawValue: raw) {
                    m[c] = preset
                }
            }
            self.fastCheckInSavedPresets = m
        } else {
            self.fastCheckInSavedPresets = [:]
        }
        let themeSnapshot = TierTapThemeSettings.load()
        self.primaryColorName = themeSnapshot.primaryColorName
        self.secondaryColorName = themeSnapshot.secondaryColorName
        self.primaryColorHex = themeSnapshot.primaryColorHex
        self.secondaryColorHex = themeSnapshot.secondaryColorHex
        self.themePresets = themeSnapshot.themePresets
        self.selectedLocationFilter = UserDefaults.standard.string(forKey: keySelectedLocationFilter)
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
        if let storedSpeed = UserDefaults.standard.string(forKey: keyAITypingSpeed),
           let speed = AITypingSpeed(rawValue: storedSpeed) {
            self.aiTypingSpeed = speed
        } else {
            self.aiTypingSpeed = .fast
        }
        if UserDefaults.standard.object(forKey: keyAnalyticsUseExpectedValue) != nil {
            self.analyticsUseExpectedValue = UserDefaults.standard.bool(forKey: keyAnalyticsUseExpectedValue)
        } else {
            self.analyticsUseExpectedValue = false
        }

        let storedLang =
            UserDefaults.standard.string(forKey: keyAppLanguage)
            ?? UserDefaults(suiteName: appGroupSuiteName)?.string(forKey: keyAppLanguage)
        if let raw = storedLang, let lang = AppLanguage(rawValue: raw) {
            self.appLanguage = lang
        } else {
            self.appLanguage = .english
        }

        self.appLockEnabled = UserDefaults.standard.bool(forKey: keyAppLockEnabled)
        if let raw = UserDefaults.standard.string(forKey: keyAppLockAuthMethod),
           let m = AppLockAuthMethod(rawValue: raw) {
            self.appLockAuthMethod = m
        } else {
            self.appLockAuthMethod = .faceID
        }
        if UserDefaults.standard.object(forKey: keySessionRemindersEnabled) != nil {
            self.sessionRemindersEnabled = UserDefaults.standard.bool(forKey: keySessionRemindersEnabled)
        } else {
            self.sessionRemindersEnabled = false
        }
        let storedReminderFrequency = UserDefaults.standard.integer(forKey: keySessionReminderFrequencyMinutes)
        self.sessionReminderFrequencyMinutes = max(1, storedReminderFrequency > 0 ? storedReminderFrequency : 30)
        let storedReminderPreset = UserDefaults.standard.string(forKey: keySessionReminderMessagePreset)
        let fallbackReminderPreset = Self.sessionReminderMessageOptions.first ?? "Take a break."
        if let storedReminderPreset, Self.sessionReminderMessageOptions.contains(storedReminderPreset) {
            self.sessionReminderMessagePreset = storedReminderPreset
        } else {
            self.sessionReminderMessagePreset = fallbackReminderPreset
        }
        self.sessionReminderCustomMessage = UserDefaults.standard.string(forKey: keySessionReminderCustomMessage)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if UserDefaults.standard.object(forKey: keySessionReminderIncludeSessionStats) != nil {
            self.sessionReminderIncludeSessionStats = UserDefaults.standard.bool(forKey: keySessionReminderIncludeSessionStats)
        } else {
            self.sessionReminderIncludeSessionStats = true
        }
        if UserDefaults.standard.object(forKey: keyWatchHapticsEnabled) != nil {
            self.watchHapticsEnabled = UserDefaults.standard.bool(forKey: keyWatchHapticsEnabled)
        } else {
            self.watchHapticsEnabled = true
        }
        if let raw = UserDefaults.standard.string(forKey: keyWatchHapticProfile),
           let profile = WatchHapticProfile(rawValue: raw) {
            self.watchHapticProfile = profile
        } else {
            self.watchHapticProfile = .classic
        }
        if UserDefaults.standard.object(forKey: keyWatchSessionPulseEnabled) != nil {
            self.watchSessionPulseEnabled = UserDefaults.standard.bool(forKey: keyWatchSessionPulseEnabled)
        } else {
            self.watchSessionPulseEnabled = true
        }
        let storedPulseMinutes = UserDefaults.standard.integer(forKey: keyWatchSessionPulseMinutes)
        self.watchSessionPulseMinutes = max(1, storedPulseMinutes > 0 ? storedPulseMinutes : 20)
        if UserDefaults.standard.object(forKey: keyWatchWristRaiseSummaryEnabled) != nil {
            self.watchWristRaiseSummaryEnabled = UserDefaults.standard.bool(forKey: keyWatchWristRaiseSummaryEnabled)
        } else {
            self.watchWristRaiseSummaryEnabled = true
        }
        self.watchBuyInCashDefaultsText =
            UserDefaults.standard.string(forKey: keyWatchBuyInCashDefaults)
            ?? UserDefaults(suiteName: appGroupSuiteName)?.string(forKey: keyWatchBuyInCashDefaults)
            ?? "20 100 200 500"
        self.watchCompCashDefaultsText =
            UserDefaults.standard.string(forKey: keyWatchCompCashDefaults)
            ?? UserDefaults(suiteName: appGroupSuiteName)?.string(forKey: keyWatchCompCashDefaults)
            ?? "20 50 100 500"
        self.watchCompContextOptionsText =
            UserDefaults.standard.string(forKey: keyWatchCompContextOptions)
            ?? UserDefaults(suiteName: appGroupSuiteName)?.string(forKey: keyWatchCompContextOptions)
            ?? "Cocktail, Beer, Food, Cash"
        if UserDefaults.standard.object(forKey: keyWatchAnimationsEnabled) != nil {
            self.watchAnimationsEnabled = UserDefaults.standard.bool(forKey: keyWatchAnimationsEnabled)
        } else {
            self.watchAnimationsEnabled = true
        }
        if UserDefaults.standard.object(forKey: keyAppLockPinModeLegacy) != nil {
            AppLockPINLegacy.clearFromKeychain()
            UserDefaults.standard.removeObject(forKey: keyAppLockPinModeLegacy)
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

        if let data = UserDefaults.standard.data(forKey: keyAIDayTelemetry),
           let decoded = try? JSONDecoder().decode([String: AIDayTelemetry].self, from: data) {
            self.aiDayTelemetry = decoded
        } else {
            self.aiDayTelemetry = [:]
        }

        self.aiPurchasedTokenBalance = max(0, UserDefaults.standard.integer(forKey: keyAIPurchasedTokenBalance))

        self.tierTapPlusTokensConsumedFromPurchases = max(0, UserDefaults.standard.integer(forKey: keyAITierTapPlusTokensConsumedFromPacks))

        let planMonth = Self.proPlanMonthKey(for: Date())
        let storedPlanMonth = UserDefaults.standard.string(forKey: keyAIProPlanTokenMonth) ?? ""
        if storedPlanMonth == planMonth {
            self.proPlanTokensConsumedThisMonth = max(0, UserDefaults.standard.integer(forKey: keyAIProPlanTokensConsumed))
        } else {
            self.proPlanTokensConsumedThisMonth = 0
            UserDefaults.standard.set(planMonth, forKey: keyAIProPlanTokenMonth)
            UserDefaults.standard.set(0, forKey: keyAIProPlanTokensConsumed)
        }

        var lifetimePurchased = max(0, UserDefaults.standard.integer(forKey: keyAILifetimeTierTapPlusTokensPurchased))
        if lifetimePurchased == 0 && self.aiPurchasedTokenBalance > 0 {
            lifetimePurchased = self.aiPurchasedTokenBalance
            UserDefaults.standard.set(lifetimePurchased, forKey: keyAILifetimeTierTapPlusTokensPurchased)
        }
        self.lifetimeTierTapPlusTokensPurchased = lifetimePurchased

        UserDefaults(suiteName: appGroupSuiteName)?.set(self.appLanguage.rawValue, forKey: keyAppLanguage)
        UserDefaults(suiteName: appGroupSuiteName)?.set(self.watchHapticsEnabled, forKey: keyWatchHapticsEnabled)
        UserDefaults(suiteName: appGroupSuiteName)?.set(self.watchHapticProfile.rawValue, forKey: keyWatchHapticProfile)
        UserDefaults(suiteName: appGroupSuiteName)?.set(self.watchSessionPulseEnabled, forKey: keyWatchSessionPulseEnabled)
        UserDefaults(suiteName: appGroupSuiteName)?.set(self.watchSessionPulseMinutes, forKey: keyWatchSessionPulseMinutes)
        UserDefaults(suiteName: appGroupSuiteName)?.set(self.watchWristRaiseSummaryEnabled, forKey: keyWatchWristRaiseSummaryEnabled)
        UserDefaults(suiteName: appGroupSuiteName)?.set(self.watchBuyInCashDefaultsText, forKey: keyWatchBuyInCashDefaults)
        UserDefaults(suiteName: appGroupSuiteName)?.set(self.watchCompCashDefaultsText, forKey: keyWatchCompCashDefaults)
        UserDefaults(suiteName: appGroupSuiteName)?.set(self.watchCompContextOptionsText, forKey: keyWatchCompContextOptions)
        UserDefaults(suiteName: appGroupSuiteName)?.set(self.watchAnimationsEnabled, forKey: keyWatchAnimationsEnabled)
        syncThemeToSharedStorage()
    }

    /// Reload theme colors from the App Group (e.g. after changing them on Apple Watch).
    func reloadThemeFromSharedStorage() {
        let theme = TierTapThemeSettings.load()
        primaryColorName = theme.primaryColorName
        secondaryColorName = theme.secondaryColorName
        primaryColorHex = theme.primaryColorHex
        secondaryColorHex = theme.secondaryColorHex
        themePresets = theme.themePresets
    }

    private func syncThemeToSharedStorage() {
        TierTapThemeSettings.save(
            TierTapThemeSettings.Snapshot(
                primaryColorName: primaryColorName,
                secondaryColorName: secondaryColorName,
                primaryColorHex: primaryColorHex,
                secondaryColorHex: secondaryColorHex,
                themePresets: themePresets
            )
        )
    }

    /// Adds a rewards program name to the shared custom list if it is not already present (case-insensitive).
    func rememberRewardProgramName(_ raw: String) {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let key = t.lowercased()
        if customRewardPrograms.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == key }) {
            return
        }
        customRewardPrograms.append(t)
    }

    private func resolvedRemoteInt(for key: TierTapRemoteDefaultKey, bundled: Int) -> Int {
        if let o = remoteAppNumericOverrides[key.rawValue], o > 0 { return o }
        return bundled
    }

    /// Loads optional numeric overrides from Supabase `TierTapAppDefaults`. On failure, leaves existing overrides unchanged.
    @MainActor
    func refreshRemoteAppDefaults() async {
        guard SupabaseConfig.isConfigured else { return }
        guard let next = await TierTapAppDefaultsAPI.fetchNumericOverrides() else { return }
        remoteAppNumericOverrides = next
    }

    // MARK: - AI usage helpers

    /// Count toward today's AI limit, treating a new calendar day as zero **without** mutating
    /// `@Published` state. Used from SwiftUI `body` (e.g. `ChipEstimatorSheetView.canEstimate`) where
    /// calling `resetAICallCounterIfNeeded()` would publish during a view update and can crash.
    private func effectiveAICallsToday(referenceDate: Date = Date()) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: referenceDate)
        if calendar.isDate(aiCallsDate, inSameDayAs: today) {
            return aiCallsToday
        }
        return 0
    }

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
        return effectiveAICallsToday() < maxAICallsPerDay
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

    /// Stable `yyyy-MM` key for TierTap Pro included-token monthly bucket.
    static func proPlanMonthKey(for date: Date, calendar: Calendar = .current) -> String {
        let sod = calendar.startOfDay(for: date)
        let c = calendar.dateComponents([.year, .month], from: sod)
        guard let y = c.year, let m = c.month else { return "" }
        return String(format: "%04d-%02d", y, m)
    }

    /// Stable `yyyy-MM-dd` key in the user's calendar for telemetry buckets.
    static func telemetryDayKey(for date: Date, calendar: Calendar = .current) -> String {
        let sod = calendar.startOfDay(for: date)
        let c = calendar.dateComponents([.year, .month, .day], from: sod)
        guard let y = c.year, let m = c.month, let d = c.day else { return "" }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    /// Credits from a successful **TierTapSession** (`Credits`) consumable purchase.
    /// When Supabase is configured and `supabaseUserId` is set, the server row is updated (and the purchase is recorded there). Otherwise updates are local only.
    @MainActor
    func grantTierTapSessionCreditsPack(
        amount: Int? = nil,
        storeTransactionId: String? = nil,
        supabaseUserId: UUID? = nil
    ) async {
        let grant = amount ?? effectiveCreditsPackTokenAmount
        let add = max(0, grant)
        guard add > 0 else { return }
        let txn = storeTransactionId ?? "local-\(UUID().uuidString)"

        if SupabaseConfig.isConfigured, supabaseUserId != nil {
            do {
                let payload = try await TierTapUserAITokenBalancesAPI.grantPlusPack(
                    tokensGranted: add,
                    productId: TierTapProductId.credits.rawValue,
                    storeTransactionId: txn
                )
                applyAITokenBalancesFromServer(payload)
                addPlusPurchaseToLocalCharts(amount: add)
            } catch {
                print("[SettingsStore] grantPlusPack server failed, using local balances: \(error.localizedDescription)")
                applyLocalTierTapPlusGrant(amount: add)
                addPlusPurchaseToLocalCharts(amount: add)
                if let uid = supabaseUserId {
                    await TierTapPlusPurchasesAPI.recordPurchase(
                        userId: uid,
                        tokensGranted: add,
                        productId: TierTapProductId.credits.rawValue,
                        storeTransactionId: txn
                    )
                }
            }
        } else {
            applyLocalTierTapPlusGrant(amount: add)
            addPlusPurchaseToLocalCharts(amount: add)
            if let uid = supabaseUserId {
                await TierTapPlusPurchasesAPI.recordPurchase(
                    userId: uid,
                    tokensGranted: add,
                    productId: TierTapProductId.credits.rawValue,
                    storeTransactionId: txn
                )
            }
        }
    }

    /// Loads authoritative balances from Supabase for the signed-in user and mirrors them to `UserDefaults`.
    @MainActor
    func syncAITokenBalancesFromSupabaseSession() async {
        guard SupabaseConfig.isConfigured, let client = supabase else { return }
        guard (try? await client.auth.session) != nil else { return }
        do {
            let payload = try await TierTapUserAITokenBalancesAPI.fetchCurrentUserBalances()
            applyAITokenBalancesFromServer(payload)
        } catch {
            print("[SettingsStore] syncAITokenBalancesFromSupabaseSession failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func applyAITokenBalancesFromServer(_ p: AIUserTokenBalancesPayload) {
        aiPurchasedTokenBalance = max(0, p.purchased_balance_remaining)
        lifetimeTierTapPlusTokensPurchased = max(0, p.lifetime_plus_tokens_purchased)
        tierTapPlusTokensConsumedFromPurchases = max(0, p.consumed_from_packs)
        proPlanTokensConsumedThisMonth = max(0, p.pro_plan_tokens_consumed_month)
        UserDefaults.standard.set(aiPurchasedTokenBalance, forKey: keyAIPurchasedTokenBalance)
        UserDefaults.standard.set(lifetimeTierTapPlusTokensPurchased, forKey: keyAILifetimeTierTapPlusTokensPurchased)
        UserDefaults.standard.set(tierTapPlusTokensConsumedFromPurchases, forKey: keyAITierTapPlusTokensConsumedFromPacks)
        UserDefaults.standard.set(proPlanTokensConsumedThisMonth, forKey: keyAIProPlanTokensConsumed)
        let month = p.pro_plan_month_key.trimmingCharacters(in: .whitespacesAndNewlines)
        if !month.isEmpty {
            UserDefaults.standard.set(month, forKey: keyAIProPlanTokenMonth)
        }
    }

    @MainActor
    private func applyLocalTierTapPlusGrant(amount: Int) {
        let add = max(0, amount)
        guard add > 0 else { return }
        aiPurchasedTokenBalance += add
        UserDefaults.standard.set(aiPurchasedTokenBalance, forKey: keyAIPurchasedTokenBalance)
        lifetimeTierTapPlusTokensPurchased += add
        UserDefaults.standard.set(lifetimeTierTapPlusTokensPurchased, forKey: keyAILifetimeTierTapPlusTokensPurchased)
    }

    @MainActor
    private func addPlusPurchaseToLocalCharts(amount: Int) {
        let add = max(0, amount)
        guard add > 0 else { return }
        let dayKey = Self.telemetryDayKey(for: Date())
        var next = aiDayTelemetry
        var day = next[dayKey] ?? AIDayTelemetry()
        day.plusTokensPurchased += add
        next[dayKey] = day
        Self.pruneAIDayTelemetry(&next)
        aiDayTelemetry = next
        if let data = try? JSONEncoder().encode(aiDayTelemetry) {
            UserDefaults.standard.set(data, forKey: keyAIDayTelemetry)
        }
    }

    /// Called after each successful remote AI request (Gemini text/image or Imagen). Adds token totals when known.
    /// When `hasProAccess` is true, usage counts against the monthly Pro included allowance first, then against ``aiPurchasedTokenBalance``.
    func recordAITelemetry(invocationTokens: Int, hasProAccess: Bool = false) {
        let key = Self.telemetryDayKey(for: Date())
        var next = aiDayTelemetry
        var day = next[key] ?? AIDayTelemetry()
        day.tokens += max(0, invocationTokens)
        day.aiFeaturesUsed += 1
        next[key] = day
        Self.pruneAIDayTelemetry(&next)
        aiDayTelemetry = next
        if let data = try? JSONEncoder().encode(aiDayTelemetry) {
            UserDefaults.standard.set(data, forKey: keyAIDayTelemetry)
        }
        if SupabaseConfig.isConfigured, hasProAccess, max(0, invocationTokens) > 0 {
            Task { @MainActor in
                await applyGeminiServerOrLocalSpend(invocationTokens: invocationTokens)
            }
        } else {
            applyProAndPurchasedGeminiTokenSpend(invocationTokens: invocationTokens, hasProAccess: hasProAccess)
        }
    }

    @MainActor
    private func applyGeminiServerOrLocalSpend(invocationTokens: Int) async {
        let t = max(0, invocationTokens)
        guard t > 0 else { return }
        guard SupabaseConfig.isConfigured, let client = supabase else {
            applyProAndPurchasedGeminiTokenSpend(invocationTokens: t, hasProAccess: true)
            return
        }
        guard (try? await client.auth.session) != nil else {
            applyProAndPurchasedGeminiTokenSpend(invocationTokens: t, hasProAccess: true)
            return
        }
        do {
            let payload = try await TierTapUserAITokenBalancesAPI.applyGeminiTokenUsage(invocationTokens: t)
            applyAITokenBalancesFromServer(payload)
        } catch {
            print("[SettingsStore] applyGeminiTokenUsage server failed, using local spend: \(error.localizedDescription)")
            applyProAndPurchasedGeminiTokenSpend(invocationTokens: t, hasProAccess: true)
        }
    }

    private func applyProAndPurchasedGeminiTokenSpend(invocationTokens: Int, hasProAccess: Bool) {
        guard hasProAccess else { return }
        let tokens = max(0, invocationTokens)
        guard tokens > 0 else { return }

        let monthKey = Self.proPlanMonthKey(for: Date())
        let storedMonth = UserDefaults.standard.string(forKey: keyAIProPlanTokenMonth) ?? ""
        if storedMonth != monthKey {
            proPlanTokensConsumedThisMonth = 0
            UserDefaults.standard.set(monthKey, forKey: keyAIProPlanTokenMonth)
            UserDefaults.standard.set(0, forKey: keyAIProPlanTokensConsumed)
        }

        let allowance = effectiveProPlanIncludedTokensPerCalendarMonth
        let allowanceRemaining = max(0, allowance - proPlanTokensConsumedThisMonth)
        let fromPlan = min(tokens, allowanceRemaining)
        if fromPlan > 0 {
            proPlanTokensConsumedThisMonth += fromPlan
            UserDefaults.standard.set(proPlanTokensConsumedThisMonth, forKey: keyAIProPlanTokensConsumed)
        }

        let fromPurchasedNeed = tokens - fromPlan
        guard fromPurchasedNeed > 0 else { return }
        let take = min(fromPurchasedNeed, aiPurchasedTokenBalance)
        guard take > 0 else { return }
        aiPurchasedTokenBalance -= take
        tierTapPlusTokensConsumedFromPurchases += take
        UserDefaults.standard.set(aiPurchasedTokenBalance, forKey: keyAIPurchasedTokenBalance)
        UserDefaults.standard.set(tierTapPlusTokensConsumedFromPurchases, forKey: keyAITierTapPlusTokensConsumedFromPacks)
    }

    private static func pruneAIDayTelemetry(_ dict: inout [String: AIDayTelemetry]) {
        let cal = Calendar.current
        guard let cutoff = cal.date(byAdding: .day, value: -180, to: cal.startOfDay(for: Date())) else { return }
        let cutoffKey = telemetryDayKey(for: cutoff, calendar: cal)
        dict = dict.filter { $0.key >= cutoffKey }
    }

    /// Record a bankroll reset to a new value (e.g. from Bankroll screen). Updates `bankroll` and persists to SQLite.
    func resetBankroll(to newValue: Int) {
        bankroll = newValue
        let event = BankrollResetEvent(date: Date(), value: newValue)
        BankrollDatabase.shared.insertReset(date: event.date, value: event.value)
        bankrollResets = BankrollDatabase.shared.fetchResets()
    }

    // MARK: - Last game defaults

    /// Updates saved table or poker defaults from a persisted session (e.g. close-out or add past session).
    func recordLastPlayedGameChoices(from session: Session) {
        let cat = session.gameCategory ?? .table
        if cat == .poker {
            let prevCost = lastPokerSessionDefaults?.pokerTournamentCostText ?? "0"
            lastPokerSessionDefaults = LastPokerSessionDefaults(
                pokerGameKind: session.pokerGameKind ?? .cash,
                pokerAllowsRebuy: session.pokerAllowsRebuy ?? false,
                pokerAllowsAddOn: session.pokerAllowsAddOn ?? false,
                pokerHasFreezeOut: session.pokerHasFreeOut ?? false,
                pokerVariant: session.pokerVariant ?? "No Limit Texas Hold’em",
                pokerSmallBlind: session.pokerSmallBlind ?? 0,
                pokerBigBlind: session.pokerBigBlind ?? 0,
                pokerAnte: session.pokerAnte ?? 0,
                pokerLevelMinutesText: session.pokerLevelMinutes.map { String($0) } ?? "",
                pokerStartingStackText: session.pokerStartingStack.map { String($0) } ?? "",
                pokerTournamentCostText: prevCost
            )
        } else if cat == .slots {
            if !session.game.isEmpty {
                lastSlotGameName = session.game
            }
            lastSlotSessionDefaults = LastSlotSessionDefaults(
                slotNotes: session.slotNotes ?? ""
            )
        } else {
            let isPokerSession = session.gameCategory == .poker
                || session.pokerGameKind != nil
                || session.pokerVariant != nil
            if !isPokerSession && !session.game.isEmpty {
                lastTableGameName = session.game
            }
        }
    }

    /// Persists the full check-in selection, including fields not stored on `Session` (e.g. tournament cost).
    func recordLastCheckInGameSelection(
        gameCategory: SessionGameCategory,
        selectedGame: String,
        pokerGameKind: SessionPokerGameKind,
        pokerAllowsRebuy: Bool,
        pokerAllowsAddOn: Bool,
        pokerHasFreezeOut: Bool,
        pokerVariant: String,
        pokerSmallBlind: Int,
        pokerBigBlind: Int,
        pokerAnte: Int,
        pokerLevelMinutesText: String,
        pokerStartingStackText: String,
        pokerTournamentCostText: String,
        slotNotes: String = ""
    ) {
        if gameCategory == .poker {
            lastPokerSessionDefaults = LastPokerSessionDefaults(
                pokerGameKind: pokerGameKind,
                pokerAllowsRebuy: pokerAllowsRebuy,
                pokerAllowsAddOn: pokerAllowsAddOn,
                pokerHasFreezeOut: pokerHasFreezeOut,
                pokerVariant: pokerVariant,
                pokerSmallBlind: pokerSmallBlind,
                pokerBigBlind: pokerBigBlind,
                pokerAnte: pokerAnte,
                pokerLevelMinutesText: pokerLevelMinutesText,
                pokerStartingStackText: pokerStartingStackText,
                pokerTournamentCostText: pokerTournamentCostText
            )
        } else if gameCategory == .slots {
            if !selectedGame.isEmpty {
                lastSlotGameName = selectedGame
            }
            lastSlotSessionDefaults = LastSlotSessionDefaults(slotNotes: slotNotes)
        } else if gameCategory == .table, !selectedGame.isEmpty {
            lastTableGameName = selectedGame
        }
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

    /// Same chip grid as check-in / past-session buy-in: settings denominations plus common squares, up to 100k.
    var buyInGridAmounts: [Int] {
        let base = effectiveDenominations
        let denoms = base.isEmpty ? [100, 200, 300, 500, 1000, 2000, 5000, 10_000] : base
        var set: Set<Int> = Set(denoms)

        for d in denoms {
            set.insert(d)
            set.insert(d * 2)
            set.insert(d * 3)
            if d >= 100 { set.insert(d / 2) }
        }

        set.insert(25); set.insert(50); set.insert(75); set.insert(150); set.insert(250); set.insert(750)

        let maxTarget = 100_000
        let step = 1_000
        let currentMax = set.max() ?? 0
        if currentMax < maxTarget {
            var next = max(step, ((currentMax + step - 1) / step) * step)
            while next <= maxTarget {
                set.insert(next)
                next += step
            }
        }

        return set.sorted()
    }

    private var themeSnapshot: TierTapThemeSettings.Snapshot {
        TierTapThemeSettings.Snapshot(
            primaryColorName: primaryColorName,
            secondaryColorName: secondaryColorName,
            primaryColorHex: primaryColorHex,
            secondaryColorHex: secondaryColorHex,
            themePresets: themePresets
        )
    }

    var primaryColor: Color {
        TierTapThemeSettings.primaryColor(in: themeSnapshot)
    }

    var secondaryColor: Color {
        TierTapThemeSettings.secondaryColor(in: themeSnapshot)
    }

    var effectivePrimaryHex: String {
        TierTapThemeSettings.effectivePrimaryHex(in: themeSnapshot)
    }

    var effectiveSecondaryHex: String {
        TierTapThemeSettings.effectiveSecondaryHex(in: themeSnapshot)
    }

    var primaryGradient: LinearGradient {
        TierTapThemeSettings.primaryGradient(in: themeSnapshot)
    }

    /// Update and persist the primary theme color.
    func setPrimaryColor(_ color: Color) {
        var snap = themeSnapshot
        TierTapThemeSettings.setPrimaryColor(color, in: &snap)
        primaryColorHex = snap.primaryColorHex
        primaryColorName = snap.primaryColorName
    }

    /// Update and persist the secondary theme color.
    func setSecondaryColor(_ color: Color) {
        var snap = themeSnapshot
        TierTapThemeSettings.setSecondaryColor(color, in: &snap)
        secondaryColorHex = snap.secondaryColorHex
        secondaryColorName = snap.secondaryColorName
    }

    /// Apply a given theme preset to the current settings.
    func applyThemePreset(_ preset: ThemePreset) {
        var snap = themeSnapshot
        TierTapThemeSettings.applyThemePreset(preset, to: &snap)
        primaryColorHex = snap.primaryColorHex
        primaryColorName = snap.primaryColorName
        secondaryColorHex = snap.secondaryColorHex
        secondaryColorName = snap.secondaryColorName
    }

    /// Persist the current primary/secondary colors as a new preset.
    func saveCurrentThemeAsPreset() {
        var snap = themeSnapshot
        TierTapThemeSettings.saveCurrentThemeAsPreset(in: &snap)
        themePresets = snap.themePresets
    }

    /// Convenience for turning a preset into concrete SwiftUI colors.
    func colors(for preset: ThemePreset) -> (Color, Color) {
        TierTapThemeSettings.colors(for: preset)
    }
}
