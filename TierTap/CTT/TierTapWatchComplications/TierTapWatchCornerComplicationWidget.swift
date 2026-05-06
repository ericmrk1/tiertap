import WidgetKit
import SwiftUI
import Foundation

private struct TierTapWatchComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: TierTapLiveSessionSnapshot?
}

private struct TierTapLiveSessionSnapshot: Codable {
    struct BuyInEvent: Codable {
        let amount: Int
    }

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
                casino: "TierTap",
                startTime: Date().addingTimeInterval(-35 * 60),
                isLive: true,
                buyInEvents: [.init(amount: 200), .init(amount: 100)],
                liveTrackedStackAmount: 340
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TierTapWatchComplicationEntry) -> Void) {
        completion(TierTapWatchComplicationEntry(date: Date(), snapshot: loadLiveSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TierTapWatchComplicationEntry>) -> Void) {
        let now = Date()
        let entry = TierTapWatchComplicationEntry(date: now, snapshot: loadLiveSnapshot())
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

struct TierTapWatchCornerComplicationWidget: Widget {
    private let kind = "TierTapWatchCornerComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TierTapWatchComplicationProvider()) { entry in
            TierTapWatchCornerComplicationView(entry: entry)
        }
        .configurationDisplayName("TierTap Live")
        .description("Live timer and running result for watch faces.")
        .supportedFamilies([.accessoryInline, .accessoryCircular, .accessoryRectangular, .accessoryCorner])
    }
}

private struct TierTapWatchCornerComplicationView: View {
    let entry: TierTapWatchComplicationEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let snap = entry.snapshot
        let isLive = snap?.isLive ?? false
        let start = snap?.startTime ?? entry.date
        let running = snap?.runningWinLoss
        let buyIn = snap?.totalBuyIn ?? 0

        Group {
            if isLive {
                switch family {
                case .accessoryCorner:
                    Text(money(running))
                        .widgetLabel {
                            Text(start, style: .timer)
                        }
                case .accessoryInline:
                    Text("TierTap \(money(running)) \(start, style: .timer)")
                case .accessoryCircular:
                    ZStack {
                        AccessoryWidgetBackground()
                        VStack(spacing: 1) {
                            Text(start, style: .timer)
                                .font(.system(.caption2, design: .monospaced))
                                .monospacedDigit()
                            Text(money(running))
                                .font(.system(size: 10, weight: .bold))
                        }
                    }
                default:
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TierTap")
                            .font(.caption2.weight(.semibold))
                        Text(start, style: .timer)
                            .font(.system(.caption2, design: .monospaced))
                            .monospacedDigit()
                        Text("Buy-in $\(buyIn)  \(money(running))")
                            .font(.caption2)
                    }
                }
            } else {
                switch family {
                case .accessoryCorner:
                    Text("TT")
                        .widgetLabel { Text("No live") }
                case .accessoryInline:
                    Text("TierTap No live")
                case .accessoryCircular:
                    ZStack {
                        AccessoryWidgetBackground()
                        Image(systemName: "clock.badge.xmark")
                    }
                default:
                    Text("No live session")
                        .font(.caption2)
                }
            }
        }
        .widgetURL(URL(string: isLive ? "com.app.tiertap://watch/live" : "com.app.tiertap://watch"))
    }

    private func money(_ amount: Int?) -> String {
        guard let amount else { return "--" }
        if amount > 0 { return "+$\(amount)" }
        if amount < 0 { return "-$\(abs(amount))" }
        return "$0"
    }
}
