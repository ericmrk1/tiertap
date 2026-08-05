import SwiftUI
import UIKit
import Photos
import AVFoundation

#if os(iOS)

// MARK: - Privacy presets (WP-S4)

enum SessionArtPrivacyPreset: String, CaseIterable, Identifiable {
    case fullStats
    case noMoney
    case vibeOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullStats: return "Full stats"
        case .noMoney: return "No money"
        case .vibeOnly: return "Vibe only"
        }
    }

    var subtitle: String {
        switch self {
        case .fullStats: return "Tier, buy-in, cash-out, W/L, comps"
        case .noMoney: return "Hide buy-in, cash-out, and W/L"
        case .vibeOnly: return "Photo + casino vibe — minimal metrics"
        }
    }

    var publishTierPerHour: Bool {
        switch self {
        case .fullStats, .noMoney: return true
        case .vibeOnly: return false
        }
    }

    var publishWinLoss: Bool {
        self == .fullStats
    }

    var publishBuyInCashOut: Bool {
        self == .fullStats
    }

    var publishCompDetails: Bool {
        self == .fullStats
    }

    var includeMetrics: Bool {
        self != .vibeOnly
    }
}

// MARK: - Aspect ratios (WP-E6)

enum SessionArtAspectRatio: String, CaseIterable, Identifiable {
    case story
    case feed
    case square

    var id: String { rawValue }

    var title: String {
        switch self {
        case .story: return "Story 9:16"
        case .feed: return "Feed 4:5"
        case .square: return "Square 1:1"
        }
    }

    /// Design / export canvas size in points (scale 1).
    var canvasSize: CGSize {
        switch self {
        case .story: return CGSize(width: 2160, height: 3840)
        case .feed: return CGSize(width: 2160, height: 2700)
        case .square: return CGSize(width: 2160, height: 2160)
        }
    }

    var aspect: CGFloat {
        let s = canvasSize
        return s.width / max(1, s.height)
    }
}

// MARK: - Auto underlay (WP-S3)

enum SessionArtUnderlayPicker {
    /// Prefer primary/attached session photos → chip → first receipt → nil (caller may use gradient).
    static func preferredSource(for session: Session) -> SessionUnderlaySource? {
        if let primaryKey = session.primarySessionPhotoRefKey,
           let ref = SessionPhotoRef.parse(storageKey: primaryKey) {
            switch ref.kind {
            case .attached:
                if let uuid = UUID(uuidString: ref.objectID),
                   SessionAttachedPhotoStorage.url(for: uuid) != nil {
                    return .attachedPhoto(uuid)
                }
            case .chipTable:
                if session.chipEstimatorImageFilename != nil {
                    return .chipEstimator
                }
            case .comp:
                if let uuid = UUID(uuidString: ref.objectID),
                   CompPhotoStorage.url(for: uuid) != nil {
                    return .compPhoto(uuid)
                }
            }
        }
        if let firstAttached = session.sessionAttachedPhotoIDs.first(where: {
            SessionAttachedPhotoStorage.url(for: $0) != nil
        }) {
            return .attachedPhoto(firstAttached)
        }
        if let fn = session.chipEstimatorImageFilename,
           ChipEstimatorPhotoStorage.url(for: fn) != nil {
            return .chipEstimator
        }
        if let comp = session.compEvents.first(where: { CompPhotoStorage.url(for: $0.id) != nil }) {
            return .compPhoto(comp.id)
        }
        return nil
    }

