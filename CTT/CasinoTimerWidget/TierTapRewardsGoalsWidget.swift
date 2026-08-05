import WidgetKit
import SwiftUI

// MARK: - Timeline

struct TierTapRewardsGoalsEntry: TimelineEntry {
    let date: Date
    let snapshot: TierTapHomeWidgetSnapshot?
}

struct TierTapRewardsGoalsProvider: TimelineProvider {
    func placeholder(in context: Context) -> TierTapRewardsGoalsEntry {
        TierTapRewardsGoalsEntry(date: Date(), snapshot: TierTapHomeWidgetPreviewData.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (TierTapRewardsGoalsEntry) -> Void) {
        completion(TierTapRewardsGoalsEntry(
            date: Date(),
            snapshot: TierTapWidgetSnapshotStore.load() ?? TierTapHomeWidgetPreviewData.sample
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TierTapRewardsGoalsEntry>) -> Void) {
        let now = Date()
        let snapshot = TierTapWidgetSnapshotStore.load()
        let entry = TierTapRewardsGoalsEntry(date: now, snapshot: snapshot)
        let refresh = Calendar.current.date(byAdding: .minute, value: 15, to: now) ?? now.addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

// MARK: - Widget

struct TierTapRewardsGoalsWidget: Widget {
    private let kind = "TierTapRewardsGoalsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TierTapRewardsGoalsProvider()) { entry in
            TierTapRewardsGoalsEntryView(entry: entry)
                .tierTapWidgetContainer(snapshot: entry.snapshot ?? TierTapHomeWidgetPreviewData.sample)
        }
        .configurationDisplayName("Rewards Goals")
        .description("Circle progress for every wallet tier goal.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryCircular,
            .accessoryRectangular
        ])
        .contentMarginsDisabled()
    }
}

// MARK: - Entry view

struct TierTapRewardsGoalsEntryView: View {
    let entry: TierTapRewardsGoalsEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: TierTapHomeWidgetSnapshot {
        entry.snapshot ?? TierTapHomeWidgetPreviewData.sample
    }

    private var goals: [TierTapWidgetTierGoal] {
        (snapshot.tierGoals ?? []).sorted { lhs, rhs in
            if lhs.currentPoints != rhs.currentPoints {
                return lhs.currentPoints > rhs.currentPoints
            }
            return lhs.goalPoints > rhs.goalPoints
        }
    }

    var body: some View {
        Group {
            if goals.isEmpty {
                TierTapRewardsGoalsEmptyView()
                    .widgetURL(TierTapWidgetDeepLink.wallet)
            } else {
                switch family {
                case .systemSmall:
                    TierTapRewardsGoalsSmallView(goal: goals[0], totalCount: goals.count)
                        .widgetURL(TierTapWidgetDeepLink.wallet)
                case .systemMedium:
                    TierTapRewardsGoalsMediumView(goals: Array(goals.prefix(3)))
                case .systemLarge:
                    TierTapRewardsGoalsLargeView(goals: Array(goals.prefix(6)))
                case .accessoryCircular:
                    TierTapRewardsGoalsLockCircularView(goal: goals[0])
                        .widgetURL(TierTapWidgetDeepLink.wallet)
                case .accessoryRectangular:
                    TierTapRewardsGoalsLockRectangularView(goals: Array(goals.prefix(2)))
                        .widgetURL(TierTapWidgetDeepLink.wallet)
                default:
                    TierTapRewardsGoalsMediumView(goals: Array(goals.prefix(3)))
                }
            }
        }
    }
}

// MARK: - Empty

private struct TierTapRewardsGoalsEmptyView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "target")
                .font(.title3)
                .foregroundColor(.white.opacity(0.55))
            Text("No tier goals")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.8))
            Text("Set a goal on a Wallet card")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Small

private struct TierTapRewardsGoalsSmallView: View {
    let goal: TierTapWidgetTierGoal
    let totalCount: Int

