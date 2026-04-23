import SwiftUI
import UIKit
import PhotosUI
import AVFoundation
import AVKit
import CoreImage

#if os(iOS)

// MARK: - Share item for plain text

private struct SessionArtShareTextItem: Identifiable {
    let id = UUID()
    let text: String
}

private struct SessionArtShareMediaItem: Identifiable {
    let id = UUID()
    let activityItems: [Any]
}

private let keySessionArtSharePreset = "ctt_session_art_share_preset_v1"

private struct SessionArtSharePreset: Codable {
    var outputKindRaw: String
    var artStyleRaw: String
    var publishTierPerHour: Bool
    var publishWinLoss: Bool
    var publishBuyInCashOut: Bool
    var publishCompDetails: Bool
    var selectedTemplateRaw: String
    var selectedTextFontRaw: String
    var globalTextScale: Double
    var selectedTextColorRaw: String
    var selectedTextBackgroundColorRaw: String
    var textBackgroundOpacity: Double
}

// MARK: - Underlay source

private enum SessionUnderlaySource: Hashable, Identifiable {
    case chipEstimator
    case compPhoto(UUID)

    var id: String {
        switch self {
        case .chipEstimator: return "chip"
        case .compPhoto(let u): return u.uuidString
        }
    }

    var label: String {
        switch self {
        case .chipEstimator: return "Session chip photo"
        case .compPhoto: return "Comp receipt"
        }
    }
}

// MARK: - Editable layout (canvas coords; typography scales from 1080pt-wide reference)
private let sessionArtReferenceWidth: CGFloat = 1080
private let sessionArtExportCanvas = CGSize(width: 2160, height: 3840)

private enum MetricLineKey: String, Hashable, CaseIterable {
    case tierBump
    case buyIn
    case cashOut
    case winLoss
    case winRate
    case tiersPerHour
    case comps
}

private enum SessionArtHeaderFocus: Equatable {
    case casino
    case game
}

private enum SessionArtTextFont: String, CaseIterable, Identifiable {
    case system
    case rounded
    case serif
    case mono

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .rounded: return "Rounded"
        case .serif: return "Serif"
        case .mono: return "Mono"
        }
    }
}

private enum SessionArtColorToken: String, CaseIterable, Identifiable {
    case white
    case black
    case mint
    case yellow
    case orange
    case red
    case blue
    case purple

    var id: String { rawValue }

    var label: String {
        switch self {
        case .white: return "White"
        case .black: return "Black"
        case .mint: return "Mint"
        case .yellow: return "Yellow"
        case .orange: return "Orange"
        case .red: return "Red"
        case .blue: return "Blue"
        case .purple: return "Purple"
        }
    }

    var uiColor: UIColor {
        switch self {
        case .white: return .white
        case .black: return .black
        case .mint: return .systemMint
        case .yellow: return .systemYellow
        case .orange: return .systemOrange
        case .red: return .systemRed
        case .blue: return .systemBlue
        case .purple: return .systemPurple
        }
    }

    var color: Color { Color(uiColor) }
}

private struct SessionArtLayout: Equatable {
    var headerOrigin: CGPoint
    var lineOrigins: [MetricLineKey: CGPoint]
    var footerCenter: CGPoint
    /// Multiplier on header typography (preview + export), typically 0.35…3.5.
    var headerScale: CGFloat = 1
    /// Multiplier on all metric line typography.
    var metricsScale: CGFloat = 1
    /// Multiplier on optional footer caption text.
    var footerScale: CGFloat = 1
    /// Multiplier on “by TierTap” branding.
    var brandingScale: CGFloat = 1
    /// Nudges branding from its default bottom-trailing anchor (design space).
    var brandingOffset: CGPoint = .zero
    /// Zoom on the underlay photo (>1 zooms in). Pairs with `underlayPan`.
    var underlayZoom: CGFloat = 1
    /// Pans the underlay in design space (pixels) after zoom.
    var underlayPan: CGPoint = .zero
    /// When false, the “by TierTap” chip is omitted (some templates hide it).
    var showBranding: Bool = true
    /// Which session label should be the large title in the header.
    var headerFocus: SessionArtHeaderFocus = .casino
    /// Optional metric to visually feature with larger typography.
    var emphasizedMetric: MetricLineKey? = nil
    /// Additional multiplier for the featured metric line.
    var emphasisScale: CGFloat = 1.4

    /// Stacked metric rows from top to bottom in `keys` order (same order as `activeLineKeys`).
    static func makeLineOriginsStacked(
        keys: [MetricLineKey],
        startY: CGFloat,
        rowStride: CGFloat,
        leftPadding: CGFloat
    ) -> [MetricLineKey: CGPoint] {
        var lineOrigins: [MetricLineKey: CGPoint] = [:]
        var y = startY
        for key in keys {
            lineOrigins[key] = CGPoint(x: leftPadding, y: y)
            y += rowStride
        }
        return lineOrigins
    }

    static func activeLineKeys(
        session: Session,
        publishTierPerHour: Bool,
        publishWinLoss: Bool,
        publishBuyInCashOut: Bool,
        publishCompDetails: Bool
    ) -> [MetricLineKey] {
        var keys: [MetricLineKey] = []
        if session.tierPointsEarned != nil { keys.append(.tierBump) }
        if publishBuyInCashOut, !session.buyInEvents.isEmpty {
            keys.append(.buyIn)
        }
        if publishBuyInCashOut, session.cashOut != nil {
            keys.append(.cashOut)
        }
        if publishWinLoss, session.winLoss != nil {
            keys.append(.winLoss)
            if session.winRatePerHour != nil { keys.append(.winRate) }
        }
        if publishTierPerHour, session.tiersPerHour != nil { keys.append(.tiersPerHour) }
        if publishCompDetails, !session.compEvents.isEmpty { keys.append(.comps) }
        return keys
    }

    static func `default`(
        session: Session,
        publishTierPerHour: Bool,
        publishWinLoss: Bool,
        publishBuyInCashOut: Bool,
        publishCompDetails: Bool,
        canvasSize: CGSize
    ) -> SessionArtLayout {
        SessionArtTemplate.balanced.makeLayout(
            session: session,
            publishTierPerHour: publishTierPerHour,
            publishWinLoss: publishWinLoss,
            publishBuyInCashOut: publishBuyInCashOut,
            publishCompDetails: publishCompDetails,
            canvasSize: canvasSize
        )
    }

    func scaledForCanvas(from source: CGSize, to target: CGSize) -> SessionArtLayout {
        guard source.width > 0, source.height > 0 else { return self }
        let sx = target.width / source.width
        let sy = target.height / source.height

        var scaledLines: [MetricLineKey: CGPoint] = [:]
        for (key, point) in lineOrigins {
            scaledLines[key] = CGPoint(x: point.x * sx, y: point.y * sy)
        }

        return SessionArtLayout(
            headerOrigin: CGPoint(x: headerOrigin.x * sx, y: headerOrigin.y * sy),
            lineOrigins: scaledLines,
            footerCenter: CGPoint(x: footerCenter.x * sx, y: footerCenter.y * sy),
            headerScale: headerScale,
            metricsScale: metricsScale,
            footerScale: footerScale,
            brandingScale: brandingScale,
            brandingOffset: CGPoint(x: brandingOffset.x * sx, y: brandingOffset.y * sy),
            underlayZoom: underlayZoom,
            underlayPan: CGPoint(x: underlayPan.x * sx, y: underlayPan.y * sy),
            showBranding: showBranding,
            headerFocus: headerFocus,
            emphasizedMetric: emphasizedMetric,
            emphasisScale: emphasisScale
        )
    }
}

// MARK: - Session art layout templates

