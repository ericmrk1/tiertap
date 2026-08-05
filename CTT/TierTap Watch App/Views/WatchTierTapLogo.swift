import SwiftUI
#if os(watchOS)
import WatchKit
#endif

/// Full TierTap wordmark (not the watch app icon).
struct WatchTierTapLogo: View {
    enum Style {
        /// Main menu header above Live Remote.
        case header
        /// Launch splash.
        case splash
        /// Idle / no-session state.
        case idle
    }

    let style: Style
    /// When set, sizes the logo to this width (e.g. full watch screen). Falls back to screen width.
    var width: CGFloat?

    var body: some View {
        Image("TierTapLogo")
            .resizable()
            .scaledToFit()
            .frame(width: resolvedWidth)
            .accessibilityLabel("TierTap")
    }

    private var resolvedWidth: CGFloat {
        width ?? WatchTierTapLogo.watchScreenWidth
    }

    static var watchScreenWidth: CGFloat {
        #if os(watchOS)
        WKInterfaceDevice.current().screenBounds.width
        #else
        200
        #endif
    }
}

struct WatchSplashScreen: View {
    var onFinished: () -> Void

    @EnvironmentObject private var themeStore: TierTapThemeStore
    @Environment(\.tierTapWatchAnimationsEnabled) private var tierTapWatchAnimationsEnabled
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var logoScale: CGFloat = 1
    @State private var didScheduleSequence = false

    /// Hold on screen before the zoom-out sequence (iPhone uses ~0.85s; watch stays longer).
    private static let holdBeforeZoom: TimeInterval = 2.75
    private static let blowUpDuration: TimeInterval = 0.6
    private static let collapseDuration: TimeInterval = 0.28
    private static let blowUpTargetScale: CGFloat = 50
    private static let collapseTargetScale: CGFloat = 0.01

    private var motionOK: Bool {
        tierTapWatchAnimationsEnabled && !accessibilityReduceMotion
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                themeStore.primaryGradient.ignoresSafeArea()
                WatchTierTapLogo(style: .splash, width: geo.size.width)
                    .scaleEffect(logoScale)
            }
            .onAppear {
                guard !didScheduleSequence, geo.size.width > 10 else { return }
                didScheduleSequence = true
                scheduleSplashAnimation()
            }
        }
    }

    private func scheduleSplashAnimation() {
        if motionOK {
            let afterZoom = Self.holdBeforeZoom + Self.blowUpDuration
            let afterCollapse = afterZoom + Self.collapseDuration

            DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdBeforeZoom) {
                withAnimation(.easeIn(duration: Self.blowUpDuration)) {
                    logoScale = Self.blowUpTargetScale
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + afterZoom) {
                withAnimation(.easeOut(duration: Self.collapseDuration)) {
                    logoScale = Self.collapseTargetScale
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + afterCollapse) {
                onFinished()
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdBeforeZoom) {
                onFinished()
            }
        }
    }
}