    static func loadImage(session: Session, source: SessionUnderlaySource?, uploaded: UIImage? = nil) -> UIImage? {
        guard let source else { return brandGradientFallback() }
        switch source {
        case .uploaded:
            return uploaded ?? brandGradientFallback()
        case .chipEstimator:
            guard let fn = session.chipEstimatorImageFilename,
                  let url = ChipEstimatorPhotoStorage.url(for: fn) else {
                return brandGradientFallback()
            }
            return UIImage(contentsOfFile: url.path) ?? brandGradientFallback()
        case .compPhoto(let id):
            guard let url = CompPhotoStorage.url(for: id) else { return brandGradientFallback() }
            return UIImage(contentsOfFile: url.path) ?? brandGradientFallback()
        case .attachedPhoto(let id):
            guard let url = SessionAttachedPhotoStorage.url(for: id) else { return brandGradientFallback() }
            return UIImage(contentsOfFile: url.path) ?? brandGradientFallback()
        }
    }

    static func brandGradientFallback(size: CGSize = CGSize(width: 1080, height: 1920)) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            let colors = [
                UIColor(red: 0.05, green: 0.12, blue: 0.10, alpha: 1).cgColor,
                UIColor(red: 0.02, green: 0.35, blue: 0.22, alpha: 1).cgColor,
                UIColor(red: 0.00, green: 0.08, blue: 0.06, alpha: 1).cgColor
            ]
            let space = CGColorSpaceCreateDeviceRGB()
            if let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: [0, 0.55, 1]) {
                ctx.cgContext.drawLinearGradient(
                    gradient,
                    start: .zero,
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )
            } else {
                UIColor.black.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
            }
        }
    }
}

// MARK: - Preset + privacy helpers

enum SessionArtSharePresetStore {
    static func load() -> SessionArtSharePreset? {
        guard let data = UserDefaults.standard.data(forKey: keySessionArtSharePreset) else { return nil }
        return try? JSONDecoder().decode(SessionArtSharePreset.self, from: data)
    }

    static var lastPrivacyPreset: SessionArtPrivacyPreset {
        get {
            let raw = UserDefaults.standard.string(forKey: "ctt_session_art_privacy_preset_v1") ?? ""
            return SessionArtPrivacyPreset(rawValue: raw) ?? .noMoney
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "ctt_session_art_privacy_preset_v1")
        }
    }

    static var lastAspectRatio: SessionArtAspectRatio {
        get {
            let raw = UserDefaults.standard.string(forKey: "ctt_session_art_aspect_v1") ?? ""
            return SessionArtAspectRatio(rawValue: raw) ?? .story
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "ctt_session_art_aspect_v1")
        }
    }

    static var lastLevelSharePresetRaw: String? {
        get { UserDefaults.standard.string(forKey: "ctt_tap_level_share_preset_v1") }
        set { UserDefaults.standard.set(newValue, forKey: "ctt_tap_level_share_preset_v1") }
    }
}

// MARK: - Quick Share render (WP-S1)