private enum SessionArtTemplate: String, CaseIterable, Identifiable {
    case balanced
    case spotlight
    case railRight
    case lowerThird
    case minimal
    case hero
    case socialCard
    case bigRate
    case noteStory
    case tierBlast
    case cashFlex

    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .balanced: return "Classic"
        case .spotlight: return "Magazine"
        case .railRight: return "Pace rail"
        case .lowerThird: return "Cash-out"
        case .minimal: return "Rate mini"
        case .hero: return "W/L hero"
        case .socialCard: return "Social card"
        case .bigRate: return "Big rate"
        case .noteStory: return "Note story"
        case .tierBlast: return "Tier blast"
        case .cashFlex: return "Cash flex"
        }
    }

    func makeLayout(
        session: Session,
        publishTierPerHour: Bool,
        publishWinLoss: Bool,
        publishBuyInCashOut: Bool,
        publishCompDetails: Bool,
        canvasSize: CGSize
    ) -> SessionArtLayout {
        let w = canvasSize.width
        let h = canvasSize.height
        let s = max(1, w / sessionArtReferenceWidth)
        let pad: CGFloat = 36 * s
        let keys = SessionArtLayout.activeLineKeys(
            session: session,
            publishTierPerHour: publishTierPerHour,
            publishWinLoss: publishWinLoss,
            publishBuyInCashOut: publishBuyInCashOut,
            publishCompDetails: publishCompDetails
        )

        switch self {
        case .balanced:
            let rowStride = 132 * s
            return SessionArtLayout(
                headerOrigin: CGPoint(x: pad, y: pad),
                lineOrigins: SessionArtLayout.makeLineOriginsStacked(
                    keys: keys,
                    startY: h * 0.42,
                    rowStride: rowStride,
                    leftPadding: pad
                ),
                footerCenter: CGPoint(x: w * 0.5, y: h * 0.88),
                headerScale: 1,
                metricsScale: 1,
                footerScale: 1,
                brandingScale: 1,
                brandingOffset: .zero,
                underlayZoom: 1,
                underlayPan: .zero,
                showBranding: true,
                headerFocus: .casino,
                emphasizedMetric: .winLoss,
                emphasisScale: 1.32
            )

        case .spotlight:
            let rowStride = 142 * s
            return SessionArtLayout(
                headerOrigin: CGPoint(x: pad, y: pad),
                lineOrigins: SessionArtLayout.makeLineOriginsStacked(
                    keys: keys,
                    startY: h * 0.49,
                    rowStride: rowStride,
                    leftPadding: pad
                ),
                footerCenter: CGPoint(x: w * 0.5, y: h * 0.9),
                headerScale: 1.44,
                metricsScale: 1.02,
                footerScale: 1,
                brandingScale: 1,
                brandingOffset: .zero,
                underlayZoom: 1,
                underlayPan: .zero,
                showBranding: true,
                headerFocus: .game,
                emphasizedMetric: .winRate,
                emphasisScale: 1.4
            )

        case .railRight:
            let rowStride = 132 * s
            let xCol = w * 0.54
            return SessionArtLayout(
                headerOrigin: CGPoint(x: xCol, y: pad),
                lineOrigins: SessionArtLayout.makeLineOriginsStacked(
                    keys: keys,
                    startY: h * 0.33,
                    rowStride: rowStride,
                    leftPadding: xCol
                ),
                footerCenter: CGPoint(x: w * 0.72, y: h * 0.88),
                headerScale: 1,
                metricsScale: 0.98,
                footerScale: 0.95,
                brandingScale: 0.95,
                brandingOffset: CGPoint(x: -w * 0.04, y: 0),
                underlayZoom: 1,
                underlayPan: .zero,
                showBranding: true,
                headerFocus: .casino,
                emphasizedMetric: .tiersPerHour,
                emphasisScale: 1.38
            )

        case .lowerThird:
            let rowStride = 126 * s
            return SessionArtLayout(
                headerOrigin: CGPoint(x: pad, y: h * 0.06),
                lineOrigins: SessionArtLayout.makeLineOriginsStacked(
                    keys: keys,
                    startY: h * 0.56,
                    rowStride: rowStride,
                    leftPadding: pad
                ),
                footerCenter: CGPoint(x: w * 0.5, y: h * 0.93),
                headerScale: 1,
                metricsScale: 1,
                footerScale: 1.05,
                brandingScale: 1,
                brandingOffset: .zero,
                underlayZoom: 1,
                underlayPan: .zero,
                showBranding: true,
                headerFocus: .casino,
                emphasizedMetric: .cashOut,
                emphasisScale: 1.35
            )

        case .minimal:
            let rowStride = 124 * s
            return SessionArtLayout(
                headerOrigin: CGPoint(x: pad, y: pad),
                lineOrigins: SessionArtLayout.makeLineOriginsStacked(
                    keys: keys,
                    startY: h * 0.36,
                    rowStride: rowStride,
                    leftPadding: pad
                ),
                footerCenter: CGPoint(x: w * 0.5, y: h * 0.91),
                headerScale: 0.88,
                metricsScale: 0.9,
                footerScale: 0.95,
                brandingScale: 1,
                brandingOffset: .zero,
                underlayZoom: 1,
                underlayPan: .zero,
                showBranding: false,
                headerFocus: .casino,
                emphasizedMetric: .winRate,
                emphasisScale: 1.28
            )

        case .hero:
            let rowStride = 136 * s
            return SessionArtLayout(
                headerOrigin: CGPoint(x: pad, y: h * 0.06),
                lineOrigins: SessionArtLayout.makeLineOriginsStacked(
                    keys: keys,
                    startY: h * 0.55,
                    rowStride: rowStride,
                    leftPadding: pad
                ),
                footerCenter: CGPoint(x: w * 0.5, y: h * 0.84),
                headerScale: 1.28,
                metricsScale: 1.08,
                footerScale: 1.05,
                brandingScale: 1.05,
                brandingOffset: .zero,
                underlayZoom: 1.06,
                underlayPan: .zero,
                showBranding: true,
                headerFocus: .casino,
                emphasizedMetric: .winLoss,
                emphasisScale: 1.5
            )

        case .socialCard:
            let rowStride = 128 * s
            return SessionArtLayout(
                headerOrigin: CGPoint(x: pad, y: h * 0.05),
                lineOrigins: SessionArtLayout.makeLineOriginsStacked(
                    keys: keys,
                    startY: h * 0.45,
                    rowStride: rowStride,
                    leftPadding: pad
                ),
                footerCenter: CGPoint(x: w * 0.5, y: h * 0.87),
                headerScale: 1.22,
                metricsScale: 1.04,
                footerScale: 1.08,
                brandingScale: 1.02,
                brandingOffset: .zero,
                underlayZoom: 1.04,
                underlayPan: CGPoint(x: 0, y: -h * 0.015),
                showBranding: true,
                headerFocus: .game,
                emphasizedMetric: .winLoss,
                emphasisScale: 1.45
            )

        case .bigRate:
            let rowStride = 134 * s
            return SessionArtLayout(
                headerOrigin: CGPoint(x: pad, y: h * 0.07),
                lineOrigins: SessionArtLayout.makeLineOriginsStacked(
                    keys: keys,
                    startY: h * 0.5,
                    rowStride: rowStride,
                    leftPadding: pad
                ),
                footerCenter: CGPoint(x: w * 0.5, y: h * 0.9),
                headerScale: 1.12,
                metricsScale: 1.0,
                footerScale: 1.0,
                brandingScale: 1.0,
                brandingOffset: .zero,
                underlayZoom: 1.0,
                underlayPan: .zero,
                showBranding: true,
                headerFocus: .casino,
                emphasizedMetric: .winRate,
                emphasisScale: 1.62
            )

        case .noteStory:
            let rowStride = 118 * s
            return SessionArtLayout(
                headerOrigin: CGPoint(x: pad, y: h * 0.05),
                lineOrigins: SessionArtLayout.makeLineOriginsStacked(
                    keys: keys,
                    startY: h * 0.34,
                    rowStride: rowStride,
                    leftPadding: pad
                ),
                footerCenter: CGPoint(x: w * 0.5, y: h * 0.79),
                headerScale: 1.18,
                metricsScale: 0.88,
                footerScale: 1.85,
                brandingScale: 0.96,
                brandingOffset: CGPoint(x: 0, y: h * 0.01),
                underlayZoom: 1.08,
                underlayPan: CGPoint(x: 0, y: -h * 0.04),
                showBranding: true,
                headerFocus: .game,
                emphasizedMetric: .comps,
                emphasisScale: 1.26
            )

        case .tierBlast:
            let rowStride = 130 * s
            return SessionArtLayout(
                headerOrigin: CGPoint(x: pad, y: h * 0.06),
                lineOrigins: SessionArtLayout.makeLineOriginsStacked(
                    keys: keys,
                    startY: h * 0.52,
                    rowStride: rowStride,
                    leftPadding: pad
                ),
                footerCenter: CGPoint(x: w * 0.5, y: h * 0.89),
                headerScale: 1.16,
                metricsScale: 1.03,
                footerScale: 1.02,
                brandingScale: 1.0,
                brandingOffset: .zero,
                underlayZoom: 1.03,
                underlayPan: .zero,
                showBranding: true,
                headerFocus: .casino,
                emphasizedMetric: .tierBump,
                emphasisScale: 1.58
            )

        case .cashFlex:
            let rowStride = 132 * s
            return SessionArtLayout(
                headerOrigin: CGPoint(x: pad, y: h * 0.05),
                lineOrigins: SessionArtLayout.makeLineOriginsStacked(
                    keys: keys,
                    startY: h * 0.5,
                    rowStride: rowStride,
                    leftPadding: pad
                ),
                footerCenter: CGPoint(x: w * 0.5, y: h * 0.88),
                headerScale: 1.2,
                metricsScale: 1.04,
                footerScale: 1.08,
                brandingScale: 1.02,
                brandingOffset: .zero,
                underlayZoom: 1.05,
                underlayPan: .zero,
                showBranding: true,
                headerFocus: .game,
                emphasizedMetric: .cashOut,
                emphasisScale: 1.62
            )
        }
    }

    func renderThumbnail(
        session: Session,
        base: UIImage?,
        includeMetrics: Bool,
        publishTierPerHour: Bool,
        publishWinLoss: Bool,
        publishBuyInCashOut: Bool,
        publishCompDetails: Bool,
        currencySymbol: String,
        footerCaption: String,
        fontStyle: SessionArtTextFont = .system,
        textScale: CGFloat = 1,
        textColorToken: SessionArtColorToken = .white,
        textBackgroundColorToken: SessionArtColorToken = .black,
        textBackgroundOpacity: CGFloat = 0.45,
        canvasSize: CGSize = CGSize(width: 200, height: 356)
    ) -> UIImage {
        let lay = makeLayout(
            session: session,
            publishTierPerHour: publishTierPerHour,
            publishWinLoss: publishWinLoss,
            publishBuyInCashOut: publishBuyInCashOut,
            publishCompDetails: publishCompDetails,
            canvasSize: canvasSize
        )
        return SessionArtRenderer.renderImage(params: SessionArtRenderer.RenderParams(
            base: base,
            session: session,
            currencySymbol: currencySymbol,
            includeMetrics: includeMetrics,
            publishTierPerHour: publishTierPerHour,
            publishWinLoss: publishWinLoss,
            publishBuyInCashOut: publishBuyInCashOut,
            publishCompDetails: publishCompDetails,
            metricsReach: 1,
            counterGlobalT: nil,
            fontStyle: fontStyle,
            textScale: textScale,
            textColorToken: textColorToken,
            textBackgroundColorToken: textBackgroundColorToken,
            textBackgroundOpacity: textBackgroundOpacity,
            canvasSize: canvasSize,
            layout: lay,
            footerCaption: footerCaption
        ))
    }
}

// MARK: - Rendering

private enum SessionArtRenderer {
    private static func layoutScale(forCanvasWidth width: CGFloat) -> CGFloat {
        max(1, width / sessionArtReferenceWidth)
    }

    /// Conservative social-safe frame for IG/FB style shares (keeps text away from top/bottom chrome).
    private static func socialSafeFrame(in size: CGSize) -> CGRect {
        CGRect(
            x: size.width * 0.08,
            y: size.height * 0.08,
            width: size.width * 0.84,
            height: size.height * 0.78
        )
    }

    /// Find the largest readable font size that fits within the target width.
    private static func fittedFontSize(
        text: String,
        weight: UIFont.Weight,
        targetWidth: CGFloat,
        minSize: CGFloat,
        preferredSize: CGFloat,
        maxSize: CGFloat
    ) -> CGFloat {
        let target = max(40, targetWidth)
        let minV = max(8, minSize)
        var low = minV
        var high = max(minV, min(maxSize, preferredSize * 1.8))
        var best = minV

        for _ in 0..<14 {
            let mid = (low + high) * 0.5
            let font = UIFont.systemFont(ofSize: mid, weight: weight)
            let width = (text as NSString).size(withAttributes: [.font: font]).width
            if width <= target {
                best = mid
                low = mid
            } else {
                high = mid
            }
        }
        return best
    }

