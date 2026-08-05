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

    var resolvedStackAmount: Int {
        liveTrackedStackAmount ?? totalBuyIn
    }
}

private struct TierTapWatchComplicationProvider: TimelineProvider {
    private let appGroupSuiteName = "group.com.app.tiertap"
    private let liveSnapshotKey = "ctt_wc_live_snapshot"
    private let watchLiveKey = "ctt_live_v2"

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
        guard let defaults = UserDefaults(suiteName: appGroupSuiteName) else { return nil }

        if let data = defaults.data(forKey: liveSnapshotKey),
           !data.isEmpty,
           let snap = try? JSONDecoder().decode(TierTapLiveSessionSnapshot.self, from: data) {
            return snap
        }

        // Fallback for watch-originated updates persisted locally by SessionStore.
        if let data = defaults.data(forKey: watchLiveKey),
           !data.isEmpty,
           let snap = try? JSONDecoder().decode(TierTapLiveSessionSnapshot.self, from: data) {
            return snap
        }

        return nil
    }
}

private enum TierTapComplicationFocus {
    case liveResult
    case stackSize
    case stackAndWinLoss
    case buyIn

    var kind: String {
        switch self {
        case .liveResult: return "TierTapWatchCornerComplication"
        case .stackSize: return "TierTapWatchStackComplication"
        case .stackAndWinLoss: return "TierTapWatchStackWinLossComplication"
        case .buyIn: return "TierTapWatchBuyInComplication"
        }
    }

    var displayName: String {
        switch self {
        case .liveResult: return "TierTap Live"
        case .stackSize: return "TierTap Stack"
        case .stackAndWinLoss: return "TierTap Stack + W/L"
        case .buyIn: return "TierTap Buy-in"
        }
    }

    var description: String {
        switch self {
        case .liveResult: return "Live timer and running result for watch faces."
        case .stackSize: return "Shows live stack size as the primary value."
        case .stackAndWinLoss: return "Shows stack size and running win/loss."
        case .buyIn: return "Shows live total buy-in as the primary value."
        }
    }
}

struct TierTapWatchCornerComplicationWidget: Widget {
    private let focus: TierTapComplicationFocus = .liveResult

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: focus.kind, provider: TierTapWatchComplicationProvider()) { entry in
            TierTapWatchCornerComplicationView(entry: entry, focus: focus)
        }
        .configurationDisplayName(focus.displayName)
        .description(focus.description)
        .supportedFamilies([.accessoryInline, .accessoryCircular, .accessoryRectangular, .accessoryCorner])
    }
}

struct TierTapWatchStackComplicationWidget: Widget {
    private let focus: TierTapComplicationFocus = .stackSize

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: focus.kind, provider: TierTapWatchComplicationProvider()) { entry in
            TierTapWatchCornerComplicationView(entry: entry, focus: focus)
        }
        .configurationDisplayName(focus.displayName)
        .description(focus.description)
        .supportedFamilies([.accessoryInline, .accessoryCircular, .accessoryRectangular, .accessoryCorner])
    }
}

struct TierTapWatchStackWinLossComplicationWidget: Widget {
    private let focus: TierTapComplicationFocus = .stackAndWinLoss

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: focus.kind, provider: TierTapWatchComplicationProvider()) { entry in
            TierTapWatchCornerComplicationView(entry: entry, focus: focus)
        }
        .configurationDisplayName(focus.displayName)
        .description(focus.description)
        .supportedFamilies([.accessoryInline, .accessoryCircular, .accessoryRectangular, .accessoryCorner])
    }
}

struct TierTapWatchBuyInComplicationWidget: Widget {
    private let focus: TierTapComplicationFocus = .buyIn

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: focus.kind, provider: TierTapWatchComplicationProvider()) { entry in
            TierTapWatchCornerComplicationView(entry: entry, focus: focus)
        }
        .configurationDisplayName(focus.displayName)
        .description(focus.description)
        .supportedFamilies([.accessoryInline, .accessoryCircular, .accessoryRectangular, .accessoryCorner])
    }
}

private struct TierTapWatchCornerComplicationView: View {
    let entry: TierTapWatchComplicationEntry
    let focus: TierTapComplicationFocus
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let snap = entry.snapshot
        let isLive = snap?.isLive ?? false
        let start = snap?.startTime ?? entry.date
        let running = snap?.runningWinLoss
        let buyIn = snap?.totalBuyIn ?? 0
        let stack = snap?.resolvedStackAmount ?? 0
        let primary = primaryText(running: running, buyIn: buyIn, stack: stack)
        let secondary = secondaryText(start: start, running: running)

        Group {
            if isLive {
                switch family {
                case .accessoryCorner:
                    Text(primary)
                        .widgetLabel {
                            Text(secondary)
                        }
                case .accessoryInline:
                    Text("TierTap \(primary) \(secondary)")
                case .accessoryCircular:
                    ZStack {
                        AccessoryWidgetBackground()
                        VStack(spacing: 1) {
                            Text(primary)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Text(shortSecondaryText(start: start, running: running))
                                .font(.system(size: 10, weight: .bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                    }
                default:
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TierTap")
                            .font(.caption2.weight(.semibold))
                        Text(primary)
                            .font(.caption2.weight(.bold))
                            .lineLimit(1)
                        Text(secondary)
                            .font(.caption2)
                            .lineLimit(1)
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

    private func primaryText(running: Int?, buyIn: Int, stack: Int) -> String {
        switch focus {
        case .liveResult:
            return money(running)
        case .stackSize:
            return "$\(stack)"
        case .stackAndWinLoss:
            return "$\(stack) \(money(running))"
        case .buyIn:
            return "$\(buyIn)"
        }
    }

    private func secondaryText(start: Date, running: Int?) -> String {
        switch focus {
        case .liveResult:
            return timerText(start)
        case .stackSize:
            return timerText(start)
        case .stackAndWinLoss:
            return timerText(start)
        case .buyIn:
            return money(running)
        }
    }

    private func shortSecondaryText(start: Date, running: Int?) -> String {
        switch focus {
        case .buyIn:
            return money(running)
        default:
            return timerText(start)
        }
    }

    private func timerText(_ start: Date) -> String {
        let elapsed = max(0, Int(Date().timeIntervalSince(start)))
        let h = elapsed / 3600
        let m = (elapsed % 3600) / 60
        return h > 0 ? String(format: "%02dh %02dm", h, m) : String(format: "%02dm", m)
    }

    private func money(_ amount: Int?) -> String {
        guard let amount else { return "--" }
        if amount > 0 { return "+$\(amount)" }
        if amount < 0 { return "-$\(abs(amount))" }
        return "$0"
    }
}
