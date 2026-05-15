import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ThemePreset: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var primaryHex: String
    var secondaryHex: String
}

/// Primary/secondary theme colors shared between iPhone and Apple Watch (App Group + standard defaults).
enum TierTapThemeSettings {
    static let appGroupSuiteName = "group.com.app.tiertap"

    static let keyPrimaryColorName = "ctt_primary_color_name"
    static let keySecondaryColorName = "ctt_secondary_color_name"
    static let keyPrimaryColorHex = "ctt_primary_color_hex"
    static let keySecondaryColorHex = "ctt_secondary_color_hex"
    static let keyThemePresets = "ctt_theme_presets"
    private static let keyDidMigrateToAppGroup = "ctt_theme_migrated_to_app_group"

    struct Snapshot: Equatable {
        var primaryColorName: String
        var secondaryColorName: String
        var primaryColorHex: String?
        var secondaryColorHex: String?
        var themePresets: [ThemePreset]
    }

    static func load(userDefaults: UserDefaults? = sharedDefaults) -> Snapshot {
        migrateFromStandardUserDefaultsIfNeeded()
        let primaryName = readString(keyPrimaryColorName, from: userDefaults) ?? "black"
        let secondaryName = readString(keySecondaryColorName, from: userDefaults) ?? "blue"
        let presets = loadPresets(from: userDefaults)
        return Snapshot(
            primaryColorName: primaryName,
            secondaryColorName: secondaryName,
            primaryColorHex: readString(keyPrimaryColorHex, from: userDefaults),
            secondaryColorHex: readString(keySecondaryColorHex, from: userDefaults),
            themePresets: presets.isEmpty ? builtInPresets() : presets
        )
    }