enum SessionArtQuickShareRenderer {
    static func render(
        session: Session,
        currencySymbol: String,
        privacy: SessionArtPrivacyPreset,
        aspect: SessionArtAspectRatio = SessionArtSharePresetStore.lastAspectRatio,
        uploadedUnderlay: UIImage? = nil
    ) -> UIImage {
        let preset = SessionArtSharePresetStore.load()
        let templateRaw = preset?.selectedBaseTemplateRaw ?? SessionArtTemplate.balanced.rawValue
        let template = SessionArtTemplate(rawValue: templateRaw) ?? .balanced
        let sticker = preset?.selectedStickerTemplateRaw.flatMap(SessionArtTemplate.init(rawValue:))
        let deco = preset?.selectedArtDecoTemplateRaw.flatMap(SessionArtTemplate.init(rawValue:))
        let font = SessionArtTextFont(rawValue: preset?.selectedTextFontRaw ?? "") ?? .system
        let textColor = SessionArtColorToken(rawValue: preset?.selectedTextColorRaw ?? "") ?? .white
        let bgColor = SessionArtColorToken(rawValue: preset?.selectedTextBackgroundColorRaw ?? "") ?? .black
        let textScale = CGFloat(preset?.globalTextScale ?? 1)
        let bgOpacity = CGFloat(preset?.textBackgroundOpacity ?? 0.45)

        let canvas = aspect.canvasSize
        var layout = template.makeLayout(
            session: session,
            publishTierPerHour: privacy.publishTierPerHour,
            publishWinLoss: privacy.publishWinLoss,
            publishBuyInCashOut: privacy.publishBuyInCashOut,
            publishCompDetails: privacy.publishCompDetails,
            canvasSize: canvas
        )
        if let sticker {
            let stickerLayout = sticker.makeLayout(
                session: session,
                publishTierPerHour: true,
                publishWinLoss: true,
                publishBuyInCashOut: true,
                publishCompDetails: true,
                canvasSize: canvas
            )
            layout.stickerOverlayStyle = stickerLayout.stickerOverlayStyle
            if stickerLayout.borderStyle != .none {
                layout.borderStyle = stickerLayout.borderStyle
            }
        }
        if let deco {
            let decoLayout = deco.makeLayout(
                session: session,
                publishTierPerHour: privacy.publishTierPerHour,
                publishWinLoss: privacy.publishWinLoss,
                publishBuyInCashOut: privacy.publishBuyInCashOut,
                publishCompDetails: privacy.publishCompDetails,
                canvasSize: canvas
            )
            if decoLayout.borderStyle != .none {
                layout.borderStyle = decoLayout.borderStyle
            }
            layout.secondaryOverlayStyle = decoLayout.stickerOverlayStyle
        }

        let source = SessionArtUnderlayPicker.preferredSource(for: session)
        let base = SessionArtUnderlayPicker.loadImage(session: session, source: source, uploaded: uploadedUnderlay)

        let params = SessionArtRenderer.RenderParams(
            base: base,
            session: session,
            currencySymbol: currencySymbol,
            includeMetrics: privacy.includeMetrics || sticker != nil,
            publishTierPerHour: privacy.publishTierPerHour || sticker != nil,
            publishWinLoss: privacy.publishWinLoss || sticker != nil,
            publishBuyInCashOut: privacy.publishBuyInCashOut || sticker != nil,
            publishCompDetails: privacy.publishCompDetails || sticker != nil,
            metricsReach: 1,
            counterGlobalT: nil,
            fontStyle: font,
            textScale: textScale,
            textColorToken: textColor,
            textBackgroundColorToken: bgColor,
            textBackgroundOpacity: bgOpacity,
            canvasSize: canvas,
            layout: layout,
            footerCaption: ""
        )
        return SessionArtRenderer.renderImage(params: params)
    }

    /// Transparent sticker/metric overlay only (WP-X3).
    static func renderTransparentOverlay(
        session: Session,
        currencySymbol: String,
        privacy: SessionArtPrivacyPreset,
        layout: SessionArtLayout,
        aspect: SessionArtAspectRatio,
        font: SessionArtTextFont = .system,
        textScale: CGFloat = 1,
        textColor: SessionArtColorToken = .white,
        bgColor: SessionArtColorToken = .black,
        bgOpacity: CGFloat = 0.45,
        footerCaption: String = "",
        customHeadline: String = ""
    ) -> UIImage {
        let params = SessionArtRenderer.RenderParams(
            base: nil,
            session: session,
            currencySymbol: currencySymbol,
            includeMetrics: privacy.includeMetrics,
            publishTierPerHour: privacy.publishTierPerHour,
            publishWinLoss: privacy.publishWinLoss,
            publishBuyInCashOut: privacy.publishBuyInCashOut,
            publishCompDetails: privacy.publishCompDetails,
            metricsReach: 1,
            counterGlobalT: nil,
            fontStyle: font,
            textScale: textScale,
            textColorToken: textColor,
            textBackgroundColorToken: bgColor,
            textBackgroundOpacity: bgOpacity,
            canvasSize: aspect.canvasSize,
            layout: layout,
            footerCaption: footerCaption,
            customHeadline: customHeadline
        )
        return SessionArtRenderer.renderOverlayImage(params: params)
    }
}

