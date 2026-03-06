import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#endif

private let keyBankroll = "ctt_bankroll"
private let keyUnitSize = "ctt_unit_size"
private let keyTargetAverage = "ctt_target_average"
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

struct ThemePreset: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var primaryHex: String
    var secondaryHex: String
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

    init() {
        let b = UserDefaults.standard.integer(forKey: keyBankroll)
        self.bankroll = b > 0 ? b : 2000
        self.bankrollResets = BankrollDatabase.shared.fetchResets()
        let u = UserDefaults.standard.integer(forKey: keyUnitSize)
        self.unitSize = u > 0 ? u : 50
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
        self.primaryColorName = UserDefaults.standard.string(forKey: keyPrimaryColorName) ?? "green"
        self.secondaryColorName = UserDefaults.standard.string(forKey: keySecondaryColorName) ?? "blue"
        self.primaryColorHex = UserDefaults.standard.string(forKey: keyPrimaryColorHex)
        self.secondaryColorHex = UserDefaults.standard.string(forKey: keySecondaryColorHex)
        self.selectedLocationFilter = UserDefaults.standard.string(forKey: keySelectedLocationFilter)

        if let data = UserDefaults.standard.data(forKey: keyThemePresets),
           let decoded = try? JSONDecoder().decode([ThemePreset].self, from: data),
           !decoded.isEmpty {
            self.themePresets = decoded
        } else {
            let defaults: [ThemePreset] = [
                ThemePreset(id: UUID(), name: "Casino Dark", primaryHex: Self.hexString(from: .green), secondaryHex: Self.hexString(from: .blue)),
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

    /// Record a bankroll reset to a new value (e.g. from Bankroll screen). Updates `bankroll` and persists to SQLite.
    func resetBankroll(to newValue: Int) {
        bankroll = newValue
        let event = BankrollResetEvent(date: Date(), value: newValue)
        BankrollDatabase.shared.insertReset(date: event.date, value: event.value)
        bankrollResets = BankrollDatabase.shared.fetchResets()
    }

    // MARK: - Derived helpers

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
        let primary = color(fromHex: preset.primaryHex) ?? .green
        let secondary = color(fromHex: preset.secondaryHex) ?? .blue
        return (primary, secondary)
    }

    /// Fallback mapping from legacy color names to SwiftUI colors.
    private func color(fromName name: String) -> Color {
        switch name {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "mint": return .mint
        case "teal": return .teal
        case "blue": return .blue
        case "indigo": return .indigo
        case "purple": return .purple
        case "pink": return .pink
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
            return "#00FF00" // fall back to green
        }
        let value = (Int(r * 255) << 16) | (Int(g * 255) << 8) | Int(b * 255)
        return String(format: "#%06X", value)
        #else
        // Reasonable default on non-iOS platforms.
        return "#00FF00"
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
        return "green"
    }
}
