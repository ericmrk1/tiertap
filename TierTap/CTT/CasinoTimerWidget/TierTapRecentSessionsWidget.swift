import WidgetKit
import SwiftUI

// MARK: - Timeline

struct TierTapRecentSessionsEntry: TimelineEntry {
    let date: Date
    let snapshot: TierTapHomeWidgetSnapshot?
}

struct TierTapRecentSessionsProvider: TimelineProvider {
    func placeholder(in context: Context) -> TierTapRecentSessionsEntry {
        TierTapRecentSessionsEntry(date: Date(), snapshot: TierTapHomeWidgetPreviewData.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (TierTapRecentSessionsEntry) -> Void) {
        completion(TierTapRecentSessionsEntry(
            date: Date(),
            snapshot: TierTapWidgetSnapshotStore.load() ?? TierTapHomeWidgetPreviewData.sample
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TierTapRecentSessionsEntry>) -> Void) {
        let now = Date()
        let snapshot = TierTapWidgetSnapshotStore.load()
        let entry = TierTapRecentSessionsEntry(date: now, snapshot: snapshot)
        let refresh = Calendar.current.date(byAdding: .minute, value: 15, to: now) ?? now.addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

// MARK: - Widget

struct TierTapRecentSessionsWidget: Widget {
    private let kind = "TierTapRecentSessionsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TierTapRecentSessionsProvider()) { entry in
            TierTapRecentSessionsEntryView(entry: entry)
                .tierTapWidgetContainer(snapshot: entry.snapshot ?? TierTapHomeWidgetPreviewData.sample)
        }
        .configurationDisplayName("Recent Sessions")
        .description("Your most recent sessions that fit. Tap a session to open it.")
        .supportedFamilies([.systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

// MARK: - Entry view

struct TierTapRecentSessionsEntryView: View {
    let entry: TierTapRecentSessionsEntry
    @Environment(\.widgetFamily) private var family

    private static let maxStoredSessions = 8

    private var snapshot: TierTapHomeWidgetSnapshot {
        entry.snapshot ?? TierTapHomeWidgetPreviewData.sample
    }

    private var sessions: [TierTapWidgetRecentSession] {
        Array((snapshot.recentSessions ?? []).prefix(Self.maxStoredSessions))
    }

    var body: some View {
        Group {
            if sessions.isEmpty {
                TierTapRecentSessionsEmptyView()
                    .widgetURL(TierTapWidgetDeepLink.home)
            } else {
                TierTapRecentSessionsGridView(sessions: sessions, family: family)
            }
        }
    }
}

private struct TierTapRecentSessionsEmptyView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title3)
                .foregroundColor(.white.opacity(0.55))
            Text("No sessions yet")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.8))
            Text("Log a session in TierTap")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TierTapRecentSessionsGridView: View {
    let sessions: [TierTapWidgetRecentSession]
    let family: WidgetFamily

    private let horizontalPadding: CGFloat = 12
    private let tileSpacing: CGFloat = 8
    private let headerHeight: CGFloat = 22
    private let bottomPadding: CGFloat = 10
    private let minTileWidth: CGFloat = 108
    private let minTileHeight: CGFloat = 96

    private var rowCount: Int {
        family == .systemLarge ? 2 : 1
    }

    private func columnCount(for contentWidth: CGFloat) -> Int {
        max(1, Int(floor((contentWidth + tileSpacing) / (minTileWidth + tileSpacing))))
    }

    private func fittingSessionCount(contentWidth: CGFloat, contentHeight: CGFloat) -> Int {
        let columns = columnCount(for: contentWidth)
        let rows = min(
            rowCount,
            max(1, Int(floor((contentHeight + tileSpacing) / (minTileHeight + tileSpacing))))
        )
        return min(sessions.count, columns * rows)
    }

    var body: some View {
        GeometryReader { geo in
            let contentWidth = max(geo.size.width - horizontalPadding * 2, minTileWidth)
            let contentHeight = max(geo.size.height - headerHeight - bottomPadding, minTileHeight)
            let fitCount = fittingSessionCount(contentWidth: contentWidth, contentHeight: contentHeight)
            let visible = Array(sessions.prefix(fitCount))
            let columns = max(1, min(columnCount(for: contentWidth), visible.count))
            let rows = max(1, Int(ceil(Double(visible.count) / Double(columns))))
            let tileWidth = (contentWidth - CGFloat(columns - 1) * tileSpacing) / CGFloat(columns)
            let tileHeight = (contentHeight - CGFloat(rows - 1) * tileSpacing) / CGFloat(rows)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Recent Sessions", systemImage: "rectangle.stack.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.white.opacity(0.7))
                    Spacer(minLength: 0)
                    Image("TierTapLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 11)
                        .accessibilityHidden(true)
                }
                .frame(height: headerHeight)
                .padding(.horizontal, horizontalPadding)

                VStack(spacing: tileSpacing) {
                    ForEach(0..<rows, id: \.self) { row in
                        HStack(spacing: tileSpacing) {
                            ForEach(0..<columns, id: \.self) { column in
                                let index = row * columns + column
                                if index < visible.count {
                                    let session = visible[index]
                                    Link(destination: TierTapWidgetDeepLink.sessionDetail(session.id)) {
                                        TierTapRecentSessionWidgetTile(session: session)
                                            .frame(width: tileWidth, height: tileHeight)
                                    }
                                } else {
                                    Color.clear
                                        .frame(width: tileWidth, height: tileHeight)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, bottomPadding)
            }
        }
    }
}

private struct TierTapRecentSessionWidgetTile: View {
    let session: TierTapWidgetRecentSession

    private var verificationLabel: String {
        session.isVerified ? "Verified" : "Unverified"
    }

    private var verificationColor: Color {
        session.isVerified
            ? Color(red: 0.28, green: 0.92, blue: 0.48)
            : Color.yellow.opacity(0.95)
    }

    private var winLossColor: Color {
        guard let text = session.winLossText else { return .white.opacity(0.45) }
        if text.hasPrefix("+") { return .green }
        if text.hasPrefix("-") { return .red }
        return .white.opacity(0.85)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.casino)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(session.game)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(session.timeLabel)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)

            if let winLossText = session.winLossText {
                Text(winLossText)
                    .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundColor(winLossColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Text(verificationLabel)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(verificationColor)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(verificationColor.opacity(0.18))
                .cornerRadius(3)
        }
        .padding(7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
    }
}

#if DEBUG
struct TierTapRecentSessionsWidget_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            TierTapRecentSessionsEntryView(entry: .init(date: Date(), snapshot: TierTapHomeWidgetPreviewData.sample))
                .tierTapWidgetContainer(snapshot: TierTapHomeWidgetPreviewData.sample)
                .previewContext(WidgetPreviewContext(family: .systemMedium))
            TierTapRecentSessionsEntryView(entry: .init(date: Date(), snapshot: TierTapHomeWidgetPreviewData.sample))
                .tierTapWidgetContainer(snapshot: TierTapHomeWidgetPreviewData.sample)
                .previewContext(WidgetPreviewContext(family: .systemLarge))
        }
    }
}
#endif
