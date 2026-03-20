#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The "TierTapLogo" asset catalog image resource.
static NSString * const ACImageNameTierTapLogo AC_SWIFT_PRIVATE = @"TierTapLogo";

/// The "TierTap_C_PokerChip" asset catalog image resource.
static NSString * const ACImageNameTierTapCPokerChip AC_SWIFT_PRIVATE = @"TierTap_C_PokerChip";

#undef AC_SWIFT_PRIVATE
