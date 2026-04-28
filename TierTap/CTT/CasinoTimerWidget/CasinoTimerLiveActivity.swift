import ActivityKit
import WidgetKit
import SwiftUI

struct CasinoTimerLiveActivity: Widget {
    private func shortCode(_ value: String) -> String {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "TT" }
        return String(cleaned.prefix(3)).uppercased()
    }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            // Lock Screen / Notification Banner View
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.9))
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            Circle().fill(Color.red).frame(width: 6, height: 6)
                            Text("LIVE SESSION")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.red)
                        }
                        Text(context.state.casino)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                        Text(context.state.game)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .lineLimit(2)
                        Text("Starting tier \(context.state.startingTierPoints.formatted(.number.grouping(.automatic)))")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.85))
                        if let prog = context.state.rewardsProgramName?.trimmingCharacters(in: .whitespacesAndNewlines), !prog.isEmpty {
                            Text(prog)
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                        Text("Total buy-in $\(context.state.totalBuyIn.formatted(.number.grouping(.automatic)))")
                            .font(.caption2)
                            .foregroundColor(.green.opacity(0.95))
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundColor(.green)
                            .font(.body)
                        Text(context.state.startTime, style: .timer)
                            .font(.system(.title3, design: .monospaced).bold())
                            .foregroundColor(.green)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                    }
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
            }
            .widgetURL(URL(string: "com.app.tiertap://watch/live"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(context.state.casino)
                            .font(.caption.bold()).foregroundColor(.white)
                            .lineLimit(1)
                        Text(context.state.game)
                            .font(.caption2).foregroundColor(.gray)
                            .lineLimit(1)
                        Text("Start \(context.state.startingTierPoints.formatted(.number.grouping(.automatic)))")
                            .font(.caption2).foregroundColor(.white.opacity(0.85))
                        if let prog = context.state.rewardsProgramName?.trimmingCharacters(in: .whitespacesAndNewlines), !prog.isEmpty {
                            Text(prog)
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.65))
                                .lineLimit(1)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(context.state.startTime, style: .timer)
                            .font(.system(.caption, design: .monospaced).bold())
                            .foregroundColor(.green)
                        Text("In $\(context.state.totalBuyIn.formatted(.number.grouping(.automatic)))")
                            .font(.caption2).foregroundColor(.gray)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Image(systemName: "arrow.up.circle.fill").foregroundColor(.green).font(.caption)
                        Text("TierTap · live")
                            .font(.caption2).foregroundColor(.gray)
                    }
                }
            } compactLeading: {
                Text(shortCode(context.state.casino))
                    .font(.system(.caption2, design: .rounded).bold())
                    .foregroundColor(.green)
            } compactTrailing: {
                Text(context.state.startTime, style: .timer)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.green)
                    .monospacedDigit()
                    .frame(width: 44)
            } minimal: {
                Text(shortCode(context.state.game))
                    .font(.system(.caption2, design: .rounded).bold())
                    .foregroundColor(.green)
            }
        }
    }
}
