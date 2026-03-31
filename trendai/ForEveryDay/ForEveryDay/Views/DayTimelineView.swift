import SwiftUI
import UIKit

/// Horizontal timeline from user "day start" to "day end" with markers for scheduled times, plus unscheduled tasks.
struct DayTimelineView: View {
    let date: Date
    @ObservedObject var store: HabitStore
    /// When set, shows a control to open a vertical list timeline (e.g. sheet). Omit when vertical is already on screen.
    var onOpenVertical: (() -> Void)?
    @Environment(\.calendar) private var calendar

    private var tasksWithReminders: [(HabitTask, Date)] {
        store.state.tasksWithReminders(on: date, calendar: calendar)
    }

    private var unscheduledTasks: [HabitTask] {
        store.state.unscheduledTasks(on: date, calendar: calendar)
    }

    private var dayTasks: [HabitTask] {
        store.state.tasksForCalendarDay(date, calendar: calendar)
    }

    private var hasTimelineContent: Bool {
        !tasksWithReminders.isEmpty || !unscheduledTasks.isEmpty
    }

    private var hasScheduledTimeOutsideWindow: Bool {
        dayTasks.contains { task in
            guard let st = task.scheduledTime,
                  let at = st.date(on: date, calendar: calendar) else { return false }
            guard let winStart = store.state.dayStart.date(on: date, calendar: calendar),
                  let winEnd = store.state.dayEnd.date(on: date, calendar: calendar),
                  winEnd > winStart else { return true }
            return at < winStart || at > winEnd
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer(minLength: 0)
                if hasTimelineContent, let onOpenVertical {
                    Button {
                        onOpenVertical()
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(HapticAnimatedButtonStyle(pressedScale: 0.9))
                    .accessibilityLabel("Open vertical timeline")
                }
            }

            if let ws = winStartForLayout, let we = winEndForLayout, we > ws {
                GeometryReader { geo in
                    let w = geo.size.width
                    let t0 = ws.timeIntervalSince1970
                    let t1 = we.timeIntervalSince1970
                    let layouts = Self.timelineMarkerLayouts(
                        tasksWithReminders: tasksWithReminders,
                        width: w,
                        t0: t0,
                        t1: t1
                    )
                    let (trackY, timelineHeight) = layouts.isEmpty
                        ? (12 as CGFloat, 24 as CGFloat)
                        : Self.timelineTrackMetrics(maxLane: layouts.map(\.lane).max() ?? 0)

                    ZStack(alignment: .topLeading) {
                        Capsule()
                            .fill(Color(.separator))
                            .frame(height: 6)
                            .position(x: w / 2, y: trackY)

                        ForEach(layouts, id: \.task.id) { layout in
                            markerView(task: layout.task, labelOffsetY: layout.labelOffsetY)
                                .position(x: layout.centerX, y: trackY)
                        }
                    }
                    .frame(height: timelineHeight, alignment: .top)
                }
                .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Text(store.state.dayStart.displayString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(store.state.dayEnd.displayString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Set a valid day window (start before end) to see scheduled times on the track.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            unscheduledBand

            if tasksWithReminders.isEmpty, hasScheduledTimeOutsideWindow {
                Text("Some scheduled times fall outside your day window—they only appear once you adjust the window.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private var winStartForLayout: Date? {
        store.state.dayStart.date(on: date, calendar: calendar)
    }

    private var winEndForLayout: Date? {
        store.state.dayEnd.date(on: date, calendar: calendar)
    }

    @ViewBuilder
    private var unscheduledBand: some View {
        if !unscheduledTasks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "tray")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Unscheduled")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(unscheduledTasks) { task in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "circle.dashed")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            if let data = task.attachmentImageData, let ui = UIImage(data: data) {
                                Image(uiImage: ui)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 28, height: 28)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            } else if let sym = task.resolvedSystemSymbolName {
                                Image(systemName: sym)
                                    .font(.caption)
                                    .symbolRenderingMode(.hierarchical)
                            } else if let e = task.iconEmoji, !e.isEmpty {
                                Text(e)
                                    .font(.caption)
                            }
                            Text(task.title)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
            }
        }
    }

    private func markerView(task: HabitTask, labelOffsetY: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 14, height: 14)
            markerLabel(task: task)
                .offset(y: labelOffsetY)
        }
        .frame(width: 92, height: 1)
    }

    @ViewBuilder
    private func markerLabel(task: HabitTask) -> some View {
        if let sym = task.resolvedSystemSymbolName {
            VStack(spacing: 2) {
                Image(systemName: sym)
                    .font(.caption2)
                    .symbolRenderingMode(.hierarchical)
                Text(task.title)
                    .font(.caption2)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 88, alignment: .center)
            .minimumScaleFactor(0.85)
        } else {
            Text(task.timelineTitleDisplay)
                .font(.caption2)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 88, alignment: .center)
                .minimumScaleFactor(0.85)
        }
    }

    // MARK: - Horizontal label stacking

    private struct TimelineMarkerLayout: Identifiable {
        var id: HabitTask.ID { task.id }
        let task: HabitTask
        let centerX: CGFloat
        let labelOffsetY: CGFloat
        let lane: Int
    }

    /// Label column half-width must match `markerView` outer frame (92pt) / 2.
    private static let labelHalfWidth: CGFloat = 46
    private static let labelStackBase: CGFloat = 36
    private static let labelStackStep: CGFloat = 18
    private static let textVerticalAllowance: CGFloat = 34
    private static let maxLanes = 12

    private static func labelOffsetY(forLane lane: Int) -> CGFloat {
        let sign: CGFloat = lane % 2 == 0 ? -1 : 1
        let tier = lane / 2
        return sign * (labelStackBase + CGFloat(tier) * labelStackStep)
    }

    /// Places markers so labels that would overlap horizontally use alternating vertical lanes.
    private static func timelineMarkerLayouts(
        tasksWithReminders: [(HabitTask, Date)],
        width w: CGFloat,
        t0: TimeInterval,
        t1: TimeInterval
    ) -> [TimelineMarkerLayout] {
        guard w > 0, t1 > t0, !tasksWithReminders.isEmpty else { return [] }

        var items: [(task: HabitTask, at: Date, centerX: CGFloat)] = tasksWithReminders.map { pair in
            let (task, at) = pair
            let p = (at.timeIntervalSince1970 - t0) / (t1 - t0)
            let cx = CGFloat(p) * w
            let clamped = max(labelHalfWidth, min(w - labelHalfWidth, cx))
            return (task, at, clamped)
        }
        items.sort { $0.centerX < $1.centerX }

        var laneIntervals: [[ClosedRange<CGFloat>]] = Array(repeating: [], count: maxLanes)

        return items.map { item in
            let range = (item.centerX - labelHalfWidth) ... (item.centerX + labelHalfWidth)
            var lane = maxLanes - 1
            for l in 0..<maxLanes {
                let conflicts = laneIntervals[l].contains { rangesOverlap($0, range) }
                if !conflicts {
                    lane = l
                    break
                }
            }
            laneIntervals[lane].append(range)

            return TimelineMarkerLayout(
                task: item.task,
                centerX: item.centerX,
                labelOffsetY: labelOffsetY(forLane: lane),
                lane: lane
            )
        }
    }

    private static func rangesOverlap(_ a: ClosedRange<CGFloat>, _ b: ClosedRange<CGFloat>) -> Bool {
        a.lowerBound <= b.upperBound && b.lowerBound <= a.upperBound
    }

    /// Vertical space for track and staggered labels. `maxLane` is the highest lane index used.
    private static func timelineTrackMetrics(maxLane: Int) -> (trackY: CGFloat, height: CGFloat) {
        let maxMagnitude = labelStackBase + CGFloat(maxLane / 2) * labelStackStep + textVerticalAllowance
        let trackY = maxMagnitude
        let height = trackY + maxMagnitude + 8
        return (trackY, max(height, 72))
    }
}