    var body: some View {
        VStack(spacing: 8) {
            TierTapWidgetTierGoalRing(goal: goal, diameter: 72, lineWidth: 8)
            VStack(spacing: 2) {
                Text(goal.programName)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(goalSubtitle(goal))
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
                if totalCount > 1 {
                    Text("+\(totalCount - 1) more")
                        .font(.caption2)
                        .foregroundColor(.green.opacity(0.85))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Medium

private struct TierTapRewardsGoalsMediumView: View {
    let goals: [TierTapWidgetTierGoal]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "wallet.pass.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.green)
                Text("Rewards goals")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.85))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 2)

            HStack(alignment: .top, spacing: 10) {
                ForEach(goals) { goal in
                    Link(destination: TierTapWidgetDeepLink.wallet) {
                        VStack(spacing: 6) {
                            TierTapWidgetTierGoalRing(goal: goal, diameter: 56, lineWidth: 7)
                            Text(goal.programName)
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text(goalSubtitle(goal))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white.opacity(0.65))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .frame(width: 96)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Large

private struct TierTapRewardsGoalsLargeView: View {
    let goals: [TierTapWidgetTierGoal]

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "wallet.pass.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.green)
                Text("Rewards goals")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                Spacer(minLength: 0)
                Text("\(goals.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.white.opacity(0.5))
            }

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(goals) { goal in
                    Link(destination: TierTapWidgetDeepLink.wallet) {
                        HStack(spacing: 10) {
                            TierTapWidgetTierGoalRing(goal: goal, diameter: 48, lineWidth: 6)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(goal.programName)
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                if let label = goal.goalLabel, !label.isEmpty {
                                    Text(label)
                                        .font(.caption2)
                                        .foregroundColor(.cyan.opacity(0.9))
                                        .lineLimit(1)
                                }
                                Text("\(goal.currentPoints.formatted(.number.grouping(.automatic))) / \(goal.goalPoints.formatted(.number.grouping(.automatic)))")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundColor(.white.opacity(0.7))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                                Text(goal.isComplete ? "Goal reached" : "\(goal.pointsRemaining.formatted(.number.grouping(.automatic))) pts to go")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(goal.isComplete ? .green : .white.opacity(0.55))
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Lock screen

private struct TierTapRewardsGoalsLockCircularView: View {
    let goal: TierTapWidgetTierGoal

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            TierTapWidgetTierGoalRing(goal: goal, diameter: 52, lineWidth: 6, showPercent: true)
        }
    }
}

private struct TierTapRewardsGoalsLockRectangularView: View {
    let goals: [TierTapWidgetTierGoal]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(goals) { goal in
                HStack(spacing: 6) {
                    TierTapWidgetTierGoalRing(goal: goal, diameter: 28, lineWidth: 4, showPercent: false)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(goal.programName)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                        Text(goalSubtitle(goal))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Ring

private struct TierTapWidgetTierGoalRing: View {
    let goal: TierTapWidgetTierGoal
    var diameter: CGFloat
    var lineWidth: CGFloat
    var showPercent: Bool = true

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: goal.progress)
                .stroke(
                    goal.isComplete ? Color.green : Color.green.opacity(0.95),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            if showPercent {
                Text("\(Int((goal.progress * 100).rounded()))%")
                    .font(.system(size: max(9, diameter * 0.22), weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

private func goalSubtitle(_ goal: TierTapWidgetTierGoal) -> String {
    if goal.isComplete {
        return goal.goalLabel.map { "\($0) reached" } ?? "Goal reached"
    }
    if let label = goal.goalLabel, !label.isEmpty {
        return "\(goal.pointsRemaining.formatted(.number.grouping(.automatic))) to \(label)"
    }
    return "\(goal.pointsRemaining.formatted(.number.grouping(.automatic))) pts left"
}

#if DEBUG
struct TierTapRewardsGoalsWidget_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            TierTapRewardsGoalsEntryView(entry: .init(date: Date(), snapshot: TierTapHomeWidgetPreviewData.sample))
                .tierTapWidgetContainer(snapshot: TierTapHomeWidgetPreviewData.sample)
                .previewContext(WidgetPreviewContext(family: .systemSmall))
            TierTapRewardsGoalsEntryView(entry: .init(date: Date(), snapshot: TierTapHomeWidgetPreviewData.sample))
                .tierTapWidgetContainer(snapshot: TierTapHomeWidgetPreviewData.sample)
                .previewContext(WidgetPreviewContext(family: .systemMedium))
            TierTapRewardsGoalsEntryView(entry: .init(date: Date(), snapshot: TierTapHomeWidgetPreviewData.sample))
                .tierTapWidgetContainer(snapshot: TierTapHomeWidgetPreviewData.sample)
                .previewContext(WidgetPreviewContext(family: .systemLarge))
        }
    }
}
#endif