// MARK: - Instagram Stories (WP-X2)

enum InstagramStoriesSharer {
    private static let storiesURL = URL(string: "instagram-stories://share")!

    static var isAvailable: Bool {
        UIApplication.shared.canOpenURL(storiesURL)
    }

    static func shareImage(_ image: UIImage, completion: ((Bool) -> Void)? = nil) {
        guard let data = image.pngData() else {
            completion?(false)
            return
        }
        sharePasteboardItems([
            "com.instagram.sharedSticker.backgroundImage": data
        ], completion: completion)
    }

    static func shareVideo(fileURL: URL, completion: ((Bool) -> Void)? = nil) {
        guard let data = try? Data(contentsOf: fileURL) else {
            completion?(false)
            return
        }
        sharePasteboardItems([
            "com.instagram.sharedSticker.backgroundVideo": data
        ], completion: completion)
    }

    private static func sharePasteboardItems(_ items: [String: Any], completion: ((Bool) -> Void)?) {
        guard isAvailable else {
            completion?(false)
            return
        }
        let pasteboardItems = [items]
        let options: [UIPasteboard.OptionsKey: Any] = [
            .expirationDate: Date().addingTimeInterval(60 * 5)
        ]
        UIPasteboard.general.setItems(pasteboardItems, options: options)
        UIApplication.shared.open(storiesURL, options: [:], completionHandler: completion)
    }
}

// MARK: - Animated story export (WP-X4)

enum SessionArtAnimatedStoryExporter {
    /// Renders a short 9:16 (or aspect) MP4 with count-up metrics over a still underlay.
    static func export(
        session: Session,
        currencySymbol: String,
        privacy: SessionArtPrivacyPreset,
        layout: SessionArtLayout,
        underlay: UIImage?,
        aspect: SessionArtAspectRatio,
        font: SessionArtTextFont,
        textScale: CGFloat,
        textColor: SessionArtColorToken,
        bgColor: SessionArtColorToken,
        bgOpacity: CGFloat,
        footerCaption: String,
        duration: TimeInterval = 3.2,
        fps: Int = 24,
        customHeadline: String = "",
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let canvas = aspect.canvasSize
                let frameCount = max(1, Int(duration * Double(fps)))
                let outputURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("tiertap-animated-story-\(UUID().uuidString).mp4")
                if FileManager.default.fileExists(atPath: outputURL.path) {
                    try FileManager.default.removeItem(at: outputURL)
                }

                let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
                let settings: [String: Any] = [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: Int(canvas.width),
                    AVVideoHeightKey: Int(canvas.height)
                ]
                let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
                input.expectsMediaDataInRealTime = false
                let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                    assetWriterInput: input,
                    sourcePixelBufferAttributes: [
                        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
                        kCVPixelBufferWidthKey as String: Int(canvas.width),
                        kCVPixelBufferHeightKey as String: Int(canvas.height)
                    ]
                )
                guard writer.canAdd(input) else {
                    throw NSError(domain: "SessionArtAnimatedStory", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot add video input"])
                }
                writer.add(input)
                guard writer.startWriting() else {
                    throw writer.error ?? NSError(domain: "SessionArtAnimatedStory", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to start writing"])
                }
                writer.startSession(atSourceTime: .zero)

                let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
                for i in 0..<frameCount {
                    let t = CGFloat(i) / CGFloat(max(1, frameCount - 1))
                    let params = SessionArtRenderer.RenderParams(
                        base: underlay,
                        session: session,
                        currencySymbol: currencySymbol,
                        includeMetrics: privacy.includeMetrics,
                        publishTierPerHour: privacy.publishTierPerHour,
                        publishWinLoss: privacy.publishWinLoss,
                        publishBuyInCashOut: privacy.publishBuyInCashOut,
                        publishCompDetails: privacy.publishCompDetails,
                        metricsReach: 1,
                        counterGlobalT: t,
                        fontStyle: font,
                        textScale: textScale,
                        textColorToken: textColor,
                        textBackgroundColorToken: bgColor,
                        textBackgroundOpacity: bgOpacity,
                        canvasSize: canvas,
                        layout: layout,
                        footerCaption: footerCaption,
                        customHeadline: customHeadline
                    )
                    let image = SessionArtRenderer.renderImage(params: params)
                    while !input.isReadyForMoreMediaData {
                        Thread.sleep(forTimeInterval: 0.01)
                    }
                    guard let buffer = pixelBuffer(from: image, size: canvas) else { continue }
                    let time = CMTimeMultiply(frameDuration, multiplier: Int32(i))
                    adaptor.append(buffer, withPresentationTime: time)
                }

                input.markAsFinished()
                writer.finishWriting {
                    if writer.status == .completed {
                        completion(.success(outputURL))
                    } else {
                        completion(.failure(writer.error ?? NSError(domain: "SessionArtAnimatedStory", code: 3, userInfo: [NSLocalizedDescriptionKey: "Export failed"])))
                    }
                }
            } catch {
                completion(.failure(error))
            }
        }
    }

    private static func pixelBuffer(from image: UIImage, size: CGSize) -> CVPixelBuffer? {
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue!,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue!
        ] as CFDictionary
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32ARGB,
            attrs,
            &buffer
        )
        guard status == kCVReturnSuccess, let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ), let cgImage = image.cgImage else { return nil }
        context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        return buffer
    }
}

