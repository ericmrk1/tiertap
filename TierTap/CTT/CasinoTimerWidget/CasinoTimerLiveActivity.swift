import ActivityKit
import WidgetKit
import SwiftUI

struct CasinoTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            // Lock Screen / Notification Banner View
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.9))
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 5) {
                            Circle().fill(Color.red).frame(width: 6, height: 6)
                            Text("LIVE SESSION")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.red)
                        }
                        Text(context.state.casino)
                            .font(.headline).foregroundColor(.white)
                        Text(context.state.game)
                            .font(.caption).foregroundColor(.gray)
                        HStack(spacing: 4) {
                            Image(systemName: "dollarsign.circle.fill")
                                .foregroundColor(.green).font(.caption)
                            Text("Buy-in: $\(context.state.totalBuyIn)")
                                .font(.caption).foregroundColor(.green)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundColor(.green).font(.title3)
                        Text(context.state.startTime, style: .timer)
                            .font(.system(.title2, design: .monospaced).bold())
                            .foregroundColor(.green)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 14)
            }
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.casino)
                            .font(.caption.bold()).foregroundColor(.white)
                        Text(context.state.game)
                            .font(.caption2).foregroundColor(.gray)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(context.state.startTime, style: .timer)
                            .font(.system(.caption, design: .monospaced).bold())
                            .foregroundColor(.green)
                        Text("$\(context.state.totalBuyIn)")
                            .font(.caption2).foregroundColor(.gray)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Image(systemName: "arrow.up.circle.fill").foregroundColor(.green)
                        Text("TierTap · Table Session Active")
                            .font(.caption2).foregroundColor(.gray)
                    }
                }
            } compactLeading: {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundColor(.green).font(.caption)
            } compactTrailing: {
                Text(context.state.startTime, style: .timer)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.green)
                    .monospacedDigit()
                    .frame(width: 44)
            } minimal: {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundColor(.green).font(.caption)
            }
        }
    }
}
