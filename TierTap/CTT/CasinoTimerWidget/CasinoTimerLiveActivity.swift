import ActivityKit
import WidgetKit
import SwiftUI
import Foundation

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

private struct TierTapWatchComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: TierTapLiveSessionSnapshot?
}

private struct TierTapLiveSessionSnapshot: Codable {
    struct BuyInEvent: Codable {
        let amount: Int
    }

    let game: String
    let casino: String
    let startTime: Date
    let isLive: Bool?
    let buyInEvents: [BuyInEvent]
    let liveTrackedStackAmount: Int?

    var totalBuyIn: Int {
        buyInEvents.reduce(0) { $0 + max(0, $1.amount) }
    }

    var runningWinLoss: Int? {
        guard let stack = liveTrackedStackAmount else { return nil }
        return stack - totalBuyIn
    }
}

private struct TierTapWatchComplicationProvider: TimelineProvider {
    private let appGroupSuiteName = "group.com.app.tiertap"
    private let liveSnapshotKey = "ctt_wc_live_snapshot"

    func placeholder(in context: Context) -> TierTapWatchComplicationEntry {
        TierTapWatchComplicationEntry(
            date: Date(),
            snapshot: TierTapLiveSessionSnapshot(
                game: "Blackjack",
                casino: "TierTap",
                startTime: Date().addingTimeInterval(-45 * 60),
                isLive: true,
                buyInEvents: [.init(amount: 200), .init(amount: 100)],
                liveTrackedStackAmount: 360
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TierTapWatchComplicationEntry) -> Void) {
        completion(TierTapWatchComplicationEntry(date: Date(), snapshot: loadLiveSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TierTapWatchComplicationEntry>) -> Void) {
        let now = Date()
        let entry = TierTapWatchComplicationEntry(date: now, snapshot: loadLiveSnapshot())
        // Refresh every minute so the elapsed timer text remains current.
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 1, to: now) ?? now.addingTimeInterval(60)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func loadLiveSnapshot() -> TierTapLiveSessionSnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroupSuiteName),
              let data = defaults.data(forKey: liveSnapshotKey),
              !data.isEmpty else {
            return nil
        }
        return try? JSONDecoder().decode(TierTapLiveSessionSnapshot.self, from: data)
    }
}

struct TierTapWatchComplicationWidget: Widget {
    private let kind = "TierTapWatchComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TierTapWatchComplicationProvider()) { entry in
            TierTapWatchComplicationView(entry: entry)
        }
        .configurationDisplayName("Live Session")
        .description("Shows live session time and running result.")
        .supportedFamilies([.accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

private struct TierTapWatchComplicationView: View {
    let entry: TierTapWatchComplicationEntry
    @Environment(\.widgetFamily) private var family

    @ViewBuilder
    private func liveView(snapshot: TierTapLiveSessionSnapshot, timerStart: Date, running: Int?, buyIn: Int) -> some View {
        switch family {
        case .accessoryInline:
            Text("\(shortCode(snapshot.casino)) \(winLossText(running)) · \(timerStart, style: .timer)")
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 1) {
                    Text(timerStart, style: .timer)
                        .font(.system(.caption2, design: .monospaced))
                        .monospacedDigit()
                    Text(winLossText(running))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor((running ?? 0) >= 0 ? .green : .red)
                }
            }
        default:
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.casino)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                Text(timerStart, style: .timer)
                    .font(.system(.caption2, design: .monospaced))
                    .monospacedDigit()
                    .lineLimit(1)
                Text("Buy-in $\(buyIn)  \(winLossText(running))")
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundColor((running ?? 0) >= 0 ? .green : .red)
            }
        }
    }

    @ViewBuilder
    private var emptyView: some View {
        switch family {
        case .accessoryInline:
            Text("TierTap · No live session")
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "clock.badge.xmark")
                    .font(.caption)
            }
        default:
            Text("No live session")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func shortCode(_ value: String) -> String {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "TT" }
        return String(cleaned.prefix(3)).uppercased()
    }

    private func winLossText(_ amount: Int?) -> String {
        guard let amount else { return "--" }
        if amount > 0 { return "+$\(amount)" }
        if amount < 0 { return "-$\(abs(amount))" }
        return "$0"
    }

    var body: some View {
        let snap = entry.snapshot
        let isLive = snap?.isLive ?? false
        let timerStart = snap?.startTime ?? entry.date
        let running = snap?.runningWinLoss
        let buyIn = snap?.totalBuyIn ?? 0

        Group {
            if let snap, isLive {
                liveView(snapshot: snap, timerStart: timerStart, running: running, buyIn: buyIn)
                    .widgetURL(URL(string: "com.app.tiertap://watch/live"))
            } else {
                emptyView
                    .widgetURL(URL(string: "com.app.tiertap://watch"))
            }
        }
    }
}