// MARK: - Layout composer + shuffle (WP-E7 / E8)

enum SessionArtLayoutComposer {
    static func compose(
        session: Session,
        base: SessionArtTemplate,
        sticker: SessionArtTemplate?,
        artDeco: SessionArtTemplate?,
        privacy: SessionArtPrivacyPreset,
        canvasSize: CGSize,
        preserving from: SessionArtLayout? = nil
    ) -> SessionArtLayout {
        let stickerMode = sticker != nil
        var composed = base.makeLayout(
            session: session,
            publishTierPerHour: privacy.publishTierPerHour || stickerMode,
            publishWinLoss: privacy.publishWinLoss || stickerMode,
            publishBuyInCashOut: privacy.publishBuyInCashOut || stickerMode,
            publishCompDetails: privacy.publishCompDetails || stickerMode,
            canvasSize: canvasSize
        )
        if let sticker {
            let stickerLayout = sticker.makeLayout(
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
        }
        if let artDeco {
            let decoLayout = artDeco.makeLayout(
                session: session,
                publishTierPerHour: privacy.publishTierPerHour || stickerMode,
                publishWinLoss: privacy.publishWinLoss || stickerMode,
                publishBuyInCashOut: privacy.publishBuyInCashOut || stickerMode,
                publishCompDetails: privacy.publishCompDetails || stickerMode,
                canvasSize: canvasSize
            )
            if decoLayout.borderStyle != .none {
                composed.borderStyle = decoLayout.borderStyle
            }
            composed.secondaryOverlayStyle = decoLayout.stickerOverlayStyle
        }
        if let from {
            composed.underlayZoom = from.underlayZoom
            composed.underlayPan = from.underlayPan
            composed.hiddenLines = from.hiddenLines
            composed.lockedLines = from.lockedLines
            composed.headerHidden = from.headerHidden
            composed.headerLocked = from.headerLocked
            composed.footerHidden = from.footerHidden
            composed.footerLocked = from.footerLocked
        }
        return composed
    }
}

enum SessionArtStyleRandomizer {
    struct Result {
        var baseTemplate: SessionArtTemplate
        var stickerTemplate: SessionArtTemplate?
        var artDecoTemplate: SessionArtTemplate?
        var font: SessionArtTextFont
        var textColor: SessionArtColorToken
        var bgColor: SessionArtColorToken
        var textScale: CGFloat
        var bgOpacity: CGFloat
    }

