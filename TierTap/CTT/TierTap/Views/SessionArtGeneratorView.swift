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

private enum SessionArtPickerKind: Identifiable {
    case image
    case video

    var id: String {
        switch self {
        case .image: return "image"
        case .video: return "video"
        }
    }
}

private struct SessionArtMediaPickerSheet: UIViewControllerRepresentable {
    let kind: SessionArtPickerKind
    let onPick: (UIImage?, URL?) -> Void

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: SessionArtMediaPickerSheet

        init(parent: SessionArtMediaPickerSheet) {
            self.parent = parent
        }

        /// `loadFileRepresentation` URLs are short-lived, so we copy immediately while still inside the callback.
        private static func persistPickedVideo(_ sourceURL: URL) -> URL? {
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
                guard let data = try? Data(contentsOf: sourceURL), !data.isEmpty else {
                    return nil
                }
                do {
                    try data.write(to: destination, options: .atomic)
                    return destination
                } catch {
                    return nil
                }
            }
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let result = results.first else {
                parent.onPick(nil, nil)
                return
            }
            let provider = result.itemProvider

            switch parent.kind {
            case .image:
                if provider.canLoadObject(ofClass: UIImage.self) {
                    provider.loadObject(ofClass: UIImage.self) { object, _ in
                        DispatchQueue.main.async {
                            self.parent.onPick(object as? UIImage, nil)
                        }
                    }
                    return
                }
                if provider.hasItemConformingToTypeIdentifier("public.image") {
                    provider.loadFileRepresentation(forTypeIdentifier: "public.image") { url, _ in
                        let image = url.flatMap { UIImage(contentsOfFile: $0.path) }
                        DispatchQueue.main.async {
                            self.parent.onPick(image, nil)
                        }
                    }
                    return
                }
                parent.onPick(nil, nil)

            case .video:
                if provider.hasItemConformingToTypeIdentifier("public.movie") {
                    provider.loadFileRepresentation(forTypeIdentifier: "public.movie") { url, _ in
                        let persistedURL = url.flatMap { Self.persistPickedVideo($0) }
                        DispatchQueue.main.async {
                            self.parent.onPick(nil, persistedURL)
                        }
                    }
                    return
                }
                if provider.hasItemConformingToTypeIdentifier("public.video") {
                    provider.loadFileRepresentation(forTypeIdentifier: "public.video") { url, _ in
                        let persistedURL = url.flatMap { Self.persistPickedVideo($0) }
                        DispatchQueue.main.async {
                            self.parent.onPick(nil, persistedURL)
                        }
                    }
                    return
                }
                parent.onPick(nil, nil)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 1
        switch kind {
        case .image:
            config.filter = .images
            config.preferredAssetRepresentationMode = .current
        case .video:
            config.filter = .videos
            // Ask Photos for a broadly compatible export format for downstream AVAsset pipelines.
            config.preferredAssetRepresentationMode = .compatible
        }
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
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
    var selectedBaseTemplateRaw: String?
    var selectedStickerTemplateRaw: String?
    var selectedArtDecoTemplateRaw: String?
    var selectedTextFontRaw: String
    var globalTextScale: Double
    var selectedTextColorRaw: String
    var selectedTextBackgroundColorRaw: String
    var textBackgroundOpacity: Double
}

// MARK: - Underlay source

private enum SessionUnderlaySource: Hashable, Identifiable {
    case uploaded
    case chipEstimator
    case compPhoto(UUID)

    var id: String {
        switch self {
        case .uploaded: return "uploaded"
        case .chipEstimator: return "chip"
        case .compPhoto(let u): return u.uuidString
        }
    }