    struct RenderParams {
        var base: UIImage?
        var session: Session
        var currencySymbol: String
        var includeMetrics: Bool
        var publishTierPerHour: Bool
        var publishWinLoss: Bool
        var publishBuyInCashOut: Bool
        var publishCompDetails: Bool
        /// 0…1 opacity / simple scale for non-counter fades
        var metricsReach: CGFloat
        /// When set (e.g. video), each metric counts up with stagger using this global 0…1 progress
        var counterGlobalT: CGFloat?
        var fontStyle: SessionArtTextFont = .system
        var textScale: CGFloat = 1
        var textColorToken: SessionArtColorToken = .white
        var textBackgroundColorToken: SessionArtColorToken = .black
        var textBackgroundOpacity: CGFloat = 0.45
        var canvasSize: CGSize
        var layout: SessionArtLayout?
        var footerCaption: String
    }

    private static func styledFont(
        size: CGFloat,
        weight: UIFont.Weight,
        style: SessionArtTextFont
    ) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let desiredDesign: UIFontDescriptor.SystemDesign
        switch style {
        case .system:
            return base
        case .rounded:
            desiredDesign = .rounded
        case .serif:
            desiredDesign = .serif
        case .mono:
            desiredDesign = .monospaced
        }
        if let descriptor = base.fontDescriptor.withDesign(desiredDesign) {
            return UIFont(descriptor: descriptor, size: size)
        }
        return base
    }

    private static func resolvedTextColor(_ params: RenderParams) -> UIColor {
        params.textColorToken.uiColor
    }

    private static func resolvedTextBackgroundColor(_ params: RenderParams) -> UIColor {
        let alpha = min(0.95, max(0, params.textBackgroundOpacity))
        return params.textBackgroundColorToken.uiColor.withAlphaComponent(alpha)
    }

    static func renderImage(params: RenderParams) -> UIImage {
        let canvas = params.canvasSize
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: canvas, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            let layout = params.layout ?? SessionArtLayout.default(
                session: params.session,
                publishTierPerHour: params.publishTierPerHour,
                publishWinLoss: params.publishWinLoss,
                publishBuyInCashOut: params.publishBuyInCashOut,
                publishCompDetails: params.publishCompDetails,
                canvasSize: canvas
            )
            drawBackground(in: canvas, cg: cg)
            if let base = params.base {
                drawAspectFillUIImage(
                    base,
                    in: CGRect(origin: .zero, size: canvas),
                    zoom: layout.underlayZoom,
                    pan: layout.underlayPan,
                    cg: cg
                )
                if params.includeMetrics {
                    cg.setFillColor(UIColor.black.withAlphaComponent(0.42).cgColor)
                    cg.fill(CGRect(origin: .zero, size: canvas))
                }
            } else {
                cg.setFillColor(UIColor.black.withAlphaComponent(0.55).cgColor)
                cg.fill(CGRect(origin: .zero, size: canvas))
            }

            if params.includeMetrics {
                drawMetricsBlock(
                    params: params,
                    layout: layout,
                    in: canvas,
                    cg: cg
                )
            }

            drawHeader(params: params, layout: layout, in: canvas, cg: cg)
            if layout.showBranding {
                drawBranding(in: canvas, layout: layout, params: params, cg: cg)
            }
            drawFooterCaption(
                params.footerCaption,
                center: layout.footerCenter,
                footerScale: layout.footerScale,
                params: params,
                in: canvas,
                cg: cg
            )
        }
    }

    static func renderOverlayImage(params: RenderParams) -> UIImage {
        let canvas = params.canvasSize
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: canvas, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            let layout = params.layout ?? SessionArtLayout.default(
                session: params.session,
                publishTierPerHour: params.publishTierPerHour,
                publishWinLoss: params.publishWinLoss,
                publishBuyInCashOut: params.publishBuyInCashOut,
                publishCompDetails: params.publishCompDetails,
                canvasSize: canvas
            )

            if params.includeMetrics {
                cg.setFillColor(UIColor.black.withAlphaComponent(0.42).cgColor)
                cg.fill(CGRect(origin: .zero, size: canvas))
                drawMetricsBlock(
                    params: params,
                    layout: layout,
                    in: canvas,
                    cg: cg
                )
            }

            drawHeader(params: params, layout: layout, in: canvas, cg: cg)
            if layout.showBranding {
                drawBranding(in: canvas, layout: layout, params: params, cg: cg)
            }
            drawFooterCaption(
                params.footerCaption,
                center: layout.footerCenter,
                footerScale: layout.footerScale,
                params: params,
                in: canvas,
                cg: cg
            )
        }
    }

    private static func drawBackground(in size: CGSize, cg: CGContext) {
        cg.setFillColor(UIColor(red: 0.06, green: 0.12, blue: 0.08, alpha: 1).cgColor)
        cg.fill(CGRect(origin: .zero, size: size))
    }

    /// Uses UIKit drawing so photo orientation (EXIF) is respected. `zoom` scales above aspect-fill; `pan` shifts in canvas points.
    private static func drawAspectFillUIImage(
        _ image: UIImage,
        in rect: CGRect,
        zoom: CGFloat,
        pan: CGPoint,
        cg: CGContext
    ) {
        let iw = image.size.width * image.scale
        let ih = image.size.height * image.scale
        guard iw > 0, ih > 0 else { return }
        let scale0 = max(rect.width / iw, rect.height / ih)
        let z = min(4.5, max(0.35, zoom))
        let scale = scale0 * z
        let w = iw * scale
        let h = ih * scale
        let x = rect.midX - w / 2 + pan.x
        let y = rect.midY - h / 2 + pan.y
        cg.saveGState()
        cg.translateBy(x: x, y: y)
        cg.scaleBy(x: scale / image.scale, y: scale / image.scale)
        image.draw(in: CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height))
        cg.restoreGState()
    }

    private static let sessionArtHeaderDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = .current
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()

    /// Subtitle lines under the casino title on session art (date/time, typed game, duration).
    static func sessionArtHeaderSublines(session: Session) -> [String] {
        var lines: [String] = []
        lines.append(sessionArtHeaderDateFormatter.string(from: session.startTime))
        var typedGame = session.game
        if let cat = session.gameCategory {
            var prefix = cat.pickerTitle
            if cat == .poker, let kind = session.pokerGameKind {
                prefix += kind == .cash ? " · Cash" : " · Tournament"
            }
            typedGame = "\(prefix) · \(session.game)"
        }
        lines.append(typedGame)
        lines.append("Played \(shortPlayDuration(session.duration))")
        return lines
    }

    /// Design-space height from the header origin through the last subtitle line (for layout / drag badges).
    static func sessionArtHeaderStackHeight(session: Session, canvasWidth: CGFloat, headerScale: CGFloat) -> CGFloat {
        let s = layoutScale(forCanvasWidth: canvasWidth)
        let n = sessionArtHeaderSublines(session: session).count
        let hs = min(3.5, max(0.35, headerScale))
        return (42 * s + CGFloat(n) * 28 * s + 16 * s) * hs
    }

    private static func shortPlayDuration(_ interval: TimeInterval) -> String {
        let secs = max(0, Int(interval))
        let h = secs / 3600
        let m = (secs % 3600) / 60
        if h > 0, m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        if m > 0 { return "\(m)m" }
        return "under a minute"
    }

    private static func headerTitleAndSublines(session: Session, focus: SessionArtHeaderFocus) -> (title: String, sublines: [String]) {
        switch focus {
        case .casino:
            let title = session.casino.trimmingCharacters(in: .whitespacesAndNewlines)
            return (title.isEmpty ? "Casino session" : title, sessionArtHeaderSublines(session: session))
        case .game:
            let game = session.game.trimmingCharacters(in: .whitespacesAndNewlines)
            let casino = session.casino.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = game.isEmpty ? "Session recap" : game
            var sublines: [String] = []
            if !casino.isEmpty {
                sublines.append(casino)
            }
            sublines.append(sessionArtHeaderDateFormatter.string(from: session.startTime))
            sublines.append("Played \(shortPlayDuration(session.duration))")
            return (title, sublines)
        }
    }

    private static func drawHeader(params: RenderParams, layout: SessionArtLayout, in size: CGSize, cg: CGContext) {
        let session = params.session
        let origin = layout.headerOrigin
        let s = layoutScale(forCanvasWidth: size.width)
        let textScale = min(2.2, max(0.7, params.textScale))
        let hs = min(3.5, max(0.35, layout.headerScale * textScale))
        let header = headerTitleAndSublines(session: session, focus: layout.headerFocus)
        let safe = socialSafeFrame(in: size)
        let titleTargetWidth = size.width * 0.8
        let titleSize = fittedFontSize(
            text: header.title,
            weight: .bold,
            targetWidth: titleTargetWidth,
            minSize: 28 * s * hs,
            preferredSize: 48 * s * hs,
            maxSize: 140 * s
        )
        let titleFont = styledFont(size: titleSize, weight: .bold, style: params.fontStyle)
        let textColor = resolvedTextColor(params)
        let backgroundColor = resolvedTextBackgroundColor(params)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: textColor
        ]
        let subtitleColor = textColor.withAlphaComponent(max(0.55, min(1, 0.9)))
        let subtitleFont = styledFont(size: 22 * s * hs, weight: .medium, style: params.fontStyle)
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: subtitleFont,
            .foregroundColor: subtitleColor
        ]
        let title = header.title as NSString
        let titleWidth = title.size(withAttributes: attrs).width
        let titleX = max(safe.minX, min(safe.maxX - titleWidth, (size.width - titleWidth) * 0.5))
        let startY = max(safe.minY, origin.y)
        var linePlacements: [(line: NSString, x: CGFloat, y: CGFloat, width: CGFloat)] = []
        var y = startY + titleFont.lineHeight + 8 * s * hs
        for line in header.sublines {
            let ns = line as NSString
            let lineWidth = ns.size(withAttributes: subAttrs).width
            let x = max(safe.minX, min(safe.maxX - lineWidth, (size.width - lineWidth) * 0.5))
            linePlacements.append((line: ns, x: x, y: y, width: lineWidth))
            y += 28 * s * hs
        }

        var minX = titleX
        var maxX = titleX + titleWidth
        for placement in linePlacements {
            minX = min(minX, placement.x)
            maxX = max(maxX, placement.x + placement.width)
        }
        let textBottom = linePlacements.last.map { $0.y + subtitleFont.lineHeight } ?? (startY + titleFont.lineHeight)
        let bgPadX = 18 * s
        let bgPadY = 14 * s
        let bgRect = CGRect(
            x: minX - bgPadX,
            y: startY - bgPadY,
            width: maxX - minX + (bgPadX * 2),
            height: textBottom - startY + (bgPadY * 2)
        )
        if params.textBackgroundOpacity > 0.01 {
            cg.saveGState()
            cg.setFillColor(backgroundColor.cgColor)
            cg.addPath(UIBezierPath(roundedRect: bgRect, cornerRadius: 14 * s).cgPath)
            cg.fillPath()
            cg.restoreGState()
        }
        title.draw(at: CGPoint(x: titleX, y: startY), withAttributes: attrs)
        for placement in linePlacements {
            placement.line.draw(at: CGPoint(x: placement.x, y: placement.y), withAttributes: subAttrs)
        }
    }

    private static func drawBranding(in size: CGSize, layout: SessionArtLayout, params: RenderParams, cg: CGContext) {
        let text = "by TierTap" as NSString
        let s = layoutScale(forCanvasWidth: size.width)
        let textScale = min(2.2, max(0.7, params.textScale))
        let fontSize = fittedFontSize(
            text: "by TierTap",
            weight: .heavy,
            targetWidth: size.width * 0.34,
            minSize: 24 * s,
            preferredSize: 44 * s * min(3, max(0.35, layout.brandingScale * textScale)),
            maxSize: 120 * s
        )
        let font = styledFont(size: fontSize, weight: .semibold, style: params.fontStyle)
        let textColor = resolvedTextColor(params)
        let backgroundColor = resolvedTextBackgroundColor(params)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        let tw = text.size(withAttributes: attrs).width
        let pad: CGFloat = max(24, fontSize * 1.1)
        let point = CGPoint(
            x: size.width - tw - pad + layout.brandingOffset.x,
            y: size.height - font.lineHeight - pad + layout.brandingOffset.y
        )
        let bgRect = CGRect(x: point.x - 12, y: point.y - 8, width: tw + 24, height: font.lineHeight + 16)
        if params.textBackgroundOpacity > 0.01 {
            cg.saveGState()
            cg.setFillColor(backgroundColor.cgColor)
            cg.addPath(UIBezierPath(roundedRect: bgRect, cornerRadius: 10 * s).cgPath)
            cg.fillPath()
            cg.restoreGState()
        }
        text.draw(at: point, withAttributes: attrs)
    }

    private static func drawFooterCaption(
        _ caption: String,
        center: CGPoint,
        footerScale: CGFloat,
        params: RenderParams,
        in size: CGSize,
        cg: CGContext
    ) {
        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let s = layoutScale(forCanvasWidth: size.width)
        let textScale = min(2.2, max(0.7, params.textScale))
        let fs = min(3.5, max(0.35, footerScale * textScale))
        let font = styledFont(size: 26 * s * fs, weight: .semibold, style: params.fontStyle)
        let textColor = resolvedTextColor(params)
        let backgroundColor = resolvedTextBackgroundColor(params)
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: para
        ]
        let maxW = size.width - 48 * s
        let ns = trimmed as NSString
        let bounds = ns.boundingRect(
            with: CGSize(width: maxW, height: 200),
            options: [.usesLineFragmentOrigin],
            attributes: attrs,
            context: nil
        )
        let drawRect = CGRect(
            x: center.x - bounds.width / 2,
            y: center.y - bounds.height / 2,
            width: bounds.width,
            height: bounds.height
        )
        if params.textBackgroundOpacity > 0.01 {
            cg.saveGState()
            cg.setFillColor(backgroundColor.cgColor)
            let padX = 10 * s * fs
            let padY = 8 * s * fs
            let bgRect = drawRect.insetBy(dx: -padX, dy: -padY)
            cg.addPath(UIBezierPath(roundedRect: bgRect, cornerRadius: 10 * s).cgPath)
            cg.fillPath()
            cg.restoreGState()
        }
        ns.draw(in: drawRect, withAttributes: attrs)
    }

    /// Per-line counter progress with stagger so each metric “ticks” up after the previous starts.
    private static func lineCounterMultiplier(lineIndex: Int, globalT: CGFloat) -> CGFloat {
        let stagger = CGFloat(lineIndex) * 0.07
        let dur: CGFloat = 0.55
        let t = (globalT - stagger) / dur
        let s = min(1, max(0, t))
        return s * s * (3 - 2 * s)
    }

    private static func drawMetricsBlock(
        params: RenderParams,
        layout: SessionArtLayout,
        in size: CGSize,
        cg: CGContext
    ) {
        let session = params.session
        let mReach = params.metricsReach
        let useCounters = params.counterGlobalT != nil
        let gT = params.counterGlobalT ?? 0

        let s = layoutScale(forCanvasWidth: size.width)
        let textScale = min(2.2, max(0.7, params.textScale))
        let ms = min(3.5, max(0.35, layout.metricsScale * textScale))
        let emphasisScale = min(2.0, max(1.0, layout.emphasisScale))
        let safe = socialSafeFrame(in: size)
        let keys = SessionArtLayout.activeLineKeys(
            session: session,
            publishTierPerHour: params.publishTierPerHour,
            publishWinLoss: params.publishWinLoss,
            publishBuyInCashOut: params.publishBuyInCashOut,
            publishCompDetails: params.publishCompDetails
        )

        func multiplier(forLineIndex idx: Int) -> CGFloat {
            if useCounters {
                return lineCounterMultiplier(lineIndex: idx, globalT: gT)
            }
            return mReach
        }

        let textColor = resolvedTextColor(params)
        let metricTitleColor = textColor.withAlphaComponent(0.92)
        let metricValueColor = textColor
        let metricBackgroundColor = resolvedTextBackgroundColor(params)

        func paintMetricLine(title: String, value: String, key: MetricLineKey) {
            let origin = layout.lineOrigins[key] ?? CGPoint(x: 36 * s, y: size.height * 0.42)
            let isEmphasized = layout.emphasizedMetric == key
            let titleFont: UIFont
            let valueFont: UIFont
            let titleX: CGFloat
            let valueX: CGFloat

            if isEmphasized {
                // Hero metric should dominate ~80% of the canvas width.
                let heroTargetWidth = size.width * 0.8
                let titleSize = fittedFontSize(
                    text: title.uppercased(),
                    weight: .heavy,
                    targetWidth: heroTargetWidth * 0.92,
                    minSize: 20 * s,
                    preferredSize: 38 * s * ms,
                    maxSize: 84 * s
                )
                let valueSize = fittedFontSize(
                    text: value,
                    weight: .black,
                    targetWidth: heroTargetWidth,
                    minSize: 34 * s,
                    preferredSize: 64 * s * ms * emphasisScale,
                    maxSize: 220 * s
                )
                titleFont = styledFont(size: titleSize, weight: .heavy, style: params.fontStyle)
                valueFont = styledFont(size: valueSize, weight: .black, style: params.fontStyle)
                let tw = (title as NSString).size(withAttributes: [.font: titleFont]).width
                let vw = (value as NSString).size(withAttributes: [.font: valueFont]).width
                titleX = max(safe.minX, min(safe.maxX - tw, (size.width - tw) * 0.5))
                valueX = max(safe.minX, min(safe.maxX - vw, (size.width - vw) * 0.5))
            } else {
                titleFont = styledFont(size: 34 * s * ms, weight: .bold, style: params.fontStyle)
                valueFont = styledFont(size: 52 * s * ms, weight: .heavy, style: params.fontStyle)
                titleX = origin.x
                valueX = origin.x
            }
            let ta: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: metricTitleColor
            ]
            let va: [NSAttributedString.Key: Any] = [
                .font: valueFont,
                .foregroundColor: metricValueColor
            ]
            let safeY = max(safe.minY, min(origin.y, safe.maxY - titleFont.lineHeight - valueFont.lineHeight - 24 * s))
            let valueBaseline = safeY + titleFont.lineHeight + 10 * s * ms
            let titleWidth = (title as NSString).size(withAttributes: ta).width
            let valueWidth = (value as NSString).size(withAttributes: va).width
            let minX = min(titleX, valueX)
            let maxX = max(titleX + titleWidth, valueX + valueWidth)
            let bgRect = CGRect(
                x: minX - 14 * s,
                y: safeY - 10 * s,
                width: (maxX - minX) + 28 * s,
                height: (valueBaseline + valueFont.lineHeight - safeY) + 18 * s
            )
            if params.textBackgroundOpacity > 0.01 {
                cg.saveGState()
                cg.setFillColor(metricBackgroundColor.cgColor)
                cg.addPath(UIBezierPath(roundedRect: bgRect, cornerRadius: 12 * s).cgPath)
                cg.fillPath()
                cg.restoreGState()
            }
            (title as NSString).draw(at: CGPoint(x: titleX, y: safeY), withAttributes: ta)
            (value as NSString).draw(at: CGPoint(x: valueX, y: valueBaseline), withAttributes: va)
        }

        if let earned = session.tierPointsEarned, keys.contains(.tierBump) {
            let idx = keys.firstIndex(of: .tierBump) ?? 0
            let mult = multiplier(forLineIndex: idx)
            let v = useCounters ? Int(round(Double(earned) * Double(mult))) : Int(round(CGFloat(earned) * mult))
            paintMetricLine(title: "Tier bump", value: "\(v >= 0 ? "+" : "")\(v) pts", key: .tierBump)
        }

        if params.publishBuyInCashOut, !session.buyInEvents.isEmpty, keys.contains(.buyIn) {
            let idx = keys.firstIndex(of: .buyIn) ?? 0
            let mult = multiplier(forLineIndex: idx)
            let total = session.totalBuyIn
            let v = useCounters ? Int(round(Double(total) * Double(mult))) : Int(round(CGFloat(total) * mult))
            paintMetricLine(
                title: "Buy-in",
                value: "\(params.currencySymbol)\(max(0, v))",
                key: .buyIn
            )
        }

        if params.publishBuyInCashOut, let co = session.cashOut, keys.contains(.cashOut) {
            let idx = keys.firstIndex(of: .cashOut) ?? 0
            let mult = multiplier(forLineIndex: idx)
            let v = useCounters ? Int(round(Double(co) * Double(mult))) : Int(round(CGFloat(co) * mult))
            paintMetricLine(
                title: "Cash out",
                value: "\(params.currencySymbol)\(max(0, v))",
                key: .cashOut
            )
        }

        if params.publishWinLoss, let wl = session.winLoss, keys.contains(.winLoss) {
            let idx = keys.firstIndex(of: .winLoss) ?? 0
            let mult = multiplier(forLineIndex: idx)
            let v = useCounters ? Int(round(Double(wl) * Double(mult))) : Int(round(CGFloat(wl) * mult))
            let sign = v >= 0 ? "+" : "-"
            let absv = abs(v)
            paintMetricLine(title: "Win / Loss", value: "\(sign)\(params.currencySymbol)\(absv)", key: .winLoss)
        }

        if params.publishWinLoss, let wr = session.winRatePerHour, keys.contains(.winRate) {
            let idx = keys.firstIndex(of: .winRate) ?? 0
            let mult = multiplier(forLineIndex: idx)
            let wv = wr * Double(useCounters ? Double(mult) : Double(mReach))
            paintMetricLine(title: "Win rate", value: String(format: "%@%.0f / hr", wv >= 0 ? "+" : "", wv), key: .winRate)
        }

        if params.publishTierPerHour, let tph = session.tiersPerHour, keys.contains(.tiersPerHour) {
            let idx = keys.firstIndex(of: .tiersPerHour) ?? 0
            let mult = multiplier(forLineIndex: idx)
            let tv = tph * (useCounters ? Double(mult) : Double(mReach))
            paintMetricLine(title: "Tiers / hour", value: String(format: "%.1f", tv), key: .tiersPerHour)
        }

        if params.publishCompDetails, !session.compEvents.isEmpty, keys.contains(.comps) {
            let idx = keys.firstIndex(of: .comps) ?? 0
            let mult = multiplier(forLineIndex: idx)
            let count = useCounters ? max(0, Int(round(Double(session.compEvents.count) * Double(mult)))) : max(0, Int(round(CGFloat(session.compEvents.count) * mult)))
            let total = useCounters ? Int(round(Double(session.totalComp) * Double(mult))) : Int(round(CGFloat(session.totalComp) * mult))
            paintMetricLine(title: "Comps", value: "\(count) · est. \(params.currencySymbol)\(total)", key: .comps)
        }
    }
}