    static func pick() -> Result {
        let bases = SessionArtTemplate.allCases.filter { $0.pickerGroup == .templates }
        let stickers = SessionArtTemplate.allCases.filter { $0.pickerGroup == .stickers }
        let decos = SessionArtTemplate.allCases.filter { $0.pickerGroup == .artDeco }
        let includeSticker = Bool.random() && !stickers.isEmpty
        let includeDeco = Bool.random() && !decos.isEmpty
        return Result(
            baseTemplate: bases.randomElement() ?? .balanced,
            stickerTemplate: includeSticker ? stickers.randomElement() : nil,
            artDecoTemplate: includeDeco ? decos.randomElement() : nil,
            font: SessionArtTextFont.allCases.randomElement() ?? .system,
            textColor: [SessionArtColorToken.white, .mint, .yellow, .orange].randomElement() ?? .white,
            bgColor: [SessionArtColorToken.black, .blue, .purple, .red].randomElement() ?? .black,
            textScale: CGFloat([0.9, 1.0, 1.1, 1.25, 1.4].randomElement() ?? 1),
            bgOpacity: CGFloat([0.35, 0.45, 0.55, 0.65].randomElement() ?? 0.45)
        )
    }
}

// MARK: - Named compositions / My styles (WP-E7)

struct SessionArtNamedComposition: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var createdAt: Date
    var aspectRaw: String
    var privacyRaw: String
    var baseTemplateRaw: String
    var stickerTemplateRaw: String?
    var artDecoTemplateRaw: String?
    var fontRaw: String
    var textScale: Double
    var textColorRaw: String
    var bgColorRaw: String
    var bgOpacity: Double
    var footerCaption: String
    var customHeadline: String
    var layout: SessionArtLayoutSnapshot

    struct SessionArtLayoutSnapshot: Codable, Equatable {
        var headerOrigin: SessionArtCodableXY
        var footerCenter: SessionArtCodableXY
        var lineOrigins: [String: SessionArtCodableXY]
        var headerScale: Double
        var metricsScale: Double
        var footerScale: Double
        var brandingScale: Double
        var brandingOffset: SessionArtCodableXY
        var underlayZoom: Double
        var underlayPan: SessionArtCodableXY
        var showBranding: Bool
        var headerFocusRaw: String
        var emphasizedMetricRaw: String?
        var emphasisScale: Double
        var borderStyleRaw: String
        var stickerOverlayStyleRaw: String
        var secondaryOverlayStyleRaw: String
        var lineScales: [String: Double]
        var lineRotations: [String: Double]
        var hiddenLines: [String: Bool]
        var lockedLines: [String: Bool]
        var headerHidden: Bool
        var headerLocked: Bool
        var footerHidden: Bool
        var footerLocked: Bool
    }

    struct SessionArtCodableXY: Codable, Equatable {
        var x: Double
        var y: Double
        init(_ p: CGPoint) { x = Double(p.x); y = Double(p.y) }
        var point: CGPoint { CGPoint(x: x, y: y) }
    }