    static func save(_ snapshot: Snapshot, userDefaults: UserDefaults? = sharedDefaults) {
        writeString(snapshot.primaryColorName, forKey: keyPrimaryColorName, to: userDefaults)
        writeString(snapshot.secondaryColorName, forKey: keySecondaryColorName, to: userDefaults)
        writeOptionalHex(snapshot.primaryColorHex, forKey: keyPrimaryColorHex, to: userDefaults)
        writeOptionalHex(snapshot.secondaryColorHex, forKey: keySecondaryColorHex, to: userDefaults)
        if let data = try? JSONEncoder().encode(snapshot.themePresets) {
            userDefaults?.set(data, forKey: keyThemePresets)
            UserDefaults.standard.set(data, forKey: keyThemePresets)
        }
        UserDefaults.standard.set(snapshot.primaryColorName, forKey: keyPrimaryColorName)
        UserDefaults.standard.set(snapshot.secondaryColorName, forKey: keySecondaryColorName)
        if let hex = snapshot.primaryColorHex {
            UserDefaults.standard.set(hex, forKey: keyPrimaryColorHex)
        } else {
            UserDefaults.standard.removeObject(forKey: keyPrimaryColorHex)
        }
        if let hex = snapshot.secondaryColorHex {
            UserDefaults.standard.set(hex, forKey: keySecondaryColorHex)
        } else {
            UserDefaults.standard.removeObject(forKey: keySecondaryColorHex)
        }
    }

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupSuiteName)
    }

    static func primaryColor(in snapshot: Snapshot) -> Color {
        if let hex = snapshot.primaryColorHex, let c = color(fromHex: hex) { return c }
        return color(fromName: snapshot.primaryColorName)
    }

    static func secondaryColor(in snapshot: Snapshot) -> Color {
        if let hex = snapshot.secondaryColorHex, let c = color(fromHex: hex) { return c }
        return color(fromName: snapshot.secondaryColorName)
    }

    static func primaryGradient(in snapshot: Snapshot) -> LinearGradient {
        LinearGradient(
            colors: [primaryColor(in: snapshot), secondaryColor(in: snapshot)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func effectivePrimaryHex(in snapshot: Snapshot) -> String {
        snapshot.primaryColorHex ?? hexString(from: primaryColor(in: snapshot))
    }

    static func effectiveSecondaryHex(in snapshot: Snapshot) -> String {
        snapshot.secondaryColorHex ?? hexString(from: secondaryColor(in: snapshot))
    }

    static func setPrimaryColor(_ color: Color, in snapshot: inout Snapshot) {
        snapshot.primaryColorHex = hexString(from: color)
        snapshot.primaryColorName = nearestColorName(for: color)
    }

    static func setSecondaryColor(_ color: Color, in snapshot: inout Snapshot) {
        snapshot.secondaryColorHex = hexString(from: color)
        snapshot.secondaryColorName = nearestColorName(for: color)
    }

    static func applyThemePreset(_ preset: ThemePreset, to snapshot: inout Snapshot) {
        if let primary = color(fromHex: preset.primaryHex),
           let secondary = color(fromHex: preset.secondaryHex) {
            setPrimaryColor(primary, in: &snapshot)
            setSecondaryColor(secondary, in: &snapshot)
        }
    }

    static func colors(for preset: ThemePreset) -> (Color, Color) {
        let primary = color(fromHex: preset.primaryHex) ?? .black
        let secondary = color(fromHex: preset.secondaryHex) ?? .blue
        return (primary, secondary)
    }

    static func saveCurrentThemeAsPreset(in snapshot: inout Snapshot) {
        let primaryHexValue = effectivePrimaryHex(in: snapshot)
        let secondaryHexValue = effectiveSecondaryHex(in: snapshot)
        let primaryName = snapshot.primaryColorName.capitalized
        let secondaryName = snapshot.secondaryColorName.capitalized

        let baseName: String
        if primaryName.isEmpty && secondaryName.isEmpty {
            baseName = "Custom Theme"
        } else if primaryName == secondaryName {
            baseName = primaryName
        } else {
            baseName = "\(primaryName) → \(secondaryName)"
        }

        var candidateName = baseName
        let existingNames = Set(snapshot.themePresets.map(\.name))
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
        snapshot.themePresets.insert(newPreset, at: 0)
    }

    static func builtInPresets() -> [ThemePreset] {
        [
            ThemePreset(id: UUID(), name: "Royal Blue & Gold", primaryHex: hexString(from: .indigo), secondaryHex: hexString(from: .yellow)),
            ThemePreset(id: UUID(), name: "Apple Standard", primaryHex: hexString(from: .blue), secondaryHex: hexString(from: .teal)),
            ThemePreset(id: UUID(), name: "Emerald Night", primaryHex: hexString(from: .green), secondaryHex: hexString(from: .teal)),
            ThemePreset(id: UUID(), name: "Royal Blue", primaryHex: hexString(from: .indigo), secondaryHex: hexString(from: .blue)),
            ThemePreset(id: UUID(), name: "Sunset", primaryHex: hexString(from: .orange), secondaryHex: hexString(from: .pink)),
            ThemePreset(id: UUID(), name: "Gold Rush", primaryHex: hexString(from: .yellow), secondaryHex: hexString(from: .orange)),
            ThemePreset(id: UUID(), name: "Purple Royale", primaryHex: hexString(from: .purple), secondaryHex: hexString(from: .blue)),
            ThemePreset(id: UUID(), name: "Ocean Floor", primaryHex: hexString(from: .teal), secondaryHex: hexString(from: .blue)),
            ThemePreset(id: UUID(), name: "Vegas Neon", primaryHex: hexString(from: .pink), secondaryHex: hexString(from: .green)),
            ThemePreset(id: UUID(), name: "Midnight", primaryHex: hexString(from: .indigo), secondaryHex: hexString(from: .teal)),
            ThemePreset(id: UUID(), name: "High Roller", primaryHex: hexString(from: .green), secondaryHex: hexString(from: .yellow)),
            ThemePreset(id: UUID(), name: "Ice", primaryHex: hexString(from: .mint), secondaryHex: hexString(from: .blue))
        ]
    }

    // MARK: - Persistence helpers

    private static func migrateFromStandardUserDefaultsIfNeeded() {
        guard let group = sharedDefaults else { return }
        if group.bool(forKey: keyDidMigrateToAppGroup) { return }

        let standard = UserDefaults.standard
        if standard.object(forKey: keyPrimaryColorName) != nil {
            group.set(standard.string(forKey: keyPrimaryColorName), forKey: keyPrimaryColorName)
        }
        if standard.object(forKey: keySecondaryColorName) != nil {
            group.set(standard.string(forKey: keySecondaryColorName), forKey: keySecondaryColorName)
        }
        if let hex = standard.string(forKey: keyPrimaryColorHex) {
            group.set(hex, forKey: keyPrimaryColorHex)
        }
        if let hex = standard.string(forKey: keySecondaryColorHex) {
            group.set(hex, forKey: keySecondaryColorHex)
        }
        if let data = standard.data(forKey: keyThemePresets) {
            group.set(data, forKey: keyThemePresets)
        }
        group.set(true, forKey: keyDidMigrateToAppGroup)
    }

    private static func readString(_ key: String, from userDefaults: UserDefaults?) -> String? {
        if let value = userDefaults?.string(forKey: key) { return value }
        return UserDefaults.standard.string(forKey: key)
    }

    private static func writeString(_ value: String, forKey key: String, to userDefaults: UserDefaults?) {
        userDefaults?.set(value, forKey: key)
    }

    private static func writeOptionalHex(_ value: String?, forKey key: String, to userDefaults: UserDefaults?) {
        if let value {
            userDefaults?.set(value, forKey: key)
        } else {
            userDefaults?.removeObject(forKey: key)
        }
    }

    private static func loadPresets(from userDefaults: UserDefaults?) -> [ThemePreset] {
        let data = userDefaults?.data(forKey: keyThemePresets) ?? UserDefaults.standard.data(forKey: keyThemePresets)
        guard let data,
              let decoded = try? JSONDecoder().decode([ThemePreset].self, from: data) else {
            return []
        }
        return decoded
    }

    // MARK: - Color conversion

    static func color(fromHex hex: String) -> Color? {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }

    static func color(fromName name: String) -> Color {
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

    static func hexString(from color: Color) -> String {
        #if canImport(UIKit)
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
        return "#000000"
        #endif
    }

    static func nearestColorName(for color: Color) -> String {
        #if canImport(UIKit)
        let uiColor = UIColor(color)
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        if uiColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a) {
            let hue = h * 360.0
            if b < 0.25 {
                if s < 0.2 { return "black" }
                return "indigo"
            }
            if s < 0.2 { return b > 0.8 ? "yellow" : "mint" }
            switch hue {
            case 0..<20, 340...360: return "red"
            case 20..<50: return "orange"
            case 50..<80: return "yellow"
            case 80..<150: return "mint"
            case 150..<190: return "teal"
            case 190..<250: return "blue"
            case 250..<290: return "indigo"
            case 290..<320: return "purple"
            default: return "pink"
            }
        }
        #endif
        return "black"
    }
}

/// Observable theme state for watch UI (reloads from shared storage).
final class TierTapThemeStore: ObservableObject {
    @Published private(set) var snapshot: TierTapThemeSettings.Snapshot

    init() {
        snapshot = TierTapThemeSettings.load()
    }

    var primaryColor: Color { TierTapThemeSettings.primaryColor(in: snapshot) }
    var secondaryColor: Color { TierTapThemeSettings.secondaryColor(in: snapshot) }
    var primaryColorName: String { snapshot.primaryColorName }
    var secondaryColorName: String { snapshot.secondaryColorName }
    var primaryGradient: LinearGradient { TierTapThemeSettings.primaryGradient(in: snapshot) }
    var themePresets: [ThemePreset] { snapshot.themePresets }

    func reload() {
        snapshot = TierTapThemeSettings.load()
    }

    func setPrimaryColor(_ color: Color) {
        var next = snapshot
        TierTapThemeSettings.setPrimaryColor(color, in: &next)
        commit(next)
    }

    func setSecondaryColor(_ color: Color) {
        var next = snapshot
        TierTapThemeSettings.setSecondaryColor(color, in: &next)
        commit(next)
    }

    func applyThemePreset(_ preset: ThemePreset) {
        var next = snapshot
        TierTapThemeSettings.applyThemePreset(preset, to: &next)
        commit(next)
    }

    func saveCurrentThemeAsPreset() {
        var next = snapshot
        TierTapThemeSettings.saveCurrentThemeAsPreset(in: &next)
        commit(next)
    }

    func effectivePrimaryHex(for preset: ThemePreset) -> String {
        TierTapThemeSettings.effectivePrimaryHex(in: snapshot)
    }

    func isPresetSelected(_ preset: ThemePreset) -> Bool {
        preset.primaryHex == TierTapThemeSettings.effectivePrimaryHex(in: snapshot)
            && preset.secondaryHex == TierTapThemeSettings.effectiveSecondaryHex(in: snapshot)
    }

    private func commit(_ next: TierTapThemeSettings.Snapshot) {
        snapshot = next
        TierTapThemeSettings.save(next)
    }
}
