import SwiftUI

/// Resolved primary/secondary theme for watch UI (from ``TierTapThemeStore``).
struct WatchThemePalette: Equatable {
    var primary: Color
    var secondary: Color

    static let `default` = WatchThemePalette(primary: .black, secondary: .blue)

    init(primary: Color, secondary: Color) {
        self.primary = primary
        self.secondary = secondary
    }

    init(from store: TierTapThemeStore) {
        primary = store.primaryColor
        secondary = store.secondaryColor
    }

    var gradient: LinearGradient {
        LinearGradient(
            colors: [primary, secondary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    func metricAccent(at index: Int) -> Color {
        index.isMultiple(of: 2) ? primary : secondary
    }

    func timerFill(hasLive: Bool, paused: Bool) -> Color {
        if !hasLive { return primary }
        return paused ? secondary : primary
    }

    var onPrimaryButtonLabel: Color { .white }

    var successColor: Color { primary }
    var queuedColor: Color { secondary }

    var tileBackground: Color { primary.opacity(0.14) }
    var tileStroke: Color { secondary.opacity(0.35) }

    var celebrationGradientLead: Color { primary.opacity(0.52) }
}

private struct WatchThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue = WatchThemePalette.default
}

extension EnvironmentValues {
    var watchTheme: WatchThemePalette {
        get { self[WatchThemeEnvironmentKey.self] }
        set { self[WatchThemeEnvironmentKey.self] = newValue }
    }
}

private struct WatchThemedScreenBackground: ViewModifier {
    @Environment(\.watchTheme) private var theme

    func body(content: Content) -> some View {
        ZStack {
            theme.gradient.ignoresSafeArea()
            content
        }
    }
}

struct WatchThemedActionChipModifier: ViewModifier {
    @Environment(\.watchTheme) private var theme
    var compact: Bool = false

    func body(content: Content) -> some View {
        content
            .foregroundStyle(theme.onPrimaryButtonLabel)
            .padding(.vertical, compact ? 4 : 6)
            .background(theme.primary)
            .clipShape(RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous))
    }
}

extension View {
    func watchThemedScreen() -> some View {
        modifier(WatchThemedScreenBackground())
    }

    func watchThemedActionChip(compact: Bool = false) -> some View {
        modifier(WatchThemedActionChipModifier(compact: compact))
    }
}
