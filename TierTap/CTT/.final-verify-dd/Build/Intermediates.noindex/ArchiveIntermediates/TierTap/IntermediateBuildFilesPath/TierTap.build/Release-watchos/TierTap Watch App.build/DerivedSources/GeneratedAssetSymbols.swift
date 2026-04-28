import Foundation
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

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DeveloperToolsSupport.ColorResource {

}

// MARK: - Image Symbols -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DeveloperToolsSupport.ImageResource {

    /// The "TierTapLogo" asset catalog image resource.
    static let tierTapLogo = DeveloperToolsSupport.ImageResource(name: "TierTapLogo", bundle: resourceBundle)

    /// The "TierTap_C_PokerChip" asset catalog image resource.
    static let tierTapCPokerChip = DeveloperToolsSupport.ImageResource(name: "TierTap_C_PokerChip", bundle: resourceBundle)

}