// MARK: - Preview sheet

private enum SessionArtPreviewOutputKind: Equatable {
    case image
    case text
}

private struct SessionArtPreviewSheet: View {
    let session: Session
    /// Read on each render so the preview matches the underlay selected on the parent screen (upload / chip / comp).
    let resolveUnderlay: () -> UIImage?
    let includeMetrics: Bool
    let publishTierPerHour: Bool
    let publishWinLoss: Bool
    let publishBuyInCashOut: Bool
    let publishCompDetails: Bool
    let currencySymbol: String
    let designSize: CGSize
    let videoUnderlayURL: URL?

    @Binding var layout: SessionArtLayout
    @Binding var selectedTemplate: SessionArtTemplate
    @Binding var selectedTextFont: SessionArtTextFont
    @Binding var globalTextScale: CGFloat
    @Binding var selectedTextColor: SessionArtColorToken
    @Binding var selectedTextBackgroundColor: SessionArtColorToken
    @Binding var textBackgroundOpacity: CGFloat
    /// Footnote text baked into the image (edited on the main Session Art screen).
    let footerCaption: String
    @Binding var shareBodyText: String
    let outputKind: SessionArtPreviewOutputKind
    let onShareImage: () -> Void
    let onShareText: () -> Void
    let onCancel: () -> Void

