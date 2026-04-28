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

/// The "SessionArtDecoCoin" asset catalog image resource.
static NSString * const ACImageNameSessionArtDecoCoin AC_SWIFT_PRIVATE = @"SessionArtDecoCoin";

/// The "SessionArtDecoCrown" asset catalog image resource.
static NSString * const ACImageNameSessionArtDecoCrown AC_SWIFT_PRIVATE = @"SessionArtDecoCrown";

/// The "SessionArtDecoDiamond" asset catalog image resource.
static NSString * const ACImageNameSessionArtDecoDiamond AC_SWIFT_PRIVATE = @"SessionArtDecoDiamond";

/// The "SessionArtDecoDice" asset catalog image resource.
static NSString * const ACImageNameSessionArtDecoDice AC_SWIFT_PRIVATE = @"SessionArtDecoDice";

/// The "SessionArtDecoGem" asset catalog image resource.
static NSString * const ACImageNameSessionArtDecoGem AC_SWIFT_PRIVATE = @"SessionArtDecoGem";

/// The "SessionArtDecoHeart" asset catalog image resource.
static NSString * const ACImageNameSessionArtDecoHeart AC_SWIFT_PRIVATE = @"SessionArtDecoHeart";

/// The "SessionArtDecoJoker" asset catalog image resource.
static NSString * const ACImageNameSessionArtDecoJoker AC_SWIFT_PRIVATE = @"SessionArtDecoJoker";

/// The "SessionArtDecoMoneyBag" asset catalog image resource.
static NSString * const ACImageNameSessionArtDecoMoneyBag AC_SWIFT_PRIVATE = @"SessionArtDecoMoneyBag";

/// The "SessionArtDecoSlotMachine" asset catalog image resource.
static NSString * const ACImageNameSessionArtDecoSlotMachine AC_SWIFT_PRIVATE = @"SessionArtDecoSlotMachine";

/// The "SessionArtDecoSpade" asset catalog image resource.
static NSString * const ACImageNameSessionArtDecoSpade AC_SWIFT_PRIVATE = @"SessionArtDecoSpade";

/// The "SessionArtDecoSparkles" asset catalog image resource.
static NSString * const ACImageNameSessionArtDecoSparkles AC_SWIFT_PRIVATE = @"SessionArtDecoSparkles";

/// The "SessionArtDecoTicket" asset catalog image resource.
static NSString * const ACImageNameSessionArtDecoTicket AC_SWIFT_PRIVATE = @"SessionArtDecoTicket";

/// The "TierTapLogo" asset catalog image resource.
static NSString * const ACImageNameTierTapLogo AC_SWIFT_PRIVATE = @"TierTapLogo";

/// The "TierTap_C_PokerChip" asset catalog image resource.
static NSString * const ACImageNameTierTapCPokerChip AC_SWIFT_PRIVATE = @"TierTap_C_PokerChip";

#undef AC_SWIFT_PRIVATE