    static func capture(
        name: String,
        layout: SessionArtLayout,
        aspect: SessionArtAspectRatio,
        privacy: SessionArtPrivacyPreset,
        base: SessionArtTemplate,
        sticker: SessionArtTemplate?,
        artDeco: SessionArtTemplate?,
        font: SessionArtTextFont,
        textScale: CGFloat,
        textColor: SessionArtColorToken,
        bgColor: SessionArtColorToken,
        bgOpacity: CGFloat,
        footerCaption: String,
        customHeadline: String
    ) -> SessionArtNamedComposition {
        SessionArtNamedComposition(
            id: UUID(),
            name: name,
            createdAt: Date(),
            aspectRaw: aspect.rawValue,
            privacyRaw: privacy.rawValue,
            baseTemplateRaw: base.rawValue,
            stickerTemplateRaw: sticker?.rawValue,
            artDecoTemplateRaw: artDeco?.rawValue,
            fontRaw: font.rawValue,
            textScale: Double(textScale),
            textColorRaw: textColor.rawValue,
            bgColorRaw: bgColor.rawValue,
            bgOpacity: Double(bgOpacity),
            footerCaption: footerCaption,
            customHeadline: customHeadline,
            layout: .init(
                headerOrigin: .init(layout.headerOrigin),
                footerCenter: .init(layout.footerCenter),
                lineOrigins: layout.lineOrigins.reduce(into: [:]) { $0[$1.key.rawValue] = .init($1.value) },
                headerScale: Double(layout.headerScale),
                metricsScale: Double(layout.metricsScale),
                footerScale: Double(layout.footerScale),
                brandingScale: Double(layout.brandingScale),
                brandingOffset: .init(layout.brandingOffset),
                underlayZoom: Double(layout.underlayZoom),
                underlayPan: .init(layout.underlayPan),
                showBranding: layout.showBranding,
                headerFocusRaw: layout.headerFocus.rawValue,
                emphasizedMetricRaw: layout.emphasizedMetric?.rawValue,
                emphasisScale: Double(layout.emphasisScale),
                borderStyleRaw: layout.borderStyle.rawValue,
                stickerOverlayStyleRaw: layout.stickerOverlayStyle.rawValue,
                secondaryOverlayStyleRaw: layout.secondaryOverlayStyle.rawValue,
                lineScales: layout.lineScales.reduce(into: [:]) { $0[$1.key.rawValue] = Double($1.value) },
                lineRotations: layout.lineRotations.reduce(into: [:]) { $0[$1.key.rawValue] = Double($1.value) },
                hiddenLines: layout.hiddenLines.reduce(into: [:]) { $0[$1.key.rawValue] = $1.value },
                lockedLines: layout.lockedLines.reduce(into: [:]) { $0[$1.key.rawValue] = $1.value },
                headerHidden: layout.headerHidden,
                headerLocked: layout.headerLocked,
                footerHidden: layout.footerHidden,
                footerLocked: layout.footerLocked
            )
        )
    }

    func makeLayout() -> SessionArtLayout {
        let snap = layout
        var lines: [MetricLineKey: CGPoint] = [:]
        for (k, v) in snap.lineOrigins {
            if let key = MetricLineKey(rawValue: k) { lines[key] = v.point }
        }
        var scales: [MetricLineKey: CGFloat] = [:]
        for (k, v) in snap.lineScales {
            if let key = MetricLineKey(rawValue: k) { scales[key] = CGFloat(v) }
        }
        var rotations: [MetricLineKey: CGFloat] = [:]
        for (k, v) in snap.lineRotations {
            if let key = MetricLineKey(rawValue: k) { rotations[key] = CGFloat(v) }
        }
        var hidden: [MetricLineKey: Bool] = [:]
        for (k, v) in snap.hiddenLines {
            if let key = MetricLineKey(rawValue: k) { hidden[key] = v }
        }
        var locked: [MetricLineKey: Bool] = [:]
        for (k, v) in snap.lockedLines {
            if let key = MetricLineKey(rawValue: k) { locked[key] = v }
        }
        return SessionArtLayout(
            headerOrigin: snap.headerOrigin.point,
            lineOrigins: lines,
            footerCenter: snap.footerCenter.point,
            headerScale: CGFloat(snap.headerScale),
            metricsScale: CGFloat(snap.metricsScale),
            footerScale: CGFloat(snap.footerScale),
            brandingScale: CGFloat(snap.brandingScale),
            brandingOffset: snap.brandingOffset.point,
            underlayZoom: CGFloat(snap.underlayZoom),
            underlayPan: snap.underlayPan.point,
            showBranding: snap.showBranding,
            headerFocus: SessionArtHeaderFocus(rawValue: snap.headerFocusRaw) ?? .casino,
            emphasizedMetric: snap.emphasizedMetricRaw.flatMap(MetricLineKey.init(rawValue:)),
            emphasisScale: CGFloat(snap.emphasisScale),
            borderStyle: SessionArtBorderStyle(rawValue: snap.borderStyleRaw) ?? .none,
            stickerOverlayStyle: SessionArtStickerOverlayStyle(rawValue: snap.stickerOverlayStyleRaw) ?? .none,
            secondaryOverlayStyle: SessionArtStickerOverlayStyle(rawValue: snap.secondaryOverlayStyleRaw) ?? .none,
            lineScales: scales,
            lineRotations: rotations,
            hiddenLines: hidden,
            lockedLines: locked,
            headerHidden: snap.headerHidden,
            headerLocked: snap.headerLocked,
            footerHidden: snap.footerHidden,
            footerLocked: snap.footerLocked
        )
    }
}

