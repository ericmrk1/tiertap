import UIKit

/// Loads bundled `sf_symbol_names.txt` (one SF Symbol name per line) and keeps names that render on this OS.
enum SFSymbolCatalog {
    private static var _validated: [String]?

    static var validatedNames: [String] {
        if let _validated { return _validated }
        guard let url = Bundle.main.url(forResource: "sf_symbol_names", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            _validated = []
            return []
        }
        let raw = text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
        let filtered = raw.filter { UIImage(systemName: $0) != nil }.sorted()
        _validated = filtered
        return filtered
    }

    /// Short list shown before the user types a search query.
    static let suggestedSymbols: [String] = [
        "star.fill", "heart.fill", "leaf.fill", "flame.fill", "bolt.fill",
        "moon.fill", "sun.max.fill", "cloud.fill", "drop.fill", "snowflake",
        "figure.run", "figure.walk", "sportscourt.fill", "bicycle", "car.fill",
        "house.fill", "briefcase.fill", "book.fill", "pencil", "tray.full.fill",
        "bell.fill", "calendar", "clock.fill", "timer", "gift.fill",
        "cup.and.saucer.fill", "fork.knife", "takeoutbag.and.cup.and.straw.fill",
        "music.note", "headphones", "gamecontroller.fill", "paintbrush.fill",
        "camera.fill", "photo.fill", "flag.fill", "mappin.circle.fill",
        "checkmark.circle.fill", "xmark.circle.fill", "exclamationmark.triangle.fill",
    ].filter { UIImage(systemName: $0) != nil }
}