    @State private var renderedPreviewImage: UIImage?
    @State private var isGeneratingPreview = false
    @State private var previewProgress: Double = 0
    @State private var previewProgressTask: Task<Void, Never>?
    @State private var previewVideoPlayer: AVPlayer?
    @State private var previewVideoLoopObserver: NSObjectProtocol?
    @State private var templatesControlsExpanded = true
    @State private var fontsControlsExpanded = true
    @State private var colorsControlsExpanded = true

    var body: some View {
        NavigationStack {
            Group {
                if outputKind == .text {
                    textPreviewContent
                } else {
                    ZStack {
                        Color.black.ignoresSafeArea()
                        VStack(spacing: 0) {
                            previewCanvas
                                .frame(maxHeight: .infinity)
                        }
                    }
                }
            }
            .navigationTitle(outputKind == .text ? "Preview text" : "Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .foregroundColor(.green)
                }
            }
            .safeAreaInset(edge: .bottom) {
                imagePreviewChrome
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
            }
            .onAppear {
                configurePreviewVideoPlayerIfNeeded()
                refreshPreviewImage()
            }
            .onDisappear {
                previewProgressTask?.cancel()
                previewProgressTask = nil
                tearDownPreviewVideoPlayer()
            }
            .onChange(of: videoUnderlayURL) { _ in
                configurePreviewVideoPlayerIfNeeded()
                refreshPreviewImage()
            }
            .onChange(of: selectedTemplate) { _ in refreshPreviewImage() }
            .onChange(of: layout) { _ in refreshPreviewImage() }
            .onChange(of: includeMetrics) { _ in refreshPreviewImage() }
            .onChange(of: publishTierPerHour) { _ in refreshPreviewImage() }
            .onChange(of: publishWinLoss) { _ in refreshPreviewImage() }
            .onChange(of: publishBuyInCashOut) { _ in refreshPreviewImage() }
            .onChange(of: publishCompDetails) { _ in refreshPreviewImage() }
            .onChange(of: currencySymbol) { _ in refreshPreviewImage() }
            .onChange(of: footerCaption) { _ in refreshPreviewImage() }
            .onChange(of: selectedTextFont) { _ in refreshPreviewImage() }
            .onChange(of: globalTextScale) { _ in refreshPreviewImage() }
            .onChange(of: selectedTextColor) { _ in refreshPreviewImage() }
            .onChange(of: selectedTextBackgroundColor) { _ in refreshPreviewImage() }
            .onChange(of: textBackgroundOpacity) { _ in refreshPreviewImage() }
        }
    }

    @ViewBuilder
    private var imagePreviewChrome: some View {
        switch outputKind {
        case .text:
            bottomActionBar
        case .image:
            VStack(alignment: .leading, spacing: 10) {
                collapsibleControlsBubble(
                    title: "Templates",
                    subtitle: "\(selectedTemplate.shortTitle) selected",
                    icon: "photo.on.rectangle",
                    isExpanded: $templatesControlsExpanded
                ) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(SessionArtTemplate.allCases) { template in
                                templateThumbnailButton(template)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                collapsibleControlsBubble(
                    title: "Fonts + size",
                    subtitle: "\(selectedTextFont.label) · \(String(format: "%.2fx", globalTextScale))",
                    icon: "textformat.size",
                    isExpanded: $fontsControlsExpanded
                ) {
                    fontControlsRow
                }
                collapsibleControlsBubble(
                    title: "Colors",
                    subtitle: "Font + background styling",
                    icon: "paintpalette.fill",
                    isExpanded: $colorsControlsExpanded
                ) {
                    colorControlsRow
                }
                bottomActionBar
            }
        }
    }

    private func collapsibleControlsBubble<Content: View>(
        title: String,
        subtitle: String,
        icon: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .foregroundColor(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isExpanded.wrappedValue ? 180 : 0))
                }
                .padding(12)
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                VStack(alignment: .leading, spacing: 10) {
                    content()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .background(Color(.systemGray6).opacity(0.18))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .cornerRadius(14)
    }

    private var fontControlsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Font", selection: $selectedTextFont) {
                ForEach(SessionArtTextFont.allCases) { font in
                    Text(font.label).tag(font)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 10) {
                Text("Scale")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Slider(value: $globalTextScale, in: 0.8...1.8, step: 0.05)
                    .tint(.green)
                Text(String(format: "%.2fx", globalTextScale))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.primary)
                    .frame(minWidth: 46, alignment: .trailing)
            }
        }
    }

    private var colorControlsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            colorTokenRow(
                title: "Font color",
                selection: $selectedTextColor
            )
            colorTokenRow(
                title: "Font background",
                selection: $selectedTextBackgroundColor
            )
            HStack(spacing: 10) {
                Text("Font background opacity")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Slider(value: $textBackgroundOpacity, in: 0...0.9, step: 0.05)
                    .tint(.green)
                Text(String(format: "%.0f%%", textBackgroundOpacity * 100))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.primary)
                    .frame(minWidth: 42, alignment: .trailing)
            }
            Text("Applies to text background only")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func colorTokenRow(
        title: String,
        selection: Binding<SessionArtColorToken>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SessionArtColorToken.allCases) { token in
                        Button {
                            selection.wrappedValue = token
                        } label: {
                            VStack(spacing: 4) {
                                Circle()
                                    .fill(token.color)
                                    .frame(width: 24, height: 24)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.7), lineWidth: 0.7)
                                    )
                                Text(token.label)
                                    .font(.caption2)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 9)
                                    .fill(selection.wrappedValue == token ? Color.green.opacity(0.22) : Color.secondary.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 9)
                                    .stroke(selection.wrappedValue == token ? Color.green : Color.clear, lineWidth: 1.4)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var textPreviewContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Same story as Share in History (Tools): edit before sending.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextEditor(text: $shareBodyText)
                    .font(.body)
                    .foregroundColor(.primary)
                    .frame(minHeight: 320)
                    .padding(10)
                    .scrollContentBackground(.hidden)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemGray6))
                    )
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private var bottomActionBar: some View {
        switch outputKind {
        case .text:
            Button(action: onShareText) {
                Label("Share text", systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.green.opacity(0.9))
                    .foregroundColor(.black)
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .disabled(shareBodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        case .image:
            Button(action: onShareImage) {
                Label("Share media", systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.green.opacity(0.9))
                    .foregroundColor(.black)
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)
        }
    }

    private var previewCanvas: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / designSize.width, geo.size.height / designSize.height)
            let w = designSize.width * scale
            let h = designSize.height * scale
            let isVideoPreview = outputKind == .image && videoUnderlayURL != nil
            ZStack {
                if isVideoPreview, let player = previewVideoPlayer {
                    VideoPlayer(player: player)
                        .frame(width: w, height: h)
                        .clipped()
                        .allowsHitTesting(false)
                } else if let image = renderedPreviewImage {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: w, height: h)
                        .clipped()
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.06))
                        .frame(width: w, height: h)
                }

                if isVideoPreview, let image = renderedPreviewImage {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: w, height: h)
                        .clipped()
                }

                if isGeneratingPreview {
                    VStack(spacing: 10) {
                        Text(isVideoPreview ? "Generating overlay..." : "Generating image...")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white)
                        ProgressView(value: previewProgress, total: 1)
                            .progressViewStyle(.linear)
                            .tint(.green)
                            .frame(width: min(w * 0.68, 300))
                        Text("\(Int(previewProgress * 100))%")
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.white.opacity(0.85))
                    }
                    .padding(14)
                    .background(Color.black.opacity(0.62))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .frame(width: w, height: h, alignment: .center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
    }

    private func templateThumbnailButton(_ template: SessionArtTemplate) -> some View {
        let selected = template == selectedTemplate
        return Button {
            selectedTemplate = template
            layout = template.makeLayout(
                session: session,
                publishTierPerHour: publishTierPerHour,
                publishWinLoss: publishWinLoss,
                publishBuyInCashOut: publishBuyInCashOut,
                publishCompDetails: publishCompDetails,
                canvasSize: designSize
            )
        } label: {
            VStack(spacing: 0) {
                Image(
                    uiImage: template.renderThumbnail(
                        session: session,
                        base: resolveUnderlay(),
                        includeMetrics: includeMetrics,
                        publishTierPerHour: publishTierPerHour,
                        publishWinLoss: publishWinLoss,
                        publishBuyInCashOut: publishBuyInCashOut,
                        publishCompDetails: publishCompDetails,
                        currencySymbol: currencySymbol,
                        footerCaption: footerCaption,
                        fontStyle: selectedTextFont,
                        textScale: globalTextScale,
                        textColorToken: selectedTextColor,
                        textBackgroundColorToken: selectedTextBackgroundColor,
                        textBackgroundOpacity: textBackgroundOpacity
                    )
                )
                .resizable()
                .interpolation(.high)
                .aspectRatio(designSize.width / designSize.height, contentMode: .fit)
                .frame(width: 88, height: 156)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    VStack {
                        HStack(spacing: 6) {
                            Text(template.shortTitle)
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            if selected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.7))
                        .clipShape(Capsule())
                        .padding(.top, 6)
                        Spacer()
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(selected ? Color.green : Color.secondary.opacity(0.35), lineWidth: selected ? 3 : 1)
                )
            }
            .frame(width: 100)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(template.shortTitle) layout\(selected ? ", selected" : "")")
    }

    private func refreshPreviewImage() {
        guard outputKind == .image else { return }
        let isVideoPreview = videoUnderlayURL != nil
        let params = SessionArtRenderer.RenderParams(
            base: isVideoPreview ? nil : resolveUnderlay(),
            session: session,
            currencySymbol: currencySymbol,
            includeMetrics: includeMetrics,
            publishTierPerHour: publishTierPerHour,
            publishWinLoss: publishWinLoss,
            publishBuyInCashOut: publishBuyInCashOut,
            publishCompDetails: publishCompDetails,
            metricsReach: 1,
            counterGlobalT: nil,
            fontStyle: selectedTextFont,
            textScale: globalTextScale,
            textColorToken: selectedTextColor,
            textBackgroundColorToken: selectedTextBackgroundColor,
            textBackgroundOpacity: textBackgroundOpacity,
            canvasSize: designSize,
            layout: layout,
            footerCaption: footerCaption
        )
        previewProgressTask?.cancel()
        previewProgress = 0.04
        isGeneratingPreview = true
        previewProgressTask = Task { @MainActor in
            while !Task.isCancelled && previewProgress < 0.9 {
                try? await Task.sleep(nanoseconds: 55_000_000)
                previewProgress = min(0.9, previewProgress + 0.03)
            }
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let img = isVideoPreview
                ? SessionArtRenderer.renderOverlayImage(params: params)
                : SessionArtRenderer.renderImage(params: params)
            DispatchQueue.main.async {
                previewProgressTask?.cancel()
                previewProgressTask = nil
                renderedPreviewImage = img
                previewProgress = 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    isGeneratingPreview = false
                }
            }
        }
    }

    private func configurePreviewVideoPlayerIfNeeded() {
        guard outputKind == .image, let videoUnderlayURL else {
            tearDownPreviewVideoPlayer()
            return
        }
        if let existingURL = (previewVideoPlayer?.currentItem?.asset as? AVURLAsset)?.url,
           existingURL == videoUnderlayURL {
            previewVideoPlayer?.play()
            return
        }
        tearDownPreviewVideoPlayer()

        let item = AVPlayerItem(url: videoUnderlayURL)
        let player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .none
        previewVideoLoopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            player.seek(to: .zero)
            player.play()
        }
        previewVideoPlayer = player
        player.play()
    }

    private func tearDownPreviewVideoPlayer() {
        previewVideoPlayer?.pause()
        previewVideoPlayer = nil
        if let previewVideoLoopObserver {
            NotificationCenter.default.removeObserver(previewVideoLoopObserver)
            self.previewVideoLoopObserver = nil
        }
    }
}

