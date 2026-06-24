import WidgetKit
import SwiftUI

// MARK: - Timeline

struct TierTapHomeWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: TierTapHomeWidgetSnapshot?
}

struct TierTapHomeWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TierTapHomeWidgetEntry {
        TierTapHomeWidgetEntry(date: Date(), snapshot: TierTapHomeWidgetPreviewData.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (TierTapHomeWidgetEntry) -> Void) {
        completion(TierTapHomeWidgetEntry(date: Date(), snapshot: TierTapWidgetSnapshotStore.load() ?? TierTapHomeWidgetPreviewData.sample))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TierTapHomeWidgetEntry>) -> Void) {
        let now = Date()
        let entry = TierTapHomeWidgetEntry(date: now, snapshot: TierTapWidgetSnapshotStore.load())
        let refresh: Date
        if entry.snapshot?.isLiveSession == true {
            refresh = Calendar.current.date(byAdding: .minute, value: 1, to: now) ?? now.addingTimeInterval(60)
        } else {
            refresh = Calendar.current.date(byAdding: .minute, value: 15, to: now) ?? now.addingTimeInterval(900)
        }
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

enum TierTapHomeWidgetPreviewData {
    static let sample = TierTapHomeWidgetSnapshot(
        updatedAt: Date(),
        currencySymbol: "$",
        primaryColorHex: "#1A1A2E",
        isLiveSession: false,
        liveSessionStartTime: nil,
        sessionMetricTitle: "Last Session",
        sessionMetricValue: "02:14:35",
        sessionMetricTrend: .up,
        metrics: [
            .init(title: "Bankroll", value: "$4,820", metricId: "bankroll", trend: .up),
            .init(title: "Today", value: "+$240", metricId: "today", trend: .up),
            .init(title: "Last Tier", value: "18,420", metricId: "tier", trend: .up)
        ]
    )
}

// MARK: - Widget

struct TierTapHomeWidget: Widget {
    private let kind = "TierTapHomeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TierTapHomeWidgetProvider()) { entry in
            TierTapHomeWidgetEntryView(entry: entry)
                .tierTapWidgetContainer(primaryHex: entry.snapshot?.primaryColorHex ?? TierTapHomeWidgetPreviewData.sample.primaryColorHex)
        }
        .configurationDisplayName("TierTap Dashboard")
        .description("Session time, bankroll, today's results, and tier status.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Root view

struct TierTapHomeWidgetEntryView: View {
    let entry: TierTapHomeWidgetEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: TierTapHomeWidgetSnapshot {
        entry.snapshot ?? TierTapHomeWidgetPreviewData.sample
    }

    private var dense: Bool { family == .systemSmall }
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: dense ? 6 : 8), count: 2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: dense ? 6 : 8) {
            HStack(spacing: 6) {
                if snapshot.isLiveSession {
                    Circle().fill(Color.red).frame(width: dense ? 5 : 6, height: dense ? 5 : 6)
                }
                Text("TierTap")
                    .font(.system(size: dense ? 10 : 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer(minLength: 0)
            }

            LazyVGrid(columns: columns, spacing: dense ? 6 : 8) {
                TierTapWidgetSessionMetricCell(snapshot: snapshot, dense: dense)
                ForEach(Array(snapshot.metrics.enumerated()), id: \.offset) { _, metric in
                    LiveSessionSummaryCell(
                        title: metric.title,
                        value: metric.value,
                        metricId: metric.metricId,
                        compact: !dense,
                        dense: dense,
                        trend: metric.trend?.liveTrend
                    )
                }
            }
        }
        .padding(dense ? 10 : 12)
        .widgetURL(TierTapWidgetDeepLink.home)
    }
}

// MARK: - Session metric (live timer or last duration)

private struct TierTapWidgetSessionMetricCell: View {
    let snapshot: TierTapHomeWidgetSnapshot
    let dense: Bool

    private var valueFont: Font {
        dense ? .system(size: 9, weight: .semibold) : .system(size: 14, weight: .semibold)
    }

    private var titleFont: Font {
        dense ? .system(size: 8) : .system(size: 9)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: dense ? 0 : 1) {
            HStack(spacing: 3) {
                Image(systemName: "clock.fill")
                    .font(.system(size: dense ? 8 : 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.65))
                Text(snapshot.sessionMetricTitle)
                    .font(titleFont)
                    .foregroundColor(.white.opacity(0.65))
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Group {
                    if snapshot.isLiveSession, let start = snapshot.liveSessionStartTime {
                        Text(start, style: .timer)
                            .monospacedDigit()
                            .foregroundColor(.green)
                    } else {
                        Text(snapshot.sessionMetricValue)
                            .foregroundColor(.white)
                    }
                }
                .font(valueFont)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                Spacer(minLength: 0)
                if let trend = snapshot.sessionMetricTrend?.liveTrend {
                    Image(systemName: trend.symbolName)
                        .font(valueFont)
                        .foregroundColor(trend.color)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: dense ? 24 : 28, alignment: .leading)
        .padding(.horizontal, dense ? 4 : 6)
        .padding(.vertical, dense ? 3 : 4)
        .background(Color.white.opacity(0.08))
        .cornerRadius(dense ? 5 : 6)
    }
}

// MARK: - Background

private struct TierTapWidgetBackground: View {
    let primaryHex: String?

    var body: some View {
        LinearGradient(
            colors: [
                TierTapWidgetColor.fromHex(primaryHex) ?? Color(red: 0.06, green: 0.06, blue: 0.1),
                Color(red: 0.02, green: 0.02, blue: 0.04)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct TierTapWidgetContainerModifier: ViewModifier {
    let primaryHex: String?

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.containerBackground(for: .widget) {
                TierTapWidgetBackground(primaryHex: primaryHex)
            }
        } else {
            content.background(TierTapWidgetBackground(primaryHex: primaryHex))
        }
    }
}

private extension View {
    func tierTapWidgetContainer(primaryHex: String?) -> some View {
        modifier(TierTapWidgetContainerModifier(primaryHex: primaryHex))
    }
}

enum TierTapWidgetDeepLink {
    static let home = URL(string: "com.app.tiertap://sessions")!
}

private extension TierTapHomeWidgetSnapshot.MetricTrend {
    var liveTrend: LiveSessionMetricTrend {
        switch self {
        case .up: return .up
        case .down: return .down
        case .flat: return .flat
        }
    }
}

enum TierTapWidgetColor {
    static func fromHex(_ hex: String?) -> Color? {
        guard var raw = hex?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if raw.hasPrefix("#") { raw.removeFirst() }
        guard raw.count == 6, let value = UInt64(raw, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}

#if DEBUG
struct TierTapHomeWidget_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            TierTapHomeWidgetEntryView(entry: .init(date: Date(), snapshot: TierTapHomeWidgetPreviewData.sample))
                .tierTapWidgetContainer(primaryHex: "#1A1A2E")
                .previewContext(WidgetPreviewContext(family: .systemSmall))
            TierTapHomeWidgetEntryView(entry: .init(date: Date(), snapshot: TierTapHomeWidgetPreviewData.sample))
                .tierTapWidgetContainer(primaryHex: "#1A1A2E")
                .previewContext(WidgetPreviewContext(family: .systemMedium))
            TierTapHomeWidgetEntryView(entry: .init(date: Date(), snapshot: TierTapHomeWidgetPreviewData.sample))
                .tierTapWidgetContainer(primaryHex: "#1A1A2E")
                .previewContext(WidgetPreviewContext(family: .systemLarge))
        }
    }
}
#endif