    var label: String {
        switch self {
        case .uploaded: return "Uploaded photo"
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
    case avenir
    case avenirHeavy
    case helveticaNeue
    case futura
    case georgia
    case gillSans
    case chalkboard
    case noteworthy
    case courierNew
    case optima

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .rounded: return "Rounded"
        case .serif: return "Serif"
        case .mono: return "Mono"
        case .avenir: return "Avenir"
        case .avenirHeavy: return "Avenir Heavy"
        case .helveticaNeue: return "Helvetica Neue"
        case .futura: return "Futura"
        case .georgia: return "Georgia"
        case .gillSans: return "Gill Sans"
        case .chalkboard: return "Chalkboard"
        case .noteworthy: return "Noteworthy"
        case .courierNew: return "Courier New"
        case .optima: return "Optima"
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

private enum SessionArtPickerGroup: String, CaseIterable, Identifiable {
    case templates = "Templates"
    case stickers = "Stickers"
    case artDeco = "Art Deco"

    var id: String { rawValue }
}

private enum SessionArtBorderStyle: Equatable {
    case none
    case vintagePaper
    case matteFrame
    case artDeco
    case woodFrame
}

private enum SessionArtStickerOverlayStyle: Equatable {
    case none
    case circle
    case triangle
    case square
    case suitSpade
    case suitHeart
    case suitDiamond
    case suitClub
    case aceSpades
    case aceDiamonds
    case aceHearts
    case jackCard
    case eightSpades
    case nineSpades
    case artDecoSlotMachine
    case artDecoDice
    case artDecoJoker
    case artDecoMoneyBag
    case artDecoGem
    case artDecoCoin
    case artDecoTicket
    case artDecoCrown
    case artDecoSparkles
    case artDecoSpade
    case artDecoHeart
    case artDecoDiamond

    var usesStickerMetricPlacements: Bool {
        switch self {
        case .none,
             .artDecoSlotMachine, .artDecoDice, .artDecoJoker, .artDecoMoneyBag,
             .artDecoGem, .artDecoCoin, .artDecoTicket, .artDecoCrown,
             .artDecoSparkles, .artDecoSpade, .artDecoHeart, .artDecoDiamond:
            return false
        default:
            return true
        }
    }
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
    /// Decorative border overlaid on top of the rendered media.
    var borderStyle: SessionArtBorderStyle = .none
    /// Decorative sticker geometry for stat-group presets.
    var stickerOverlayStyle: SessionArtStickerOverlayStyle = .none
    /// Optional second decorative pass (used to stack Art Deco with stickers).
    var secondaryOverlayStyle: SessionArtStickerOverlayStyle = .none

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
            emphasisScale: emphasisScale,
            borderStyle: borderStyle,
            stickerOverlayStyle: stickerOverlayStyle,
            secondaryOverlayStyle: secondaryOverlayStyle
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
    case vintageBorder
    case pictureFrame
    case artDecoBorder
    case woodFrame
    case statCircle
    case statTriangle
    case statSquare
    case stickerSpade
    case stickerHeart
    case stickerDiamond
    case stickerClub
    case aceSpadesCard
    case aceDiamondsCard
    case aceHeartsCard
    case jackCard
    case eightSpadesCard
    case nineSpadesCard
    case decoSlotMachine
    case decoDice
    case decoJoker
    case decoMoneyBag
    case decoGem
    case decoCoin
    case decoTicket
    case decoCrown
    case decoSparkles
    case decoSpade
    case decoHeart
    case decoDiamond

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
        case .vintageBorder: return "Vintage"
        case .pictureFrame: return "Picture frame"
        case .artDecoBorder: return "Art deco"
        case .woodFrame: return "Picture frame 2"
        case .statCircle: return "Stat circle"
        case .statTriangle: return "Stat triangle"
        case .statSquare: return "Stat square"
        case .stickerSpade: return "Spade"
        case .stickerHeart: return "Heart"
        case .stickerDiamond: return "Diamond"
        case .stickerClub: return "Club"
        case .aceSpadesCard: return "A♠ card"
        case .aceDiamondsCard: return "A♦ card"
        case .aceHeartsCard: return "A♥ card"
        case .jackCard: return "J card"
        case .eightSpadesCard: return "8♠ card"
        case .nineSpadesCard: return "9♠ card"
        case .decoSlotMachine: return "Slot machine"
        case .decoDice: return "Dice"
        case .decoJoker: return "Joker"
        case .decoMoneyBag: return "Money bag"
        case .decoGem: return "Gem"
        case .decoCoin: return "Coin"
        case .decoTicket: return "Ticket"
        case .decoCrown: return "Crown"
        case .decoSparkles: return "Sparkles"
        case .decoSpade: return "Spade icon"
        case .decoHeart: return "Heart icon"
        case .decoDiamond: return "Diamond icon"
        }
    }

    var pickerGroup: SessionArtPickerGroup {
        switch self {
        case .statCircle, .statTriangle, .statSquare,
             .stickerSpade, .stickerHeart, .stickerDiamond, .stickerClub,
             .aceSpadesCard, .aceDiamondsCard, .aceHeartsCard, .jackCard, .eightSpadesCard, .nineSpadesCard:
            return .stickers
        case .decoSlotMachine, .decoDice, .decoJoker, .decoMoneyBag, .decoGem, .decoCoin,
             .decoTicket, .decoCrown, .decoSparkles, .decoSpade, .decoHeart, .decoDiamond:
            return .artDeco
        default:
            return .templates
        }
    }

    private func ringLineOrigins(keys: [MetricLineKey], center: CGPoint, radius: CGFloat) -> [MetricLineKey: CGPoint] {
        guard !keys.isEmpty else { return [:] }
        let anchors: [CGPoint] = [
            // Top arc
            CGPoint(x: center.x - radius * 0.62, y: center.y - radius * 0.76),
            CGPoint(x: center.x, y: center.y - radius * 0.90),
            CGPoint(x: center.x + radius * 0.62, y: center.y - radius * 0.76),
            // Bottom arc
            CGPoint(x: center.x - radius * 0.58, y: center.y + radius * 0.78),
            CGPoint(x: center.x + radius * 0.58, y: center.y + radius * 0.78),
            // Side fallback
            CGPoint(x: center.x - radius * 0.98, y: center.y),
            CGPoint(x: center.x + radius * 0.98, y: center.y)
        ]
        var origins: [MetricLineKey: CGPoint] = [:]
        for (index, key) in keys.enumerated() {
            origins[key] = anchors[min(index, anchors.count - 1)]
        }
        return origins
    }

    private func triangleLineOrigins(keys: [MetricLineKey], in size: CGSize) -> [MetricLineKey: CGPoint] {
        guard !keys.isEmpty else { return [:] }
        let anchors: [CGPoint] = [
            CGPoint(x: size.width * 0.5, y: size.height * 0.36),  // top compartment
            CGPoint(x: size.width * 0.34, y: size.height * 0.64), // bottom-left
            CGPoint(x: size.width * 0.66, y: size.height * 0.64), // bottom-right
            CGPoint(x: size.width * 0.5, y: size.height * 0.52),  // center strip
            CGPoint(x: size.width * 0.24, y: size.height * 0.56), // left edge
            CGPoint(x: size.width * 0.76, y: size.height * 0.56)  // right edge
        ]
        var origins: [MetricLineKey: CGPoint] = [:]
        for (index, key) in keys.enumerated() {
            let anchor = anchors[min(index, anchors.count - 1)]
            origins[key] = anchor
        }
        return origins
    }

    private func squareLineOrigins(keys: [MetricLineKey], in size: CGSize) -> [MetricLineKey: CGPoint] {
        guard !keys.isEmpty else { return [:] }
        let anchors: [CGPoint] = [
            CGPoint(x: size.width * 0.58, y: size.height * 0.34),
            CGPoint(x: size.width * 0.58, y: size.height * 0.45),
            CGPoint(x: size.width * 0.58, y: size.height * 0.56),
            CGPoint(x: size.width * 0.58, y: size.height * 0.67),
            CGPoint(x: size.width * 0.36, y: size.height * 0.56),
            CGPoint(x: size.width * 0.36, y: size.height * 0.69)
        ]
        var origins: [MetricLineKey: CGPoint] = [:]
        for (index, key) in keys.enumerated() {
            let anchor = anchors[min(index, anchors.count - 1)]
            origins[key] = anchor
        }
        return origins
    }

    private func artDecoLayout(
        overlayStyle: SessionArtStickerOverlayStyle,
        keys: [MetricLineKey],
        in size: CGSize
    ) -> SessionArtLayout {
        let w = size.width
        let h = size.height
        let s = max(1, w / sessionArtReferenceWidth)
        return SessionArtLayout(
            headerOrigin: CGPoint(x: w * 0.16, y: h * 0.09),
            lineOrigins: SessionArtLayout.makeLineOriginsStacked(
                keys: keys,
                startY: h * 0.52,
                rowStride: 122 * s,
                leftPadding: w * 0.13
            ),
            footerCenter: CGPoint(x: w * 0.5, y: h * 0.9),
            headerScale: 0.9,
            metricsScale: 0.88,
            footerScale: 0.95,
            brandingScale: 0.88,
            brandingOffset: .zero,
            underlayZoom: 1.02,
            underlayPan: .zero,
            showBranding: false,
            headerFocus: .casino,
            emphasizedMetric: .winLoss,
            emphasisScale: 1.24,
            borderStyle: .artDeco,
            stickerOverlayStyle: overlayStyle
        )
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
        let stickerFallbackKeys = SessionArtLayout.activeLineKeys(
            session: session,
            publishTierPerHour: true,
            publishWinLoss: true,
            publishBuyInCashOut: true,
            publishCompDetails: true
        )
        let layoutKeys = (pickerGroup == .stickers && keys.isEmpty) ? stickerFallbackKeys : keys

        switch self {
        case .balanced:
            let rowStride = 132 * s
            return SessionArtLayout(
                headerOrigin: CGPoint(x: pad, y: pad),
                lineOrigins: SessionArtLayout.makeLineOriginsStacked(
                    keys: layoutKeys,
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
                    keys: layoutKeys,
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
                    keys: layoutKeys,
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
                    keys: layoutKeys,
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
                    keys: layoutKeys,
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
                    keys: layoutKeys,
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
                    keys: layoutKeys,
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
                    keys: layoutKeys,
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
                    keys: layoutKeys,
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
                    keys: layoutKeys,
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
                    keys: layoutKeys,
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

        case .vintageBorder:
            let rowStride = 122 * s
            return SessionArtLayout(
                headerOrigin: CGPoint(x: w * 0.12, y: h * 0.08),
                lineOrigins: SessionArtLayout.makeLineOriginsStacked(
                    keys: layoutKeys,
                    startY: h * 0.42,
                    rowStride: rowStride,
                    leftPadding: w * 0.14
                ),
                footerCenter: CGPoint(x: w * 0.5, y: h * 0.90),
                headerScale: 0.9,
                metricsScale: 0.92,
                footerScale: 1.0,
                brandingScale: 0.9,
                brandingOffset: .zero,
                underlayZoom: 1.0,
                underlayPan: .zero,
                showBranding: false,
                headerFocus: .casino,
                emphasizedMetric: .winLoss,
                emphasisScale: 1.32,
                borderStyle: .vintagePaper
            )

        case .pictureFrame:
            let rowStride = 128 * s
            return SessionArtLayout(
                headerOrigin: CGPoint(x: w * 0.18, y: h * 0.09),
                lineOrigins: SessionArtLayout.makeLineOriginsStacked(
                    keys: layoutKeys,
                    startY: h * 0.40,
                    rowStride: rowStride,
                    leftPadding: w * 0.19
                ),
                footerCenter: CGPoint(x: w * 0.68, y: h * 0.88),
                headerScale: 0.84,
                metricsScale: 0.92,
                footerScale: 0.95,
                brandingScale: 0.9,
                brandingOffset: CGPoint(x: -w * 0.03, y: 0),
                underlayZoom: 1.0,
                underlayPan: .zero,
                showBranding: false,
                headerFocus: .casino,
                emphasizedMetric: .winRate,
                emphasisScale: 1.25,
                borderStyle: .matteFrame
            )

        case .artDecoBorder:
            let rowStride = 120 * s
            return SessionArtLayout(
                headerOrigin: CGPoint(x: w * 0.16, y: h * 0.10),
                lineOrigins: SessionArtLayout.makeLineOriginsStacked(
                    keys: layoutKeys,
                    startY: h * 0.44,
                    rowStride: rowStride,
                    leftPadding: w * 0.18
                ),
                footerCenter: CGPoint(x: w * 0.5, y: h * 0.9),
                headerScale: 0.86,
                metricsScale: 0.9,
                footerScale: 0.94,
                brandingScale: 0.9,
                brandingOffset: .zero,
                underlayZoom: 1.0,
                underlayPan: .zero,
                showBranding: false,
                headerFocus: .casino,
                emphasizedMetric: .cashOut,
                emphasisScale: 1.3,
                borderStyle: .artDeco
            )

        case .woodFrame:
            let rowStride = 126 * s
            return SessionArtLayout(
                headerOrigin: CGPoint(x: w * 0.18, y: h * 0.09),
                lineOrigins: SessionArtLayout.makeLineOriginsStacked(
                    keys: keys,
                    startY: h * 0.41,
                    rowStride: rowStride,
                    leftPadding: w * 0.19
                ),
                footerCenter: CGPoint(x: w * 0.68, y: h * 0.88),
                headerScale: 0.84,
                metricsScale: 0.9,
                footerScale: 0.95,
                brandingScale: 0.88,
                brandingOffset: CGPoint(x: -w * 0.03, y: 0),
                underlayZoom: 1.0,
                underlayPan: .zero,
                showBranding: false,
                headerFocus: .casino,
                emphasizedMetric: .tiersPerHour,
                emphasisScale: 1.24,
                borderStyle: .woodFrame
            )

        case .decoSlotMachine:
            return artDecoLayout(overlayStyle: .artDecoSlotMachine, keys: keys, in: canvasSize)
        case .decoDice:
            return artDecoLayout(overlayStyle: .artDecoDice, keys: keys, in: canvasSize)
        case .decoJoker:
            return artDecoLayout(overlayStyle: .artDecoJoker, keys: keys, in: canvasSize)
        case .decoMoneyBag:
            return artDecoLayout(overlayStyle: .artDecoMoneyBag, keys: keys, in: canvasSize)
        case .decoGem:
            return artDecoLayout(overlayStyle: .artDecoGem, keys: keys, in: canvasSize)
        case .decoCoin:
            return artDecoLayout(overlayStyle: .artDecoCoin, keys: keys, in: canvasSize)
        case .decoTicket:
            return artDecoLayout(overlayStyle: .artDecoTicket, keys: keys, in: canvasSize)
        case .decoCrown:
            return artDecoLayout(overlayStyle: .artDecoCrown, keys: keys, in: canvasSize)
        case .decoSparkles:
            return artDecoLayout(overlayStyle: .artDecoSparkles, keys: keys, in: canvasSize)
        case .decoSpade:
            return artDecoLayout(overlayStyle: .artDecoSpade, keys: keys, in: canvasSize)
        case .decoHeart:
            return artDecoLayout(overlayStyle: .artDecoHeart, keys: keys, in: canvasSize)
        case .decoDiamond:
            return artDecoLayout(overlayStyle: .artDecoDiamond, keys: keys, in: canvasSize)

        case .statCircle:
            return SessionArtLayout(
                headerOrigin: CGPoint(x: w * 0.2, y: h * 0.08),
                lineOrigins: ringLineOrigins(
                    keys: layoutKeys,
                    center: CGPoint(x: w * 0.5, y: h * 0.56),
                    radius: min(w, h) * 0.24
                ),
                footerCenter: CGPoint(x: w * 0.5, y: h * 0.9),
                headerScale: 0.9,
                metricsScale: 0.82,
                footerScale: 0.9,
                brandingScale: 0.85,
                brandingOffset: .zero,
                underlayZoom: 1.03,
                underlayPan: .zero,
                showBranding: false,
                headerFocus: .game,
                emphasizedMetric: nil,
                emphasisScale: 1,
                stickerOverlayStyle: .circle
            )

        case .statTriangle:
            return SessionArtLayout(
                headerOrigin: CGPoint(x: w * 0.18, y: h * 0.08),
                lineOrigins: triangleLineOrigins(keys: layoutKeys, in: canvasSize),
                footerCenter: CGPoint(x: w * 0.5, y: h * 0.9),
                headerScale: 0.9,
                metricsScale: 0.8,
                footerScale: 0.9,
                brandingScale: 0.82,
                brandingOffset: .zero,
                underlayZoom: 1.03,
                underlayPan: .zero,
                showBranding: false,
                headerFocus: .game,
                emphasizedMetric: nil,
                emphasisScale: 1,
                stickerOverlayStyle: .triangle
            )

        case .statSquare:
            return SessionArtLayout(
                headerOrigin: CGPoint(x: w * 0.18, y: h * 0.08),
                lineOrigins: squareLineOrigins(keys: layoutKeys, in: canvasSize),
                footerCenter: CGPoint(x: w * 0.5, y: h * 0.9),
                headerScale: 0.9,
                metricsScale: 0.8,
                footerScale: 0.9,
                brandingScale: 0.82,
                brandingOffset: .zero,
                underlayZoom: 1.03,
                underlayPan: .zero,
                showBranding: false,
                headerFocus: .game,
                emphasizedMetric: nil,
                emphasisScale: 1,
                stickerOverlayStyle: .square
            )

        case .stickerSpade:
            return SessionArtLayout(
                headerOrigin: CGPoint(x: w * 0.18, y: h * 0.08),
                lineOrigins: ringLineOrigins(
                    keys: layoutKeys,
                    center: CGPoint(x: w * 0.5, y: h * 0.56),
                    radius: min(w, h) * 0.24
                ),
                footerCenter: CGPoint(x: w * 0.5, y: h * 0.9),
                headerScale: 0.88,
                metricsScale: 0.8,
                footerScale: 0.88,
                brandingScale: 0.8,
                brandingOffset: .zero,
                underlayZoom: 1.03,
                underlayPan: .zero,
                showBranding: false,
                headerFocus: .game,
                emphasizedMetric: nil,
                emphasisScale: 1,
                stickerOverlayStyle: .suitSpade
            )

        case .stickerHeart:
            return SessionArtLayout(
                headerOrigin: CGPoint(x: w * 0.18, y: h * 0.08),
                lineOrigins: ringLineOrigins(
                    keys: layoutKeys,
                    center: CGPoint(x: w * 0.5, y: h * 0.56),
                    radius: min(w, h) * 0.24
                ),
                footerCenter: CGPoint(x: w * 0.5, y: h * 0.9),
                headerScale: 0.88,
                metricsScale: 0.8,
                footerScale: 0.88,
                brandingScale: 0.8,
                brandingOffset: .zero,
                underlayZoom: 1.03,
                underlayPan: .zero,
                showBranding: false,
                headerFocus: .game,
                emphasizedMetric: nil,
                emphasisScale: 1,
                stickerOverlayStyle: .suitHeart
            )

        case .stickerDiamond:
            return SessionArtLayout(
                headerOrigin: CGPoint(x: w * 0.18, y: h * 0.08),
                lineOrigins: ringLineOrigins(
                    keys: layoutKeys,
                    center: CGPoint(x: w * 0.5, y: h * 0.56),
                    radius: min(w, h) * 0.24
                ),
                footerCenter: CGPoint(x: w * 0.5, y: h * 0.9),
                headerScale: 0.88,
                metricsScale: 0.8,
                footerScale: 0.88,
                brandingScale: 0.8,
                brandingOffset: .zero,
                underlayZoom: 1.03,
                underlayPan: .zero,
                showBranding: false,
                headerFocus: .game,
                emphasizedMetric: nil,
                emphasisScale: 1,
                stickerOverlayStyle: .suitDiamond
            )

        case .stickerClub:
            return SessionArtLayout(
                headerOrigin: CGPoint(x: w * 0.18, y: h * 0.08),
                lineOrigins: ringLineOrigins(
                    keys: layoutKeys,
                    center: CGPoint(x: w * 0.5, y: h * 0.56),
                    radius: min(w, h) * 0.24
                ),
                footerCenter: CGPoint(x: w * 0.5, y: h * 0.9),
                headerScale: 0.88,
                metricsScale: 0.8,
                footerScale: 0.88,
                brandingScale: 0.8,
                brandingOffset: .zero,
                underlayZoom: 1.03,
                underlayPan: .zero,
                showBranding: false,
                headerFocus: .game,
                emphasizedMetric: nil,
                emphasisScale: 1,
                stickerOverlayStyle: .suitClub
            )

        case .aceSpadesCard:
            return SessionArtLayout(
                headerOrigin: CGPoint(x: w * 0.18, y: h * 0.08),
                lineOrigins: ringLineOrigins(
                    keys: layoutKeys,
                    center: CGPoint(x: w * 0.5, y: h * 0.56),
                    radius: min(w, h) * 0.24
                ),
                footerCenter: CGPoint(x: w * 0.5, y: h * 0.9),
                headerScale: 0.88,
                metricsScale: 0.8,
                footerScale: 0.88,
                brandingScale: 0.8,
                brandingOffset: .zero,
                underlayZoom: 1.03,
                underlayPan: .zero,
                showBranding: false,
                headerFocus: .game,
                emphasizedMetric: nil,
                emphasisScale: 1,
                stickerOverlayStyle: .aceSpades
            )

        case .aceDiamondsCard:
            return SessionArtLayout(
                headerOrigin: CGPoint(x: w * 0.18, y: h * 0.08),
                lineOrigins: ringLineOrigins(
                    keys: layoutKeys,
                    center: CGPoint(x: w * 0.5, y: h * 0.56),
                    radius: min(w, h) * 0.24
                ),
                footerCenter: CGPoint(x: w * 0.5, y: h * 0.9),
                headerScale: 0.88,
                metricsScale: 0.8,
                footerScale: 0.88,
                brandingScale: 0.8,
                brandingOffset: .zero,
                underlayZoom: 1.03,
                underlayPan: .zero,
                showBranding: false,
                headerFocus: .game,
                emphasizedMetric: nil,
                emphasisScale: 1,
                stickerOverlayStyle: .aceDiamonds
            )

        case .aceHeartsCard:
            return SessionArtLayout(
                headerOrigin: CGPoint(x: w * 0.18, y: h * 0.08),
                lineOrigins: ringLineOrigins(
                    keys: layoutKeys,
                    center: CGPoint(x: w * 0.5, y: h * 0.56),
                    radius: min(w, h) * 0.24
                ),
                footerCenter: CGPoint(x: w * 0.5, y: h * 0.9),
                headerScale: 0.88,
                metricsScale: 0.8,
                footerScale: 0.88,
                brandingScale: 0.8,
                brandingOffset: .zero,
                underlayZoom: 1.03,
                underlayPan: .zero,
                showBranding: false,
                headerFocus: .game,
                emphasizedMetric: nil,
                emphasisScale: 1,
                stickerOverlayStyle: .aceHearts
            )

        case .jackCard:
            return SessionArtLayout(
                headerOrigin: CGPoint(x: w * 0.18, y: h * 0.08),
                lineOrigins: ringLineOrigins(
                    keys: layoutKeys,
                    center: CGPoint(x: w * 0.5, y: h * 0.56),
                    radius: min(w, h) * 0.24
                ),
                footerCenter: CGPoint(x: w * 0.5, y: h * 0.9),
                headerScale: 0.88,
                metricsScale: 0.8,
                footerScale: 0.88,
                brandingScale: 0.8,
                brandingOffset: .zero,
                underlayZoom: 1.03,
                underlayPan: .zero,
                showBranding: false,
                headerFocus: .game,
                emphasizedMetric: nil,
                emphasisScale: 1,
                stickerOverlayStyle: .jackCard
            )

        case .eightSpadesCard:
            return SessionArtLayout(
                headerOrigin: CGPoint(x: w * 0.18, y: h * 0.08),
                lineOrigins: ringLineOrigins(
                    keys: layoutKeys,
                    center: CGPoint(x: w * 0.5, y: h * 0.56),
                    radius: min(w, h) * 0.24
                ),
                footerCenter: CGPoint(x: w * 0.5, y: h * 0.9),
                headerScale: 0.88,
                metricsScale: 0.8,
                footerScale: 0.88,
                brandingScale: 0.8,
                brandingOffset: .zero,
                underlayZoom: 1.03,
                underlayPan: .zero,
                showBranding: false,
                headerFocus: .game,
                emphasizedMetric: nil,
                emphasisScale: 1,
                stickerOverlayStyle: .eightSpades
            )

        case .nineSpadesCard:
            return SessionArtLayout(
                headerOrigin: CGPoint(x: w * 0.18, y: h * 0.08),
                lineOrigins: ringLineOrigins(
                    keys: layoutKeys,
                    center: CGPoint(x: w * 0.5, y: h * 0.56),
                    radius: min(w, h) * 0.24
                ),
                footerCenter: CGPoint(x: w * 0.5, y: h * 0.9),
                headerScale: 0.88,
                metricsScale: 0.8,
                footerScale: 0.88,
                brandingScale: 0.8,
                brandingOffset: .zero,
                underlayZoom: 1.03,
                underlayPan: .zero,
                showBranding: false,
                headerFocus: .game,
                emphasizedMetric: nil,
                emphasisScale: 1,
                stickerOverlayStyle: .nineSpades
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
        func named(_ name: String) -> UIFont? {
            UIFont(name: name, size: size)
        }
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
        case .avenir:
            return named("AvenirNext-Regular") ?? base
        case .avenirHeavy:
            return named("AvenirNext-Heavy") ?? named("AvenirNext-DemiBold") ?? base
        case .helveticaNeue:
            return named("HelveticaNeue-Medium") ?? named("HelveticaNeue") ?? base
        case .futura:
            return named("Futura-Medium") ?? base
        case .georgia:
            return named("Georgia-Bold") ?? named("Georgia") ?? base
        case .gillSans:
            return named("GillSans-SemiBold") ?? named("GillSans") ?? base
        case .chalkboard:
            return named("ChalkboardSE-Bold") ?? named("ChalkboardSE-Regular") ?? base
        case .noteworthy:
            return named("Noteworthy-Bold") ?? named("Noteworthy-Light") ?? base
        case .courierNew:
            return named("CourierNewPS-BoldMT") ?? named("CourierNewPSMT") ?? base
        case .optima:
            return named("Optima-ExtraBlack") ?? named("Optima-Bold") ?? named("Optima-Regular") ?? base
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

            drawStickerOverlay(style: layout.stickerOverlayStyle, in: canvas, cg: cg)
            drawStickerOverlay(style: layout.secondaryOverlayStyle, in: canvas, cg: cg)

            if params.includeMetrics {
                drawMetricsBlock(
                    params: params,
                    layout: layout,
                    in: canvas,
                    cg: cg
                )
            }

            drawHeader(params: params, layout: layout, in: canvas, cg: cg)
            drawBranding(in: canvas, layout: layout, params: params, cg: cg)
            drawFooterCaption(
                params.footerCaption,
                center: layout.footerCenter,
                footerScale: layout.footerScale,
                params: params,
                in: canvas,
                cg: cg
            )
            drawBorderOverlay(style: layout.borderStyle, in: canvas, cg: cg)
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
            }
            drawStickerOverlay(style: layout.stickerOverlayStyle, in: canvas, cg: cg)
            drawStickerOverlay(style: layout.secondaryOverlayStyle, in: canvas, cg: cg)
            if params.includeMetrics {
                drawMetricsBlock(
                    params: params,
                    layout: layout,
                    in: canvas,
                    cg: cg
                )
            }

            drawHeader(params: params, layout: layout, in: canvas, cg: cg)
            drawBranding(in: canvas, layout: layout, params: params, cg: cg)
            drawFooterCaption(
                params.footerCaption,
                center: layout.footerCenter,
                footerScale: layout.footerScale,
                params: params,
                in: canvas,
                cg: cg
            )
            drawBorderOverlay(style: layout.borderStyle, in: canvas, cg: cg)
        }
    }

    private static func drawBackground(in size: CGSize, cg: CGContext) {
        cg.setFillColor(UIColor(red: 0.06, green: 0.12, blue: 0.08, alpha: 1).cgColor)
        cg.fill(CGRect(origin: .zero, size: size))
    }

    private static func drawBorderOverlay(style: SessionArtBorderStyle, in size: CGSize, cg: CGContext) {
        guard style != .none else { return }
        let s = layoutScale(forCanvasWidth: size.width)
        let canvasRect = CGRect(origin: .zero, size: size)

        switch style {
        case .none:
            return
        case .vintagePaper:
            let outerInset = 20 * s
            let innerInset = 44 * s
            let outer = canvasRect.insetBy(dx: outerInset, dy: outerInset)
            let inner = canvasRect.insetBy(dx: innerInset, dy: innerInset)
            cg.setStrokeColor(UIColor.white.withAlphaComponent(0.95).cgColor)
            cg.setLineWidth(14 * s)
            cg.stroke(outer)
            cg.setStrokeColor(UIColor(red: 0.84, green: 0.72, blue: 0.52, alpha: 0.95).cgColor)
            cg.setLineWidth(3 * s)
            cg.stroke(inner)
        case .matteFrame:
            let frame = canvasRect.insetBy(dx: 12 * s, dy: 12 * s)
            let matte = canvasRect.insetBy(dx: 38 * s, dy: 38 * s)
            cg.setStrokeColor(UIColor.black.withAlphaComponent(0.85).cgColor)
            cg.setLineWidth(22 * s)
            cg.stroke(frame)
            cg.setStrokeColor(UIColor.white.withAlphaComponent(0.97).cgColor)
            cg.setLineWidth(14 * s)
            cg.stroke(matte)
        case .artDeco:
            let inner = canvasRect.insetBy(dx: 34 * s, dy: 34 * s)
            cg.setStrokeColor(UIColor(red: 0.86, green: 0.68, blue: 0.37, alpha: 0.98).cgColor)
            cg.setLineWidth(5 * s)
            cg.stroke(inner)

            let corner = max(34 * s, size.width * 0.09)
            cg.setStrokeColor(UIColor(red: 0.92, green: 0.82, blue: 0.61, alpha: 0.95).cgColor)
            cg.setLineWidth(3 * s)
            cg.strokeLineSegments(between: [
                CGPoint(x: inner.minX, y: inner.minY + corner), CGPoint(x: inner.minX, y: inner.minY),
                CGPoint(x: inner.minX, y: inner.minY), CGPoint(x: inner.minX + corner, y: inner.minY),
                CGPoint(x: inner.maxX - corner, y: inner.minY), CGPoint(x: inner.maxX, y: inner.minY),
                CGPoint(x: inner.maxX, y: inner.minY), CGPoint(x: inner.maxX, y: inner.minY + corner),
                CGPoint(x: inner.minX, y: inner.maxY - corner), CGPoint(x: inner.minX, y: inner.maxY),
                CGPoint(x: inner.minX, y: inner.maxY), CGPoint(x: inner.minX + corner, y: inner.maxY),
                CGPoint(x: inner.maxX - corner, y: inner.maxY), CGPoint(x: inner.maxX, y: inner.maxY),
                CGPoint(x: inner.maxX, y: inner.maxY - corner), CGPoint(x: inner.maxX, y: inner.maxY)
            ])
        case .woodFrame:
            let frame = canvasRect.insetBy(dx: 14 * s, dy: 14 * s)
            let matte = canvasRect.insetBy(dx: 44 * s, dy: 44 * s)
            cg.setStrokeColor(UIColor(red: 0.74, green: 0.60, blue: 0.42, alpha: 0.98).cgColor)
            cg.setLineWidth(26 * s)
            cg.stroke(frame)
            cg.setStrokeColor(UIColor(red: 0.86, green: 0.74, blue: 0.57, alpha: 0.85).cgColor)
            cg.setLineWidth(8 * s)
            cg.stroke(frame.insetBy(dx: 7 * s, dy: 7 * s))
            cg.setStrokeColor(UIColor.white.withAlphaComponent(0.97).cgColor)
            cg.setLineWidth(12 * s)
            cg.stroke(matte)
        }
    }

    private static func drawStickerOverlay(style: SessionArtStickerOverlayStyle, in size: CGSize, cg: CGContext) {
        guard style != .none else { return }
        let s = layoutScale(forCanvasWidth: size.width)
        let stroke = UIColor.white.withAlphaComponent(0.88).cgColor
        let fill = UIColor.black.withAlphaComponent(0.28).cgColor
        let suitRed = UIColor(red: 0.84, green: 0.16, blue: 0.24, alpha: 0.94)

        func drawSuitCard(symbol: String, accent: UIColor) {
            let card = CGRect(
                x: size.width * 0.26,
                y: size.height * 0.30,
                width: size.width * 0.48,
                height: size.height * 0.52
            )
            cg.setFillColor(UIColor.black.withAlphaComponent(0.38).cgColor)
            cg.addPath(UIBezierPath(roundedRect: card, cornerRadius: 34 * s).cgPath)
            cg.fillPath()
            cg.setStrokeColor(UIColor.white.withAlphaComponent(0.92).cgColor)
            cg.setLineWidth(max(1.8 * s, 5))
            cg.addPath(UIBezierPath(roundedRect: card, cornerRadius: 34 * s).cgPath)
            cg.strokePath()

            let font = styledFont(size: 210 * s, weight: .black, style: .serif)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: accent
            ]
            let ns = symbol as NSString
            let bounds = ns.size(withAttributes: attrs)
            let point = CGPoint(
                x: card.midX - bounds.width * 0.5,
                y: card.midY - bounds.height * 0.52
            )
            ns.draw(at: point, withAttributes: attrs)
        }

        func drawRankCard(rank: String, suit: String, accent: UIColor) {
            let card = CGRect(
                x: size.width * 0.26,
                y: size.height * 0.30,
                width: size.width * 0.48,
                height: size.height * 0.52
            )
            cg.setFillColor(UIColor.black.withAlphaComponent(0.36).cgColor)
            cg.addPath(UIBezierPath(roundedRect: card, cornerRadius: 34 * s).cgPath)
            cg.fillPath()
            cg.setStrokeColor(UIColor.white.withAlphaComponent(0.93).cgColor)
            cg.setLineWidth(max(1.8 * s, 5))
            cg.addPath(UIBezierPath(roundedRect: card, cornerRadius: 34 * s).cgPath)
            cg.strokePath()

            let cornerFont = styledFont(size: 68 * s, weight: .bold, style: .serif)
            let cornerAttrs: [NSAttributedString.Key: Any] = [
                .font: cornerFont,
                .foregroundColor: accent
            ]
            let cornerText = "\(rank)\(suit)" as NSString
            cornerText.draw(at: CGPoint(x: card.minX + 22 * s, y: card.minY + 18 * s), withAttributes: cornerAttrs)

            let cornerSize = cornerText.size(withAttributes: cornerAttrs)
            cornerText.draw(
                at: CGPoint(
                    x: card.maxX - cornerSize.width - 22 * s,
                    y: card.maxY - cornerSize.height - 18 * s
                ),
                withAttributes: cornerAttrs
            )

            let centerFont = styledFont(size: 170 * s, weight: .black, style: .serif)
            let centerAttrs: [NSAttributedString.Key: Any] = [
                .font: centerFont,
                .foregroundColor: accent
            ]
            let centerText = suit as NSString
            let bounds = centerText.size(withAttributes: centerAttrs)
            centerText.draw(
                at: CGPoint(
                    x: card.midX - bounds.width * 0.5,
                    y: card.midY - bounds.height * 0.56
                ),
                withAttributes: centerAttrs
            )
        }

        func drawArtDecoImage(named name: String) {
            guard let image = UIImage(named: name) else { return }
            let side = min(size.width, size.height) * 0.62
            let rect = CGRect(
                x: (size.width - side) * 0.5,
                y: size.height * 0.23,
                width: side,
                height: side
            )
            cg.saveGState()
            cg.setShadow(
                offset: CGSize(width: 0, height: 8 * s),
                blur: 18 * s,
                color: UIColor.black.withAlphaComponent(0.58).cgColor
            )
            cg.setAlpha(0.9)
            image.draw(in: rect)
            cg.restoreGState()
        }

        cg.saveGState()
        cg.setStrokeColor(stroke)
        cg.setFillColor(fill)

        switch style {
        case .none:
            break
        case .circle:
            let r = min(size.width, size.height) * 0.28
            let c = CGPoint(x: size.width * 0.5, y: size.height * 0.56)
            cg.setLineWidth(max(2 * s, 7))
            cg.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            cg.setLineWidth(max(1.2 * s, 4))
            let innerR = r * 0.8
            cg.strokeEllipse(in: CGRect(x: c.x - innerR, y: c.y - innerR, width: innerR * 2, height: innerR * 2))
        case .triangle:
            let top = CGPoint(x: size.width * 0.5, y: size.height * 0.28)
            let left = CGPoint(x: size.width * 0.2, y: size.height * 0.72)
            let right = CGPoint(x: size.width * 0.8, y: size.height * 0.72)
            let midY = size.height * 0.52
            let path = UIBezierPath()
            path.move(to: top)
            path.addLine(to: left)
            path.addLine(to: right)
            path.close()
            cg.addPath(path.cgPath)
            cg.setLineWidth(max(2 * s, 6))
            cg.drawPath(using: .fillStroke)
            cg.setStrokeColor(UIColor.white.withAlphaComponent(0.74).cgColor)
            cg.setLineWidth(max(1.2 * s, 3.5))
            cg.strokeLineSegments(between: [
                CGPoint(x: size.width * 0.35, y: midY), CGPoint(x: size.width * 0.65, y: midY),
                CGPoint(x: size.width * 0.35, y: midY), left,
                CGPoint(x: size.width * 0.65, y: midY), right
            ])
        case .square:
            let rect = CGRect(
                x: size.width * 0.17,
                y: size.height * 0.30,
                width: size.width * 0.66,
                height: size.width * 0.66
            )
            cg.setLineWidth(max(2 * s, 6))
            cg.stroke(rect)
            let inner = rect.insetBy(dx: rect.width * 0.08, dy: rect.height * 0.08)
            cg.setLineWidth(max(1.4 * s, 3.5))
            cg.stroke(inner)
        case .suitSpade:
            drawSuitCard(symbol: "♠", accent: .white)
        case .suitHeart:
            drawSuitCard(symbol: "♥", accent: suitRed)
        case .suitDiamond:
            drawSuitCard(symbol: "♦", accent: suitRed)
        case .suitClub:
            drawSuitCard(symbol: "♣", accent: .white)
        case .aceSpades:
            drawRankCard(rank: "A", suit: "♠", accent: .white)
        case .aceDiamonds:
            drawRankCard(rank: "A", suit: "♦", accent: suitRed)
        case .aceHearts:
            drawRankCard(rank: "A", suit: "♥", accent: suitRed)
        case .jackCard:
            drawRankCard(rank: "J", suit: "♠", accent: .white)
        case .eightSpades:
            drawRankCard(rank: "8", suit: "♠", accent: .white)
        case .nineSpades:
            drawRankCard(rank: "9", suit: "♠", accent: .white)
        case .artDecoSlotMachine:
            drawArtDecoImage(named: "SessionArtDecoSlotMachine")
        case .artDecoDice:
            drawArtDecoImage(named: "SessionArtDecoDice")
        case .artDecoJoker:
            drawArtDecoImage(named: "SessionArtDecoJoker")
        case .artDecoMoneyBag:
            drawArtDecoImage(named: "SessionArtDecoMoneyBag")
        case .artDecoGem:
            drawArtDecoImage(named: "SessionArtDecoGem")
        case .artDecoCoin:
            drawArtDecoImage(named: "SessionArtDecoCoin")
        case .artDecoTicket:
            drawArtDecoImage(named: "SessionArtDecoTicket")
        case .artDecoCrown:
            drawArtDecoImage(named: "SessionArtDecoCrown")
        case .artDecoSparkles:
            drawArtDecoImage(named: "SessionArtDecoSparkles")
        case .artDecoSpade:
            drawArtDecoImage(named: "SessionArtDecoSpade")
        case .artDecoHeart:
            drawArtDecoImage(named: "SessionArtDecoHeart")
        case .artDecoDiamond:
            drawArtDecoImage(named: "SessionArtDecoDiamond")
        }

        cg.restoreGState()
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
        let isStickerLayout = layout.stickerOverlayStyle.usesStickerMetricPlacements
        let stickerCenter = CGPoint(x: size.width * 0.5, y: size.height * 0.56)
        let primaryKey = keys.first

        func stickerLabel(for key: MetricLineKey, defaultTitle: String) -> String {
            switch key {
            case .tierBump: return "TIER"
            case .buyIn: return "BUY-IN"
            case .cashOut: return "CASH OUT"
            case .winLoss: return "WIN/LOSS"
            case .winRate: return "RATE"
            case .tiersPerHour: return "TPH"
            case .comps: return "COMPS"
            }
        }

        func stickerEdgePlacement(secondaryIndex: Int, total: Int) -> (point: CGPoint, angle: CGFloat) {
            switch layout.stickerOverlayStyle {
            case .circle:
                let radius = min(size.width, size.height) * 0.345
                let start = -CGFloat.pi * 0.70
                let step = (CGFloat.pi * 1.4) / CGFloat(max(1, total - 1))
                let theta = start + step * CGFloat(secondaryIndex)
                let point = CGPoint(
                    x: stickerCenter.x + cos(theta) * radius,
                    y: stickerCenter.y + sin(theta) * radius
                )
                var tangent = theta + .pi / 2
                if tangent > .pi / 2 { tangent -= .pi }
                if tangent < -.pi / 2 { tangent += .pi }
                return (point, tangent)
            case .triangle:
                let placements: [(CGPoint, CGFloat)] = [
                    (CGPoint(x: size.width * 0.5, y: size.height * 0.23), 0),
                    (CGPoint(x: size.width * 0.27, y: size.height * 0.54), -0.96),
                    (CGPoint(x: size.width * 0.73, y: size.height * 0.54), 0.96)
                ]
                return placements[secondaryIndex % placements.count]
            case .square:
                let placements: [(CGPoint, CGFloat)] = [
                    (CGPoint(x: size.width * 0.5, y: size.height * 0.24), 0),
                    (CGPoint(x: size.width * 0.86, y: size.height * 0.56), .pi / 2),
                    (CGPoint(x: size.width * 0.5, y: size.height * 0.82), 0),
                    (CGPoint(x: size.width * 0.14, y: size.height * 0.56), -.pi / 2)
                ]
                return placements[secondaryIndex % placements.count]
            case .suitSpade, .suitHeart, .suitDiamond, .suitClub,
                 .aceSpades, .aceDiamonds, .aceHearts, .jackCard, .eightSpades, .nineSpades,
                 .artDecoSlotMachine, .artDecoDice, .artDecoJoker, .artDecoMoneyBag,
                 .artDecoGem, .artDecoCoin, .artDecoTicket, .artDecoCrown,
                 .artDecoSparkles, .artDecoSpade, .artDecoHeart, .artDecoDiamond:
                let placements: [(CGPoint, CGFloat)] = [
                    (CGPoint(x: size.width * 0.5, y: size.height * 0.23), 0),
                    (CGPoint(x: size.width * 0.84, y: size.height * 0.56), .pi / 2),
                    (CGPoint(x: size.width * 0.5, y: size.height * 0.87), 0),
                    (CGPoint(x: size.width * 0.16, y: size.height * 0.56), -.pi / 2)
                ]
                return placements[secondaryIndex % placements.count]
            case .none:
                return (CGPoint(x: size.width * 0.5, y: size.height * 0.5), 0)
            }
        }

        func drawStickerEdgeMetric(_ text: String, at point: CGPoint, angle: CGFloat) {
            let font = styledFont(size: max(16 * s, 20 * s * ms), weight: .bold, style: params.fontStyle)
            let shadow = NSShadow()
            shadow.shadowColor = UIColor.black.withAlphaComponent(0.62)
            shadow.shadowOffset = CGSize(width: 0, height: 2 * s)
            shadow.shadowBlurRadius = 4 * s
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: metricValueColor,
                .shadow: shadow
            ]
            let ns = text as NSString
            let bounds = ns.size(withAttributes: attrs)
            cg.saveGState()
            cg.translateBy(x: point.x, y: point.y)
            cg.rotate(by: angle)
            ns.draw(at: CGPoint(x: -bounds.width * 0.5, y: -bounds.height * 0.5), withAttributes: attrs)
            cg.restoreGState()
        }

        func paintMetricLine(title: String, value: String, key: MetricLineKey) {
            let origin = layout.lineOrigins[key] ?? CGPoint(x: 36 * s, y: size.height * 0.42)
            let isEmphasized = layout.emphasizedMetric == key
            let titleFont: UIFont
            let valueFont: UIFont
            let titleX: CGFloat
            let valueX: CGFloat
            let titleToDraw: String

            if isStickerLayout {
                let metricIndex = keys.firstIndex(of: key) ?? 0
                let isPrimary = key == primaryKey && metricIndex == 0
                if !isPrimary {
                    let secondaryIndex = max(0, metricIndex - 1)
                    let placement = stickerEdgePlacement(secondaryIndex: secondaryIndex, total: max(1, keys.count - 1))
                    let edgeText = "\(value) · \(stickerLabel(for: key, defaultTitle: title))"
                    drawStickerEdgeMetric(edgeText, at: placement.point, angle: placement.angle)
                    return
                }
                titleToDraw = stickerLabel(for: key, defaultTitle: title)
                let titleSz = max(14 * s, 17 * s * ms)
                let valueSz = max(38 * s, 54 * s * ms)
                titleFont = styledFont(size: titleSz, weight: .semibold, style: params.fontStyle)
                valueFont = styledFont(size: valueSz, weight: .heavy, style: params.fontStyle)
                let titleWidth = (titleToDraw as NSString).size(withAttributes: [.font: titleFont]).width
                let valueWidth = (value as NSString).size(withAttributes: [.font: valueFont]).width
                let centerPoint: CGPoint
                switch layout.stickerOverlayStyle {
                case .circle:
                    centerPoint = stickerCenter
                case .triangle:
                    centerPoint = CGPoint(x: size.width * 0.5, y: size.height * 0.36)
                case .square:
                    centerPoint = CGPoint(x: size.width * 0.58, y: size.height * 0.34)
                case .suitSpade, .suitHeart, .suitDiamond, .suitClub,
                     .aceSpades, .aceDiamonds, .aceHearts, .jackCard, .eightSpades, .nineSpades,
                     .artDecoSlotMachine, .artDecoDice, .artDecoJoker, .artDecoMoneyBag,
                     .artDecoGem, .artDecoCoin, .artDecoTicket, .artDecoCrown,
                     .artDecoSparkles, .artDecoSpade, .artDecoHeart, .artDecoDiamond:
                    centerPoint = CGPoint(x: size.width * 0.5, y: size.height * 0.35)
                case .none:
                    centerPoint = origin
                }
                titleX = centerPoint.x - titleWidth * 0.5
                valueX = centerPoint.x - valueWidth * 0.5
            } else if isEmphasized {
                titleToDraw = title
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
                titleToDraw = title
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
            let yBase: CGFloat
            if isStickerLayout {
                switch layout.stickerOverlayStyle {
                case .circle:
                    yBase = stickerCenter.y - valueFont.lineHeight * 0.56
                case .triangle:
                    yBase = size.height * 0.30
                case .square:
                    yBase = size.height * 0.28
                case .suitSpade, .suitHeart, .suitDiamond, .suitClub,
                     .aceSpades, .aceDiamonds, .aceHearts, .jackCard, .eightSpades, .nineSpades,
                     .artDecoSlotMachine, .artDecoDice, .artDecoJoker, .artDecoMoneyBag,
                     .artDecoGem, .artDecoCoin, .artDecoTicket, .artDecoCrown,
                     .artDecoSparkles, .artDecoSpade, .artDecoHeart, .artDecoDiamond:
                    yBase = size.height * 0.29
                case .none:
                    yBase = origin.y
                }
            } else {
                yBase = origin.y
            }
            let safeY = max(safe.minY, min(yBase, safe.maxY - titleFont.lineHeight - valueFont.lineHeight - 24 * s))
            let lineGap = isStickerLayout ? (2 * s * ms) : (10 * s * ms)
            let valueBaseline = safeY + titleFont.lineHeight + lineGap
            let titleWidth = (titleToDraw as NSString).size(withAttributes: ta).width
            let valueWidth = (value as NSString).size(withAttributes: va).width
            let minX = min(titleX, valueX)
            let maxX = max(titleX + titleWidth, valueX + valueWidth)
            let bgRect = CGRect(
                x: minX - 14 * s,
                y: safeY - 10 * s,
                width: (maxX - minX) + 28 * s,
                height: (valueBaseline + valueFont.lineHeight - safeY) + 18 * s
            )
            if params.textBackgroundOpacity > 0.01 && !isStickerLayout {
                cg.saveGState()
                cg.setFillColor(metricBackgroundColor.cgColor)
                cg.addPath(UIBezierPath(roundedRect: bgRect, cornerRadius: 12 * s).cgPath)
                cg.fillPath()
                cg.restoreGState()
            }
            (titleToDraw as NSString).draw(at: CGPoint(x: titleX, y: safeY), withAttributes: ta)
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
    @Binding var selectedBaseTemplate: SessionArtTemplate
    @Binding var selectedStickerTemplate: SessionArtTemplate?
    @Binding var selectedArtDecoTemplate: SessionArtTemplate?
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
    @State private var templatesControlsExpanded = false
    @State private var fontsControlsExpanded = false
    @State private var colorsControlsExpanded = false
    @State private var templatePickerGroup: SessionArtPickerGroup = .templates
    @State private var templateThumbnailCache: [SessionArtTemplate: UIImage] = [:]
    @State private var templateThumbnailTask: Task<Void, Never>?

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
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
            }
            .onAppear {
                templatePickerGroup = .templates
                configurePreviewVideoPlayerIfNeeded()
                refreshPreviewImage()
                warmTemplateThumbnails(for: templatePickerGroup)
            }
            .onDisappear {
                previewProgressTask?.cancel()
                previewProgressTask = nil
                templateThumbnailTask?.cancel()
                templateThumbnailTask = nil
                tearDownPreviewVideoPlayer()
            }
            .onChange(of: videoUnderlayURL) { _ in
                configurePreviewVideoPlayerIfNeeded()
                refreshPreviewImage()
            }
            .onChange(of: selectedBaseTemplate) { _ in
                refreshPreviewImage()
            }
            .onChange(of: selectedStickerTemplate) { _ in
                refreshPreviewImage()
            }
            .onChange(of: selectedArtDecoTemplate) { _ in
                refreshPreviewImage()
            }
            .onChange(of: templatePickerGroup) { group in
                warmTemplateThumbnails(for: group)
            }
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
            VStack(alignment: .leading, spacing: 8) {
                collapsibleControlsBubble(
                    title: "Templates + Stickers + Art Deco",
                    subtitle: selectionSubtitle,
                    icon: "photo.on.rectangle",
                    isExpanded: $templatesControlsExpanded
                ) {
                    Picker("Template group", selection: $templatePickerGroup) {
                        ForEach(SessionArtPickerGroup.allCases) { group in
                            Text(group.rawValue).tag(group)
                        }
                    }
                    .pickerStyle(.segmented)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(filteredTemplates) { template in
                                templateThumbnailButton(template)
                            }
                        }
                    }
                    .frame(height: 170)
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

    private var filteredTemplates: [SessionArtTemplate] {
        SessionArtTemplate.allCases.filter { $0.pickerGroup == templatePickerGroup }
    }

    private var stickerModeActive: Bool {
        selectedStickerTemplate != nil
    }

    private var selectionSubtitle: String {
        let parts: [String] = [
            selectedBaseTemplate.shortTitle,
            selectedStickerTemplate?.shortTitle ?? "No sticker",
            selectedArtDecoTemplate?.shortTitle ?? "No art deco"
        ]
        return parts.joined(separator: " · ")
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
                .padding(10)
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                VStack(alignment: .leading, spacing: 8) {
                    content()
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
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
            VStack(alignment: .leading, spacing: 6) {
                Text("Font")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(SessionArtTextFont.allCases) { font in
                            Button {
                                selectedTextFont = font
                            } label: {
                                Text(font.label)
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(selectedTextFont == font ? Color.green.opacity(0.22) : Color.secondary.opacity(0.08))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(selectedTextFont == font ? Color.green : Color.clear, lineWidth: 1.4)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

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
        let selected = isTemplateSelected(template)
        let thumbnail = templateThumbnailCache[template]
        return Button {
            withAnimation(.spring(response: 0.46, dampingFraction: 0.82, blendDuration: 0.12)) {
                applyTemplateSelectionToggle(template)
                layout = composedLayout()
            }
        } label: {
            VStack(spacing: 0) {
                Group {
                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .interpolation(.high)
                    } else {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.08))
                            .overlay {
                                ProgressView()
                                    .tint(.green)
                            }
                    }
                }
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
            .offset(y: selected ? -8 : 0)
            .animation(.spring(response: 0.46, dampingFraction: 0.82, blendDuration: 0.12), value: selected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(template.shortTitle) preset\(selected ? ", selected" : "")")
    }

    private func isTemplateSelected(_ template: SessionArtTemplate) -> Bool {
        switch template.pickerGroup {
        case .templates:
            return selectedBaseTemplate == template
        case .stickers:
            return selectedStickerTemplate == template
        case .artDeco:
            return selectedArtDecoTemplate == template
        }
    }

    private func applyTemplateSelectionToggle(_ template: SessionArtTemplate) {
        switch template.pickerGroup {
        case .templates:
            selectedBaseTemplate = template
        case .stickers:
            selectedStickerTemplate = (selectedStickerTemplate == template) ? nil : template
        case .artDeco:
            selectedArtDecoTemplate = (selectedArtDecoTemplate == template) ? nil : template
        }
    }

    private func composedLayout() -> SessionArtLayout {
        var composed = selectedBaseTemplate.makeLayout(
            session: session,
            publishTierPerHour: publishTierPerHour || stickerModeActive,
            publishWinLoss: publishWinLoss || stickerModeActive,
            publishBuyInCashOut: publishBuyInCashOut || stickerModeActive,
            publishCompDetails: publishCompDetails || stickerModeActive,
            canvasSize: designSize
        )

        if let stickerTemplate = selectedStickerTemplate {
            let stickerLayout = stickerTemplate.makeLayout(
                session: session,
                publishTierPerHour: true,
                publishWinLoss: true,
                publishBuyInCashOut: true,
                publishCompDetails: true,
                canvasSize: designSize
            )
            composed.stickerOverlayStyle = stickerLayout.stickerOverlayStyle
            if stickerLayout.borderStyle != .none {
                composed.borderStyle = stickerLayout.borderStyle
            }
        } else {
            composed.stickerOverlayStyle = .none
        }

        if let decoTemplate = selectedArtDecoTemplate {
            let decoLayout = decoTemplate.makeLayout(
                session: session,
                publishTierPerHour: publishTierPerHour || stickerModeActive,
                publishWinLoss: publishWinLoss || stickerModeActive,
                publishBuyInCashOut: publishBuyInCashOut || stickerModeActive,
                publishCompDetails: publishCompDetails || stickerModeActive,
                canvasSize: designSize
            )
            if decoLayout.borderStyle != .none {
                composed.borderStyle = decoLayout.borderStyle
            }
            composed.secondaryOverlayStyle = decoLayout.stickerOverlayStyle
        } else {
            composed.secondaryOverlayStyle = .none
        }

        return composed
    }

    private func warmTemplateThumbnails(for group: SessionArtPickerGroup) {
        templateThumbnailTask?.cancel()
        let templates = SessionArtTemplate.allCases.filter { $0.pickerGroup == group }
        let session = session
        let includeMetrics = includeMetrics
        let publishTierPerHour = publishTierPerHour
        let publishWinLoss = publishWinLoss
        let publishBuyInCashOut = publishBuyInCashOut
        let publishCompDetails = publishCompDetails
        let currencySymbol = currencySymbol
        let footerCaption = footerCaption
        let selectedTextFont = selectedTextFont
        let globalTextScale = globalTextScale
        let selectedTextColor = selectedTextColor
        let selectedTextBackgroundColor = selectedTextBackgroundColor
        let textBackgroundOpacity = textBackgroundOpacity
        let designSize = designSize

        templateThumbnailTask = Task(priority: .utility) {
            for template in templates {
                if Task.isCancelled { return }
                let alreadyCached = await MainActor.run {
                    templateThumbnailCache[template] != nil
                }
                if alreadyCached { continue }

                let image = await Self.renderThumbnailOffMain(
                    template: template,
                    session: session,
                    base: nil,
                    includeMetrics: includeMetrics || template.pickerGroup == .stickers,
                    publishTierPerHour: publishTierPerHour || template.pickerGroup == .stickers,
                    publishWinLoss: publishWinLoss || template.pickerGroup == .stickers,
                    publishBuyInCashOut: publishBuyInCashOut || template.pickerGroup == .stickers,
                    publishCompDetails: publishCompDetails || template.pickerGroup == .stickers,
                    currencySymbol: currencySymbol,
                    footerCaption: footerCaption,
                    fontStyle: selectedTextFont,
                    textScale: globalTextScale,
                    textColorToken: selectedTextColor,
                    textBackgroundColorToken: selectedTextBackgroundColor,
                    textBackgroundOpacity: textBackgroundOpacity,
                    canvasSize: designSize
                )
                if Task.isCancelled { return }
                await MainActor.run {
                    templateThumbnailCache[template] = image
                }
            }
        }
    }

    private static func renderThumbnailOffMain(
        template: SessionArtTemplate,
        session: Session,
        base: UIImage?,
        includeMetrics: Bool,
        publishTierPerHour: Bool,
        publishWinLoss: Bool,
        publishBuyInCashOut: Bool,
        publishCompDetails: Bool,
        currencySymbol: String,
        footerCaption: String,
        fontStyle: SessionArtTextFont,
        textScale: CGFloat,
        textColorToken: SessionArtColorToken,
        textBackgroundColorToken: SessionArtColorToken,
        textBackgroundOpacity: CGFloat,
        canvasSize: CGSize
    ) async -> UIImage {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let image = template.renderThumbnail(
                    session: session,
                    base: base,
                    includeMetrics: includeMetrics,
                    publishTierPerHour: publishTierPerHour,
                    publishWinLoss: publishWinLoss,
                    publishBuyInCashOut: publishBuyInCashOut,
                    publishCompDetails: publishCompDetails,
                    currencySymbol: currencySymbol,
                    footerCaption: footerCaption,
                    fontStyle: fontStyle,
                    textScale: textScale,
                    textColorToken: textColorToken,
                    textBackgroundColorToken: textBackgroundColorToken,
                    textBackgroundOpacity: textBackgroundOpacity,
                    canvasSize: canvasSize
                )
                continuation.resume(returning: image)
            }
        }
    }

    private func refreshPreviewImage() {
        guard outputKind == .image else { return }
        let isVideoPreview = videoUnderlayURL != nil
        let shouldIncludeMetrics = includeMetrics || stickerModeActive
        let params = SessionArtRenderer.RenderParams(
            base: isVideoPreview ? nil : resolveUnderlay(),
            session: session,
            currencySymbol: currencySymbol,
            includeMetrics: shouldIncludeMetrics,
            publishTierPerHour: publishTierPerHour || stickerModeActive,
            publishWinLoss: publishWinLoss || stickerModeActive,
            publishBuyInCashOut: publishBuyInCashOut || stickerModeActive,
            publishCompDetails: publishCompDetails || stickerModeActive,
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
    @State private var selectedBaseTemplate: SessionArtTemplate = .balanced
    @State private var selectedStickerTemplate: SessionArtTemplate?
    @State private var selectedArtDecoTemplate: SessionArtTemplate?
    @State private var selectedTextFont: SessionArtTextFont = .system
    @State private var globalTextScale: CGFloat = 1.0
    @State private var selectedTextColor: SessionArtColorToken = .white
    @State private var selectedTextBackgroundColor: SessionArtColorToken = .black
    @State private var textBackgroundOpacity: CGFloat = 0.45
    @State private var hasAppliedSavedSharePreset = false

    @State private var selectedUnderlay: SessionUnderlaySource?
    @State private var customUnderlay: UIImage?
    @State private var showImagePickerSheet = false
    @State private var showVideoPickerSheet = false
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
                            if selectedShareVideoURL == nil {
                                currentUnderlayPreview
                            }
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
        .fullScreenCover(isPresented: $showImagePickerSheet, onDismiss: {
            showImagePickerSheet = false
        }) {
            SessionArtMediaPickerSheet(kind: .image) { image, _ in
                showImagePickerSheet = false
                if let image {
                    customUnderlay = image
                    chooseUnderlay(.uploaded)
                }
            }
        }
        .fullScreenCover(isPresented: $showVideoPickerSheet, onDismiss: {
            showVideoPickerSheet = false
        }) {
            SessionArtMediaPickerSheet(kind: .video) { _, pickedVideoURL in
                showVideoPickerSheet = false
                guard let pickedVideoURL else {
                    exportError = "Couldn't load the selected video."
                    return
                }
                selectedShareVideoURL = pickedVideoURL
            }
        }
        .sheet(isPresented: $showPreviewSheet) {
            if let session = resolvedSession {
                SessionArtPreviewSheet(
                    session: session,
                    resolveUnderlay: { loadUnderlayImage() },
                    includeMetrics: shouldRenderMetrics,
                    publishTierPerHour: publishTierPerHour,
                    publishWinLoss: publishWinLoss,
                    publishBuyInCashOut: publishBuyInCashOut,
                    publishCompDetails: publishCompDetails,
                    currencySymbol: settingsStore.currencySymbol,
                    designSize: designCanvas,
                    videoUnderlayURL: selectedShareVideoURL,
                    layout: $previewLayout,
                    selectedBaseTemplate: $selectedBaseTemplate,
                    selectedStickerTemplate: $selectedStickerTemplate,
                    selectedArtDecoTemplate: $selectedArtDecoTemplate,
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
        if let sel = selectedUnderlay {
            if sel == .uploaded, let c = customUnderlay {
                return "custom-\(ObjectIdentifier(c))"
            }
            return sel.id
        }
        return "none"
    }

    private var sessionArtPreviewOutputKind: SessionArtPreviewOutputKind {
        outputKind == .text ? .text : .image
    }

    private var shouldRenderMetrics: Bool {
        artStyle == .photoWithMetrics || stickerModeActive
    }

    private var stickerModeActive: Bool {
        selectedStickerTemplate != nil
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
                            selected: selectedUnderlay == .uploaded && selectedShareVideoURL == nil
                        ) {
                            chooseUnderlay(.uploaded)
                        }
                    }
                    if let s = resolvedSession,
                       let fn = s.chipEstimatorImageFilename,
                       let url = ChipEstimatorPhotoStorage.url(for: fn),
                       let chipImage = UIImage(contentsOfFile: url.path) {
                        underlayThumb(
                            title: "Chip / table",
                            image: chipImage,
                            selected: selectedUnderlay == .chipEstimator
                        ) {
                            chooseUnderlay(.chipEstimator)
                        }
                    }
                    if let s = resolvedSession {
                        ForEach(Array(s.compEvents.filter { CompPhotoStorage.url(for: $0.id) != nil }), id: \.id) { ev in
                            let compURL = CompPhotoStorage.url(for: ev.id)
                            let compImage = compURL.flatMap { UIImage(contentsOfFile: $0.path) }
                            underlayThumb(
                                title: "Comp",
                                image: compImage,
                                selected: selectedUnderlay == .compPhoto(ev.id)
                            ) {
                                chooseUnderlay(.compPhoto(ev.id))
                            }
                        }
                    }
                }
            }
            Button {
                showImagePickerSheet = false
                DispatchQueue.main.async {
                    showImagePickerSheet = true
                }
            } label: {
                Label("Upload a picture", systemImage: "photo.badge.plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue.opacity(0.75))
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)
            if customUnderlay != nil {
                Button {
                    removeUploadedUnderlay()
                } label: {
                    Label("Remove uploaded picture", systemImage: "trash")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            if selectedUnderlay != nil {
                Button {
                    clearSelectedUnderlay()
                } label: {
                    Label("Clear selected underlay", systemImage: "xmark.circle")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.gray)
            }
        }
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
            Button {
                showVideoPickerSheet = false
                DispatchQueue.main.async {
                    showVideoPickerSheet = true
                }
            } label: {
                Label(selectedShareVideoURL == nil ? "Use a video instead of image" : "Replace selected video", systemImage: "video.badge.plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.purple.opacity(0.75))
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)
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
            Text(previewButtonTitle)
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

    private var previewButtonTitle: String {
        if outputKind == .text {
            return "Preview & edit text (Text)"
        }
        let mediaType = selectedShareVideoURL == nil ? "Image" : "Video"
        return "Preview & adjust (\(mediaType))"
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
        if let baseRaw = preset.selectedBaseTemplateRaw,
           let baseTemplate = SessionArtTemplate(rawValue: baseRaw),
           baseTemplate.pickerGroup == .templates {
            selectedBaseTemplate = baseTemplate
        } else if let legacy = SessionArtTemplate(rawValue: preset.selectedTemplateRaw) {
            switch legacy.pickerGroup {
            case .templates:
                selectedBaseTemplate = legacy
            case .stickers:
                selectedStickerTemplate = legacy
            case .artDeco:
                selectedArtDecoTemplate = legacy
            }
        }
        if let stickerRaw = preset.selectedStickerTemplateRaw,
           let stickerTemplate = SessionArtTemplate(rawValue: stickerRaw),
           stickerTemplate.pickerGroup == .stickers {
            selectedStickerTemplate = stickerTemplate
        }
        if let decoRaw = preset.selectedArtDecoTemplateRaw,
           let decoTemplate = SessionArtTemplate(rawValue: decoRaw),
           decoTemplate.pickerGroup == .artDeco {
            selectedArtDecoTemplate = decoTemplate
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
            selectedTemplateRaw: selectedBaseTemplate.rawValue,
            selectedBaseTemplateRaw: selectedBaseTemplate.rawValue,
            selectedStickerTemplateRaw: selectedStickerTemplate?.rawValue,
            selectedArtDecoTemplateRaw: selectedArtDecoTemplate?.rawValue,
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
            previewLayout = composedLayout(for: s, canvasSize: designCanvas)
        }
        showPreviewSheet = true
    }

    private func chooseUnderlay(_ source: SessionUnderlaySource) {
        showImagePickerSheet = false
        showVideoPickerSheet = false
        selectedShareVideoURL = nil
        selectedUnderlay = source
    }

    private func clearSelectedUnderlay() {
        showImagePickerSheet = false
        showVideoPickerSheet = false
        selectedUnderlay = nil
        selectedShareVideoURL = nil
    }

    private func removeUploadedUnderlay() {
        showImagePickerSheet = false
        showVideoPickerSheet = false
        customUnderlay = nil
        if selectedUnderlay == .uploaded {
            selectedUnderlay = nil
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
        guard let s = resolvedSession else { return nil }
        guard let sel = selectedUnderlay else { return nil }
        switch sel {
        case .uploaded:
            return customUnderlay
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
            includeMetrics: shouldRenderMetrics,
            publishTierPerHour: publishTierPerHour || stickerModeActive,
            publishWinLoss: publishWinLoss || stickerModeActive,
            publishBuyInCashOut: publishBuyInCashOut || stickerModeActive,
            publishCompDetails: publishCompDetails || stickerModeActive,
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

    private func composedLayout(for session: Session, canvasSize: CGSize) -> SessionArtLayout {
        var composed = selectedBaseTemplate.makeLayout(
            session: session,
            publishTierPerHour: publishTierPerHour || stickerModeActive,
            publishWinLoss: publishWinLoss || stickerModeActive,
            publishBuyInCashOut: publishBuyInCashOut || stickerModeActive,
            publishCompDetails: publishCompDetails || stickerModeActive,
            canvasSize: canvasSize
        )

        if let stickerTemplate = selectedStickerTemplate {
            let stickerLayout = stickerTemplate.makeLayout(
                session: session,
                publishTierPerHour: true,
                publishWinLoss: true,
                publishBuyInCashOut: true,
                publishCompDetails: true,
                canvasSize: canvasSize
            )
            composed.stickerOverlayStyle = stickerLayout.stickerOverlayStyle
            if stickerLayout.borderStyle != .none {
                composed.borderStyle = stickerLayout.borderStyle
            }
        } else {
            composed.stickerOverlayStyle = .none
        }

        if let decoTemplate = selectedArtDecoTemplate {
            let decoLayout = decoTemplate.makeLayout(
                session: session,
                publishTierPerHour: publishTierPerHour || stickerModeActive,
                publishWinLoss: publishWinLoss || stickerModeActive,
                publishBuyInCashOut: publishBuyInCashOut || stickerModeActive,
                publishCompDetails: publishCompDetails || stickerModeActive,
                canvasSize: canvasSize
            )
            if decoLayout.borderStyle != .none {
                composed.borderStyle = decoLayout.borderStyle
            }
            composed.secondaryOverlayStyle = decoLayout.stickerOverlayStyle
        } else {
            composed.secondaryOverlayStyle = .none
        }

        return composed
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
        let animateStickerMetrics = stickerModeActive && shouldRenderMetrics
        var staticOverlayCI: CIImage?
        if !animateStickerMetrics {
            let overlayImage = SessionArtRenderer.renderOverlayImage(params: overlayParams)
            guard let overlayCG = overlayImage.cgImage else {
                isExportingImage = false
                exportError = "Could not build overlay image for video export."
                return
            }
            staticOverlayCI = CIImage(cgImage: overlayCG)
        }
        let overlayExtent = CGRect(origin: .zero, size: renderSize)
        let orientationTransform = preferredTransform.concatenating(
            CGAffineTransform(translationX: -transformedRect.minX, y: -transformedRect.minY)
        )
        let durationSeconds = max(duration.seconds, 0.001)

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

            let overlayCI: CIImage
            if animateStickerMetrics {
                let t = min(1, max(0, request.compositionTime.seconds / durationSeconds))
                var frameParams = overlayParams
                frameParams.counterGlobalT = CGFloat(t)
                let frameOverlay = SessionArtRenderer.renderOverlayImage(params: frameParams)
                if let cg = frameOverlay.cgImage {
                    overlayCI = CIImage(cgImage: cg)
                } else {
                    overlayCI = CIImage(color: .clear).cropped(to: overlayExtent)
                }
            } else {
                overlayCI = staticOverlayCI ?? CIImage(color: .clear).cropped(to: overlayExtent)
            }

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