// MARK: - Main view

struct SessionArtGeneratorView: View {
    let sessionId: UUID
    let onBack: () -> Void

    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var outputKind: OutputKind = .image
    @State private var artStyle: ArtStyle = .photoWithMetrics
    @State private var publishTierPerHour = true
    @State private var publishWinLoss = false
    @State private var publishBuyInCashOut = true
    @State private var publishCompDetails = false
    @State private var metricsBubbleExpanded = false
    @State private var selectedArtTemplate: SessionArtTemplate = .balanced
    @State private var selectedTextFont: SessionArtTextFont = .system
    @State private var globalTextScale: CGFloat = 1.0
    @State private var selectedTextColor: SessionArtColorToken = .white
    @State private var selectedTextBackgroundColor: SessionArtColorToken = .black
    @State private var textBackgroundOpacity: CGFloat = 0.45
    @State private var hasAppliedSavedSharePreset = false

    @State private var selectedUnderlay: SessionUnderlaySource?
    @State private var customUnderlay: UIImage?
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var videoPickerItem: PhotosPickerItem?
    @State private var selectedShareVideoURL: URL?

    @State private var shareMediaItem: SessionArtShareMediaItem?
    @State private var shareTextItem: SessionArtShareTextItem?

    @State private var exportError: String?

    @State private var showPreviewSheet = false
    @State private var previewLayout = SessionArtLayout(
        headerOrigin: .zero,
        lineOrigins: [:],
        footerCenter: .zero
    )
    @State private var previewFooterCaption = ""
    @State private var previewShareText = ""
    @State private var isExportingImage = false
    @State private var exportProgress: Double = 0
    @State private var exportProgressTask: Task<Void, Never>?
    @State private var exportRenderWorkItem: DispatchWorkItem?
    @State private var exportRenderToken = UUID()
    @State private var exportSession: AVAssetExportSession?
    @State private var exportStatusTitle = "Generating image..."

    private let designCanvas = sessionArtExportCanvas

    private enum OutputKind: String, CaseIterable {
        case image = "Image"
        case text = "Text"
    }

    private enum ArtStyle: String, CaseIterable {
        case photoOnly = "Photo only"
        case photoWithMetrics = "Photo + metrics"
    }

    var body: some View {
        ZStack {
            settingsStore.primaryGradient.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if resolvedSession == nil {
                        Text("Session not found.")
                            .foregroundColor(.orange)
                    } else {
                        outputKindPicker
                        if outputKind == .text {
                            textShareOptionsSection
                        } else {
                            artStylePicker
                            if artStyle == .photoWithMetrics {
                                metricsOptionsBubble
                            }
                            underlaySection
                            currentUnderlayPreview
                            shareVideoSection
                        }
                        previewButton
                    }
                }
                .padding()
            }

