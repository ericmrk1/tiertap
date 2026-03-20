#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The resource bundle ID.
static NSString * const ACBundleID AC_SWIFT_PRIVATE = @"com.app.tiertap";

/// The "AccentColor" asset catalog color resource.
static NSString * const ACColorNameAccentColor AC_SWIFT_PRIVATE = @"AccentColor";

/// The "LogoSplash" asset catalog image resource.
static NSString * const ACImageNameLogoSplash AC_SWIFT_PRIVATE = @"LogoSplash";

/// The "TierTapLogo" asset catalog image resource.
static NSString * const ACImageNameTierTapLogo AC_SWIFT_PRIVATE = @"TierTapLogo";

/// The "TierTap_C_PokerChip" asset catalog image resource.
static NSString * const ACImageNameTierTapCPokerChip AC_SWIFT_PRIVATE = @"TierTap_C_PokerChip";

#undef AC_SWIFT_PRIVATE
