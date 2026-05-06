import WidgetKit
import SwiftUI

@main
struct TierTapWatchComplicationsBundle: WidgetBundle {
    var body: some Widget {
        TierTapWatchCornerComplicationWidget()
        TierTapWatchStackComplicationWidget()
        TierTapWatchStackWinLossComplicationWidget()
        TierTapWatchBuyInComplicationWidget()
    }
}