            if isExportingImage {
                Color.black.opacity(0.42)
                    .ignoresSafeArea()
                VStack(spacing: 10) {
                    Text(exportStatusTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                    ProgressView(value: exportProgress, total: 1)
                        .progressViewStyle(.linear)
                        .tint(.green)
                        .frame(width: 250)
                    Text("\(Int(exportProgress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.white.opacity(0.85))
                    Button("Cancel render") {
                        cancelMediaExport()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.18))
                    .clipShape(Capsule())
                }
                .padding(18)
                .background(Color.black.opacity(0.75))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

        }
        .navigationTitle("Session Art")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back", action: onBack)
                    .foregroundColor(.green)
            }
        }
        .alert("Export", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
        .sheet(item: $shareMediaItem, onDismiss: { dismiss() }) { item in
            ShareSheet(items: item.activityItems)
        }
        .sheet(item: $shareTextItem, onDismiss: { dismiss() }) { item in
            ShareSheet(items: [item.text])
        }
        .sheet(isPresented: $showPreviewSheet) {
            if let session = resolvedSession {
                SessionArtPreviewSheet(
                    session: session,
                    resolveUnderlay: { loadUnderlayImage() },
                    includeMetrics: artStyle == .photoWithMetrics,
                    publishTierPerHour: publishTierPerHour,
                    publishWinLoss: publishWinLoss,
                    publishBuyInCashOut: publishBuyInCashOut,
                    publishCompDetails: publishCompDetails,
                    currencySymbol: settingsStore.currencySymbol,
                    designSize: designCanvas,
                    videoUnderlayURL: selectedShareVideoURL,
                    layout: $previewLayout,
                    selectedTemplate: $selectedArtTemplate,
                    selectedTextFont: $selectedTextFont,
                    globalTextScale: $globalTextScale,
                    selectedTextColor: $selectedTextColor,
                    selectedTextBackgroundColor: $selectedTextBackgroundColor,
                    textBackgroundOpacity: $textBackgroundOpacity,
                    footerCaption: previewFooterCaption,
                    shareBodyText: $previewShareText,
                    outputKind: sessionArtPreviewOutputKind,
                    onShareImage: {
                        saveSharePreset()
                        showPreviewSheet = false
                        exportMediaAfterPreview(session: session)
                    },
                    onShareText: {
                        saveSharePreset()
                        showPreviewSheet = false
                        let trimmed = previewShareText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        shareTextItem = SessionArtShareTextItem(text: trimmed)
                    },
                    onCancel: { showPreviewSheet = false }
                )
                .id(underlayPreviewIdentity)
            }
        }
        .onAppear {
            applySavedSharePresetIfNeeded()
            pickDefaultUnderlayIfNeeded()
        }
        .onDisappear {
            cancelMediaExport()
            exportProgressTask?.cancel()
            exportProgressTask = nil
        }
    }

    private var resolvedSession: Session? {
        if let saved = store.sessions.first(where: { $0.id == sessionId }) { return saved }
        if store.liveSession?.id == sessionId { return store.liveSession }
        return nil
    }

    /// Busts sheet / preview caching when the chosen background image changes.
    private var underlayPreviewIdentity: String {
        if let videoURL = selectedShareVideoURL {
            return "video-\(videoURL.absoluteString)"
        }
        if let c = customUnderlay {
            return "custom-\(ObjectIdentifier(c))"
        }
        if let sel = selectedUnderlay {
            return sel.id
        }
        return "none"
    }

    private var sessionArtPreviewOutputKind: SessionArtPreviewOutputKind {
        outputKind == .text ? .text : .image
    }

    private var textShareOptionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Story text matches History → Tools → Share sessions (plain text).")
                .font(.caption)
                .foregroundColor(.white.opacity(0.85))
            Toggle("Include buy-in, cash-out, and result lines", isOn: $publishWinLoss)
                .tint(.green)
                .foregroundColor(.white)
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.15))
        .cornerRadius(12)
    }

    private var outputKindPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Output")
                .font(.caption.bold())
                .foregroundColor(.gray)
            Picker("", selection: $outputKind) {
                ForEach(OutputKind.allCases, id: \.self) { k in
                    Text(k.rawValue).tag(k)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var artStylePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Style")
                .font(.caption.bold())
                .foregroundColor(.gray)
            Picker("", selection: $artStyle) {
                ForEach(ArtStyle.allCases, id: \.self) { k in
                    Text(k.rawValue).tag(k)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var metricsOptionsBubble: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    metricsBubbleExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "rectangle.stack.fill")
                        .foregroundColor(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Metrics & optional footnote")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                        Text("Choose what appears on session art (tap to expand)")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.65))
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white.opacity(0.85))
                        .rotationEffect(.degrees(metricsBubbleExpanded ? 180 : 0))
                }
                .padding(14)
            }
            .buttonStyle(.plain)
            if metricsBubbleExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    metricsTogglesInner
                    footnoteEditorField
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
        .background(Color(.systemGray6).opacity(0.18))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .cornerRadius(14)
    }

    private var metricsTogglesInner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Include on the image")
                .font(.caption.bold())
                .foregroundColor(.gray)
            Toggle("Tier / hour", isOn: $publishTierPerHour)
                .tint(.green)
                .foregroundColor(.white)
            Toggle("Buy-in & cash-out", isOn: $publishBuyInCashOut)
                .tint(.green)
                .foregroundColor(.white)
            Toggle("Publish wins / losses", isOn: $publishWinLoss)
                .tint(.green)
                .foregroundColor(.white)
            Toggle("Comp details", isOn: $publishCompDetails)
                .tint(.green)
                .foregroundColor(.white)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6).opacity(0.12))
        .cornerRadius(12)
    }

    private var footnoteEditorField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Extra footnote on the image")
                .font(.caption.bold())
                .foregroundColor(.gray)
            TextField("e.g. 🔥 heater · booked win", text: $previewFooterCaption)
                .textFieldStyle(.roundedBorder)
                .foregroundColor(.primary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6).opacity(0.12))
        .cornerRadius(12)
    }

    private var underlaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Underlay photo")
                .font(.caption.bold())
                .foregroundColor(.gray)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    if let custom = customUnderlay {
                        underlayThumb(
                            title: "Uploaded",
                            image: custom,
                            selected: customUnderlay != nil && selectedShareVideoURL == nil
                        ) {
                            selectedUnderlay = nil
                            selectedShareVideoURL = nil
                        }
                    }
                    if let s = resolvedSession,
                       let fn = s.chipEstimatorImageFilename,
                       let url = ChipEstimatorPhotoStorage.url(for: fn),
                       let chipImage = UIImage(contentsOfFile: url.path) {
                        underlayThumb(
                            title: "Chip / table",
                            image: chipImage,
                            selected: selectedUnderlay == .chipEstimator && customUnderlay == nil
                        ) {
                            customUnderlay = nil
                            selectedUnderlay = .chipEstimator
                            selectedShareVideoURL = nil
                        }
                    }
                    if let s = resolvedSession {
                        ForEach(Array(s.compEvents.filter { CompPhotoStorage.url(for: $0.id) != nil }), id: \.id) { ev in
                            let compURL = CompPhotoStorage.url(for: ev.id)
                            let compImage = compURL.flatMap { UIImage(contentsOfFile: $0.path) }
                            underlayThumb(
                                title: "Comp",
                                image: compImage,
                                selected: selectedUnderlay == .compPhoto(ev.id) && customUnderlay == nil
                            ) {
                                customUnderlay = nil
                                selectedUnderlay = .compPhoto(ev.id)
                                selectedShareVideoURL = nil
                            }
                        }
                    }
                }
            }
            PhotosPicker(selection: $photoPickerItem, matching: .images, photoLibrary: .shared()) {
                Label("Upload a picture", systemImage: "photo.badge.plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue.opacity(0.75))
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .onChange(of: photoPickerItem) { newItem in
                guard let newItem else { return }
                photoPickerItem = nil
                Task {
                    let img = await loadUIImageFromPickerItem(newItem)
                    await MainActor.run {
                        if let img {
                            customUnderlay = img
                            selectedUnderlay = nil
                            selectedShareVideoURL = nil
                        } else {
                            exportError = "Couldn't load the selected picture."
                        }
                    }
                }
            }
            if customUnderlay != nil {
                Button(role: .destructive) {
                    customUnderlay = nil
                    pickDefaultUnderlayIfNeeded()
                } label: {
                    Label("Remove uploaded picture", systemImage: "trash")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
            }
        }
        .onChange(of: store.sessions) { _ in pickDefaultUnderlayIfNeeded() }
    }

    private var currentUnderlayPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Photo used for image export")
                .font(.caption.bold())
                .foregroundColor(.gray)
            Group {
                if let img = loadUnderlayImage() {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "photo")
                            .foregroundColor(.white.opacity(0.6))
                        Text("No underlay selected yet.")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.75))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private var shareVideoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Share media (image or video)")
                .font(.caption.bold())
                .foregroundColor(.gray)
            PhotosPicker(selection: $videoPickerItem, matching: .videos, photoLibrary: .shared()) {
                Label(selectedShareVideoURL == nil ? "Use a video instead of image" : "Replace selected video", systemImage: "video.badge.plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.purple.opacity(0.75))
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .onChange(of: videoPickerItem) { newItem in
                guard let newItem else { return }
                videoPickerItem = nil
                Task {
                    let url = await loadShareVideoURLFromPickerItem(newItem)
                    await MainActor.run {
                        if let url {
                            selectedShareVideoURL = url
                        } else {
                            exportError = "Couldn't load the selected video."
                        }
                    }
                }
            }
            if let shareVideoURL = selectedShareVideoURL {
                HStack(spacing: 8) {
                    Image(systemName: "video.fill")
                        .foregroundColor(.green)
                    Text(shareVideoURL.lastPathComponent)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                    Spacer()
                    Button("Remove") {
                        selectedShareVideoURL = nil
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.green)
                }
                .padding(10)
                .background(Color(.systemGray6).opacity(0.15))
                .cornerRadius(10)
                Text("Video mode is active. Share will export a new video with your selected template, fonts, and metrics overlaid.")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.75))
            } else {
                Text("No video selected. Share will export a single image.")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.75))
            }
        }
    }

    private func underlayThumb(title: String, image: UIImage?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 88, height: 88)
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 88, height: 88)
                            .clipped()
                    } else {
                        Image(systemName: "photo")
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(selected ? Color.green : Color.clear, lineWidth: 3)
                }
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.85))
            }
        }
        .buttonStyle(.plain)
    }

    private var previewButton: some View {
        Button {
            openPreview()
        } label: {
            Text(outputKind == .text ? "Preview & edit text" : "Preview & adjust")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.green.opacity(0.9))
                .foregroundColor(.black)
                .cornerRadius(14)
        }
        .buttonStyle(.plain)
        .disabled(resolvedSession == nil)
        .opacity(resolvedSession == nil ? 0.5 : 1)
    }

    private func applySavedSharePresetIfNeeded() {
        guard !hasAppliedSavedSharePreset else { return }
        hasAppliedSavedSharePreset = true
        guard let data = UserDefaults.standard.data(forKey: keySessionArtSharePreset),
              let preset = try? JSONDecoder().decode(SessionArtSharePreset.self, from: data) else {
            return
        }
        if let output = OutputKind(rawValue: preset.outputKindRaw) {
            outputKind = output
        }
        if let style = ArtStyle(rawValue: preset.artStyleRaw) {
            artStyle = style
        }
        publishTierPerHour = preset.publishTierPerHour
        publishWinLoss = preset.publishWinLoss
        publishBuyInCashOut = preset.publishBuyInCashOut
        publishCompDetails = preset.publishCompDetails
        if let template = SessionArtTemplate(rawValue: preset.selectedTemplateRaw) {
            selectedArtTemplate = template
        }
        if let textFont = SessionArtTextFont(rawValue: preset.selectedTextFontRaw) {
            selectedTextFont = textFont
        }
        globalTextScale = min(1.8, max(0.8, CGFloat(preset.globalTextScale)))
        if let textColor = SessionArtColorToken(rawValue: preset.selectedTextColorRaw) {
            selectedTextColor = textColor
        }
        if let bgColor = SessionArtColorToken(rawValue: preset.selectedTextBackgroundColorRaw) {
            selectedTextBackgroundColor = bgColor
        }
        textBackgroundOpacity = min(0.9, max(0, CGFloat(preset.textBackgroundOpacity)))
    }

    private func saveSharePreset() {
        let preset = SessionArtSharePreset(
            outputKindRaw: outputKind.rawValue,
            artStyleRaw: artStyle.rawValue,
            publishTierPerHour: publishTierPerHour,
            publishWinLoss: publishWinLoss,
            publishBuyInCashOut: publishBuyInCashOut,
            publishCompDetails: publishCompDetails,
            selectedTemplateRaw: selectedArtTemplate.rawValue,
            selectedTextFontRaw: selectedTextFont.rawValue,
            globalTextScale: Double(globalTextScale),
            selectedTextColorRaw: selectedTextColor.rawValue,
            selectedTextBackgroundColorRaw: selectedTextBackgroundColor.rawValue,
            textBackgroundOpacity: Double(textBackgroundOpacity)
        )
        guard let data = try? JSONEncoder().encode(preset) else { return }
        UserDefaults.standard.set(data, forKey: keySessionArtSharePreset)
    }

    private func openPreview() {
        guard let s = resolvedSession else { return }
        if outputKind == .text {
            previewShareText = SessionShareFormatter.combinedMessage(
                for: [s],
                currencySymbol: settingsStore.currencySymbol,
                includeWinLoss: publishWinLoss
            )
        } else {
            previewLayout = selectedArtTemplate.makeLayout(
                session: s,
                publishTierPerHour: publishTierPerHour,
                publishWinLoss: publishWinLoss,
                publishBuyInCashOut: publishBuyInCashOut,
                publishCompDetails: publishCompDetails,
                canvasSize: designCanvas
            )
        }
        showPreviewSheet = true
    }

    private func pickDefaultUnderlayIfNeeded() {
        guard selectedUnderlay == nil, customUnderlay == nil, let s = resolvedSession else { return }
        if s.chipEstimatorImageFilename != nil,
           let fn = s.chipEstimatorImageFilename,
           ChipEstimatorPhotoStorage.url(for: fn) != nil {
            selectedUnderlay = .chipEstimator
            return
        }
        if let ev = s.compEvents.first(where: { CompPhotoStorage.url(for: $0.id) != nil }) {
            selectedUnderlay = .compPhoto(ev.id)
        }
    }

    /// `Data` import works for many assets; `URL` covers some Photos / iCloud exports where `Data` is unavailable.
    private func loadUIImageFromPickerItem(_ item: PhotosPickerItem) async -> UIImage? {
        if let data = try? await item.loadTransferable(type: Data.self),
           let img = UIImage(data: data) {
            return img
        }
        if let url = try? await item.loadTransferable(type: URL.self) {
            if let fileImg = UIImage(contentsOfFile: url.path) { return fileImg }
            if let data = try? Data(contentsOf: url), let img = UIImage(data: data) { return img }
        }
        return nil
    }

    private func loadShareVideoURLFromPickerItem(_ item: PhotosPickerItem) async -> URL? {
        if let sourceURL = try? await item.loadTransferable(type: URL.self) {
            return copyVideoForShare(from: sourceURL)
        }
        if let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty {
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("session-share-\(UUID().uuidString).mov")
            do {
                try data.write(to: dest, options: .atomic)
                return dest
            } catch {
                return nil
            }
        }
        return nil
    }

    private func copyVideoForShare(from sourceURL: URL) -> URL? {
        let fileExtension = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("session-share-\(UUID().uuidString).\(fileExtension)")

        let granted = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if granted {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    private func loadUnderlayImage() -> UIImage? {
        if let customUnderlay { return customUnderlay }
        guard let s = resolvedSession, let sel = selectedUnderlay else { return nil }
        switch sel {
        case .chipEstimator:
            guard let fn = s.chipEstimatorImageFilename,
                  let url = ChipEstimatorPhotoStorage.url(for: fn) else { return nil }
            return UIImage(contentsOfFile: url.path)
        case .compPhoto(let id):
            guard let url = CompPhotoStorage.url(for: id) else { return nil }
            return UIImage(contentsOfFile: url.path)
        }
    }

    private func renderParams(
        session: Session,
        base: UIImage?,
        metricsReach: CGFloat,
        counterT: CGFloat?,
        canvas: CGSize
    ) -> SessionArtRenderer.RenderParams {
        SessionArtRenderer.RenderParams(
            base: base,
            session: session,
            currencySymbol: settingsStore.currencySymbol,
            includeMetrics: artStyle == .photoWithMetrics,
            publishTierPerHour: publishTierPerHour,
            publishWinLoss: publishWinLoss,
            publishBuyInCashOut: publishBuyInCashOut,
            publishCompDetails: publishCompDetails,
            metricsReach: metricsReach,
            counterGlobalT: counterT,
            fontStyle: selectedTextFont,
            textScale: globalTextScale,
            textColorToken: selectedTextColor,
            textBackgroundColorToken: selectedTextBackgroundColor,
            textBackgroundOpacity: textBackgroundOpacity,
            canvasSize: canvas,
            layout: previewLayout,
            footerCaption: previewFooterCaption
        )
    }

    private func exportMediaAfterPreview(session: Session) {
        if let sourceVideoURL = selectedShareVideoURL {
            exportVideoAfterPreview(session: session, sourceVideoURL: sourceVideoURL)
        } else {
            exportImageAfterPreview(session: session)
        }
    }

    private func exportImageAfterPreview(session: Session) {
        guard !isExportingImage else { return }
        exportStatusTitle = "Generating image..."
        isExportingImage = true
        exportProgress = 0.03
        exportProgressTask?.cancel()
        exportRenderWorkItem?.cancel()
        exportSession?.cancelExport()
        exportSession = nil
        exportProgressTask = Task { @MainActor in
            while !Task.isCancelled && exportProgress < 0.9 {
                try? await Task.sleep(nanoseconds: 55_000_000)
                exportProgress = min(0.9, exportProgress + 0.025)
            }
        }
        let token = UUID()
        exportRenderToken = token
        let base = loadUnderlayImage()
        let params = renderParams(
            session: session,
            base: base,
            metricsReach: 1,
            counterT: nil,
            canvas: designCanvas
        )
        let workItem = DispatchWorkItem {
            let img = SessionArtRenderer.renderImage(params: params)
            DispatchQueue.main.async {
                guard exportRenderToken == token else { return }
                exportProgressTask?.cancel()
                exportProgressTask = nil
                exportRenderWorkItem = nil
                exportProgress = 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    guard exportRenderToken == token else { return }
                    isExportingImage = false
                    shareMediaItem = SessionArtShareMediaItem(activityItems: [img])
                }
            }
        }
        exportRenderWorkItem = workItem
        DispatchQueue.global(qos: .userInitiated).async(execute: workItem)
    }

    private func exportVideoAfterPreview(session: Session, sourceVideoURL: URL) {
        guard !isExportingImage else { return }
        exportStatusTitle = "Rendering video..."
        isExportingImage = true
        exportProgress = 0.01
        exportProgressTask?.cancel()
        exportRenderWorkItem?.cancel()
        exportSession?.cancelExport()
        exportSession = nil

        let token = UUID()
        exportRenderToken = token

        let sourceAsset = AVURLAsset(url: sourceVideoURL)
        let duration = sourceAsset.duration
        guard duration.seconds > 0 else {
            isExportingImage = false
            exportError = "Selected video appears empty."
            return
        }
        guard let sourceVideoTrack = sourceAsset.tracks(withMediaType: .video).first else {
            isExportingImage = false
            exportError = "Selected file does not contain a video track."
            return
        }

        let preferredTransform = sourceVideoTrack.preferredTransform
        let transformedRect = CGRect(origin: .zero, size: sourceVideoTrack.naturalSize).applying(preferredTransform)
        var orientedSize = CGSize(width: abs(transformedRect.width), height: abs(transformedRect.height))
        if orientedSize.width < 16 || orientedSize.height < 16 {
            orientedSize = CGSize(width: abs(sourceVideoTrack.naturalSize.width), height: abs(sourceVideoTrack.naturalSize.height))
        }
        if orientedSize.width < 16 || orientedSize.height < 16 {
            orientedSize = CGSize(width: 1080, height: 1920)
        }

        // Keep a story-friendly minimum while avoiding extreme export dimensions.
        let minShortSide: CGFloat = 1080
        let minLongSide: CGFloat = 1920
        let maxDimension: CGFloat = 3840
        let shortSide = min(orientedSize.width, orientedSize.height)
        let longSide = max(orientedSize.width, orientedSize.height)
        var upscale = max(minShortSide / max(shortSide, 1), minLongSide / max(longSide, 1), 1)
        if longSide * upscale > maxDimension {
            upscale = maxDimension / max(longSide, 1)
        }
        let renderSize = CGSize(
            width: floor(orientedSize.width * upscale),
            height: floor(orientedSize.height * upscale)
        )

        var overlayParams = renderParams(
            session: session,
            base: nil,
            metricsReach: 1,
            counterT: nil,
            canvas: renderSize
        )
        overlayParams.base = nil
        overlayParams.layout = previewLayout.scaledForCanvas(from: designCanvas, to: renderSize)
        let overlayImage = SessionArtRenderer.renderOverlayImage(params: overlayParams)
        guard let overlayCG = overlayImage.cgImage else {
            isExportingImage = false
            exportError = "Could not build overlay image for video export."
            return
        }
        let overlayCI = CIImage(cgImage: overlayCG)
        let overlayExtent = CGRect(origin: .zero, size: renderSize)
        let orientationTransform = preferredTransform.concatenating(
            CGAffineTransform(translationX: -transformedRect.minX, y: -transformedRect.minY)
        )

        // Use CI-based compositing for stability when exporting user-picked videos.
        let videoComposition = AVMutableVideoComposition(asset: sourceAsset) { request in
            let oriented = request.sourceImage
                .transformed(by: orientationTransform)
                .cropped(to: CGRect(origin: .zero, size: orientedSize))

            let scaledBase = oriented.transformed(by: CGAffineTransform(
                scaleX: renderSize.width / max(orientedSize.width, 1),
                y: renderSize.height / max(orientedSize.height, 1)
            ))
            .cropped(to: overlayExtent)

            let out = overlayCI.composited(over: scaledBase).cropped(to: overlayExtent)
            request.finish(with: out, context: nil)
        }
        let fps = sourceVideoTrack.nominalFrameRate > 0 ? sourceVideoTrack.nominalFrameRate : 30
        let timescale = CMTimeScale(max(24, min(60, Int(fps.rounded()))))
        videoComposition.frameDuration = CMTime(value: 1, timescale: timescale)
        videoComposition.renderSize = renderSize

        guard let exportSession = AVAssetExportSession(asset: sourceAsset, presetName: AVAssetExportPresetHighestQuality) else {
            isExportingImage = false
            exportError = "Could not initialize video export."
            return
        }
        let outputType: AVFileType = exportSession.supportedFileTypes.contains(.mp4) ? .mp4 : .mov
        let outputExt = outputType == .mp4 ? "mp4" : "mov"
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("session-art-video-\(UUID().uuidString).\(outputExt)")
        try? FileManager.default.removeItem(at: outputURL)
        exportSession.outputURL = outputURL
        exportSession.outputFileType = outputType
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.videoComposition = videoComposition
        self.exportSession = exportSession

        exportProgressTask = Task { @MainActor in
            while !Task.isCancelled && exportRenderToken == token {
                let p = Double(exportSession.progress)
                exportProgress = min(0.99, max(0.01, p))
                try? await Task.sleep(nanoseconds: 90_000_000)
            }
        }

        exportSession.exportAsynchronously {
            DispatchQueue.main.async {
                guard exportRenderToken == token else { return }
                exportProgressTask?.cancel()
                exportProgressTask = nil
                self.exportSession = nil

                switch exportSession.status {
                case .completed:
                    exportProgress = 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        guard exportRenderToken == token else { return }
                        isExportingImage = false
                        shareMediaItem = SessionArtShareMediaItem(activityItems: [outputURL])
                    }
                case .cancelled:
                    isExportingImage = false
                    exportProgress = 0
                case .failed:
                    isExportingImage = false
                    exportProgress = 0
                    exportError = exportSession.error?.localizedDescription ?? "Video export failed."
                default:
                    isExportingImage = false
                    exportProgress = 0
                    exportError = "Video export did not complete."
                }
            }
        }
    }

    private func cancelMediaExport() {
        exportRenderToken = UUID()
        exportRenderWorkItem?.cancel()
        exportRenderWorkItem = nil
        exportProgressTask?.cancel()
        exportProgressTask = nil
        exportSession?.cancelExport()
        exportSession = nil
        isExportingImage = false
        exportProgress = 0
    }

}

#endif