// MARK: - Vertical timeline

/// Vertical list timeline for the day: unscheduled tray items and scheduled times.
struct VerticalDayTimelineContent: View {
    let date: Date
    @ObservedObject var store: HabitStore
    @Environment(\.calendar) private var calendar
    @State private var fullScreenTaskImage: FullScreenTaskImageItem?

    private var timedItems: [(HabitTask, Date)] {
        store.state.tasksWithReminders(on: date, calendar: calendar)
    }

    private var unscheduledTasks: [HabitTask] {
        store.state.unscheduledTasks(on: date, calendar: calendar)
    }

    private var hasAnyRows: Bool {
        !timedItems.isEmpty || !unscheduledTasks.isEmpty
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        Group {
            if !hasAnyRows {
                ContentUnavailableView(
                    "Nothing on this timeline",
                    systemImage: "calendar.day.timeline.left",
                    description: Text("Add tasks with a time of day, a reminder, both, or neither.")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if !unscheduledTasks.isEmpty {
                            sectionHeader("Unscheduled", systemImage: "tray")
                            ForEach(Array(unscheduledTasks.enumerated()), id: \.element.id) { idx, task in
                                let isLastUnscheduled = idx == unscheduledTasks.count - 1
                                unscheduledRow(
                                    task: task,
                                    isCompleted: store.isCompleted(taskId: task.id, on: date, calendar: calendar),
                                    showConnectorBelow: !isLastUnscheduled
                                )
                            }
                        }

                        if !unscheduledTasks.isEmpty && !timedItems.isEmpty {
                            Divider()
                                .padding(.vertical, 16)
                        }

                        if !timedItems.isEmpty {
                            sectionHeader("Scheduled", systemImage: "clock")
                            ForEach(Array(timedItems.enumerated()), id: \.element.0.id) { idx, pair in
                                let (task, at) = pair
                                timedRow(
                                    time: Self.timeFormatter.string(from: at),
                                    task: task,
                                    isCompleted: store.isCompleted(taskId: task.id, on: date, calendar: calendar),
                                    isLast: idx == timedItems.count - 1
                                )
                            }
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fullScreenCover(item: $fullScreenTaskImage) { item in
            TaskAttachmentFullScreenView(image: item.image, title: item.title)
        }
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .tracking(0.6)
        }
        .padding(.bottom, 10)
    }

    private func unscheduledRow(task: HabitTask, isCompleted: Bool, showConnectorBelow: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("—")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 76, alignment: .trailing)

            VStack(spacing: 0) {
                Image(systemName: "circle.dashed")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(width: 14, height: 14)
                if showConnectorBelow {
                    Rectangle()
                        .fill(Color(.tertiarySystemFill))
                        .frame(width: 2, height: 28)
                }
            }

            titleRow(task: task, isCompleted: isCompleted)
                .padding(.bottom, showConnectorBelow ? 24 : 8)
        }
    }

    private func timedRow(time: String, task: HabitTask, isCompleted: Bool, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(time)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .trailing)

            VStack(spacing: 0) {
                Circle()
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .background(Circle().fill(Color(.systemBackground)))
                    .frame(width: 14, height: 14)
                if !isLast {
                    Rectangle()
                        .fill(Color(.tertiarySystemFill))
                        .frame(width: 2, height: 40)
                }
            }

            titleRow(task: task, isCompleted: isCompleted)
                .padding(.bottom, isLast ? 8 : 28)
        }
    }

    private func titleRow(task: HabitTask, isCompleted: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            TaskLeadingAttachmentView(task: task) {
                guard let data = task.attachmentImageData, let ui = UIImage(data: data) else { return }
                fullScreenTaskImage = FullScreenTaskImageItem(id: task.id, image: ui, title: task.title)
            }

            Text(task.title)
                .font(.body)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.body)
                .foregroundStyle(isCompleted ? .green : .secondary)
                .accessibilityLabel(isCompleted ? "Completed" : "Not completed")
        }
    }
}
