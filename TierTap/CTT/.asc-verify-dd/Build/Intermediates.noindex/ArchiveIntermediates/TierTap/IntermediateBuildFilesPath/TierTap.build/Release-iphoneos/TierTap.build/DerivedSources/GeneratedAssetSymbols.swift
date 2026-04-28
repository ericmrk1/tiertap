import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif
#if canImport(DeveloperToolsSupport)
import DeveloperToolsSupport
#endif

#if SWIFT_PACKAGE
private let resourceBundle = Foundation.Bundle.module
#else
private class ResourceBundleClass {}
private let resourceBundle = Foundation.Bundle(for: ResourceBundleClass.self)
#endif

// MARK: - Color Symbols -

@available(iOS 11.0, macOS 10.13, tvOS 11.0, *)
extension ColorResource {

    /// The "AccentColor" asset catalog color resource.
    static let accent = ColorResource(name: "AccentColor", bundle: resourceBundle)

}

// MARK: - Image Symbols -

@available(iOS 11.0, macOS 10.7, tvOS 11.0, *)
extension ImageResource {

    /// The "LogoSplash" asset catalog image resource.
    static let logoSplash = ImageResource(name: "LogoSplash", bundle: resourceBundle)

    /// The "SessionArtDecoCoin" asset catalog image resource.
    static let sessionArtDecoCoin = ImageResource(name: "SessionArtDecoCoin", bundle: resourceBundle)

    /// The "SessionArtDecoCrown" asset catalog image resource.
    static let sessionArtDecoCrown = ImageResource(name: "SessionArtDecoCrown", bundle: resourceBundle)

    /// The "SessionArtDecoDiamond" asset catalog image resource.
    static let sessionArtDecoDiamond = ImageResource(name: "SessionArtDecoDiamond", bundle: resourceBundle)

    /// The "SessionArtDecoDice" asset catalog image resource.
    static let sessionArtDecoDice = ImageResource(name: "SessionArtDecoDice", bundle: resourceBundle)

    /// The "SessionArtDecoGem" asset catalog image resource.
    static let sessionArtDecoGem = ImageResource(name: "SessionArtDecoGem", bundle: resourceBundle)

    /// The "SessionArtDecoHeart" asset catalog image resource.
    static let sessionArtDecoHeart = ImageResource(name: "SessionArtDecoHeart", bundle: resourceBundle)

    /// The "SessionArtDecoJoker" asset catalog image resource.
    static let sessionArtDecoJoker = ImageResource(name: "SessionArtDecoJoker", bundle: resourceBundle)

    /// The "SessionArtDecoMoneyBag" asset catalog image resource.
    static let sessionArtDecoMoneyBag = ImageResource(name: "SessionArtDecoMoneyBag", bundle: resourceBundle)

    /// The "SessionArtDecoSlotMachine" asset catalog image resource.
    static let sessionArtDecoSlotMachine = ImageResource(name: "SessionArtDecoSlotMachine", bundle: resourceBundle)

    /// The "SessionArtDecoSpade" asset catalog image resource.
    static let sessionArtDecoSpade = ImageResource(name: "SessionArtDecoSpade", bundle: resourceBundle)

    /// The "SessionArtDecoSparkles" asset catalog image resource.
    static let sessionArtDecoSparkles = ImageResource(name: "SessionArtDecoSparkles", bundle: resourceBundle)

    /// The "SessionArtDecoTicket" asset catalog image resource.
    static let sessionArtDecoTicket = ImageResource(name: "SessionArtDecoTicket", bundle: resourceBundle)

    /// The "TierTapLogo" asset catalog image resource.
    static let tierTapLogo = ImageResource(name: "TierTapLogo", bundle: resourceBundle)

    /// The "TierTap_C_PokerChip" asset catalog image resource.
    static let tierTapCPokerChip = ImageResource(name: "TierTap_C_PokerChip", bundle: resourceBundle)

}

// MARK: - Backwards Deployment Support -

/// A color resource.
struct ColorResource: Swift.Hashable, Swift.Sendable {

    /// An asset catalog color resource name.
    fileprivate let name: Swift.String

    /// An asset catalog color resource bundle.
    fileprivate let bundle: Foundation.Bundle

    /// Initialize a `ColorResource` with `name` and `bundle`.
    init(name: Swift.String, bundle: Foundation.Bundle) {
        self.name = name
        self.bundle = bundle
    }

}

/// An image resource.
struct ImageResource: Swift.Hashable, Swift.Sendable {

    /// An asset catalog image resource name.
    fileprivate let name: Swift.String

    /// An asset catalog image resource bundle.
    fileprivate let bundle: Foundation.Bundle

    /// Initialize an `ImageResource` with `name` and `bundle`.
    init(name: Swift.String, bundle: Foundation.Bundle) {
        self.name = name
        self.bundle = bundle
    }

}

#if canImport(AppKit)
@available(macOS 10.13, *)
@available(macCatalyst, unavailable)
extension AppKit.NSColor {

    /// Initialize a `NSColor` with a color resource.
    convenience init(resource: ColorResource) {
        self.init(named: NSColor.Name(resource.name), bundle: resource.bundle)!
    }

}

protocol _ACResourceInitProtocol {}
extension AppKit.NSImage: _ACResourceInitProtocol {}

@available(macOS 10.7, *)
@available(macCatalyst, unavailable)
extension _ACResourceInitProtocol {

    /// Initialize a `NSImage` with an image resource.
    init(resource: ImageResource) {
        self = resource.bundle.image(forResource: NSImage.Name(resource.name))! as! Self
    }

}
#endif

#if canImport(UIKit)
@available(iOS 11.0, tvOS 11.0, *)
@available(watchOS, unavailable)
extension UIKit.UIColor {

    /// Initialize a `UIColor` with a color resource.
    convenience init(resource: ColorResource) {
#if !os(watchOS)
        self.init(named: resource.name, in: resource.bundle, compatibleWith: nil)!
#else
        self.init()
#endif
    }

}

@available(iOS 11.0, tvOS 11.0, *)
@available(watchOS, unavailable)
extension UIKit.UIImage {

    /// Initialize a `UIImage` with an image resource.
    convenience init(resource: ImageResource) {
#if !os(watchOS)
        self.init(named: resource.name, in: resource.bundle, compatibleWith: nil)!
#else
        self.init()
#endif
    }

}
#endif

#if canImport(SwiftUI)
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension SwiftUI.Color {

    /// Initialize a `Color` with a color resource.
    init(_ resource: ColorResource) {
        self.init(resource.name, bundle: resource.bundle)
    }

}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension SwiftUI.Image {

    /// Initialize an `Image` with an image resource.
    init(_ resource: ImageResource) {
        self.init(resource.name, bundle: resource.bundle)
    }

}
#endif