enum SessionArtCompositionStore {
    private static let key = "ctt_session_art_my_styles_v1"

    static func loadAll() -> [SessionArtNamedComposition] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let items = try? JSONDecoder().decode([SessionArtNamedComposition].self, from: data) else {
            return []
        }
        return items.sorted { $0.createdAt > $1.createdAt }
    }

    static func save(_ composition: SessionArtNamedComposition) {
        var all = loadAll()
        if let idx = all.firstIndex(where: { $0.id == composition.id }) {
            all[idx] = composition
        } else {
            all.insert(composition, at: 0)
        }
        persist(all)
    }

    static func delete(id: UUID) {
        persist(loadAll().filter { $0.id != id })
    }

    private static func persist(_ items: [SessionArtNamedComposition]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

enum SessionArtMultiFormatExporter {
    /// Renders Story (9:16) + Feed (4:5) images for a single share sheet (WP-X5).
    static func renderStoryAndFeed(
        session: Session,
        currencySymbol: String,
        privacy: SessionArtPrivacyPreset,
        layout: SessionArtLayout,
        underlay: UIImage?,
        sourceAspect: SessionArtAspectRatio,
        font: SessionArtTextFont,
        textScale: CGFloat,
        textColor: SessionArtColorToken,
        bgColor: SessionArtColorToken,
        bgOpacity: CGFloat,
        footerCaption: String,
        customHeadline: String
    ) -> [UIImage] {
        let targets: [SessionArtAspectRatio] = [.story, .feed]
        return targets.map { target in
            let scaled = layout.scaledForCanvas(from: sourceAspect.canvasSize, to: target.canvasSize)
            let params = SessionArtRenderer.RenderParams(
                base: underlay,
                session: session,
                currencySymbol: currencySymbol,
                includeMetrics: privacy.includeMetrics,
                publishTierPerHour: privacy.publishTierPerHour,
                publishWinLoss: privacy.publishWinLoss,
                publishBuyInCashOut: privacy.publishBuyInCashOut,
                publishCompDetails: privacy.publishCompDetails,
                metricsReach: 1,
                counterGlobalT: nil,
                fontStyle: font,
                textScale: textScale,
                textColorToken: textColor,
                textBackgroundColorToken: bgColor,
                textBackgroundOpacity: bgOpacity,
                canvasSize: target.canvasSize,
                layout: scaled,
                footerCaption: footerCaption,
                customHeadline: customHeadline
            )
            return SessionArtRenderer.renderImage(params: params)
        }
    }
}

enum SessionArtPhotoLibrarySaver {
    static func saveImage(_ image: UIImage, completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }) { ok, _ in
                DispatchQueue.main.async { completion(ok) }
            }
        }
    }

    static func saveVideo(fileURL: URL, completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
            }) { ok, _ in
                DispatchQueue.main.async { completion(ok) }
            }
        }
    }
}

#endif
