import SwiftUI

struct HistoryDayAggregate {
    let sessionCount: Int
    let netValue: Int
}

struct HistoryActivityGridLayout {
    let bands: [[Date]]
    let monthLabelsPerBand: [Set<Int>]
    let cellSize: CGFloat
    /// Width of the week-column area (widest band); shorter bands center inside this.
    let weekAreaWidth: CGFloat
    /// Weekday labels plus week columns.
    let totalWidth: CGFloat
    let periodOffset: Int
    let periodStart: Date
    let periodEnd: Date
}

enum HistoryActivityGridEngine {
    static let cellGap: CGFloat = 2
    static let minCellSize: CGFloat = 10
    /// On-screen cells grow to fill width; export uses this cap on very wide cards.
    static let exportMaxCellSize: CGFloat = 18
    static let weekdayLabelWidth: CGFloat = 14
    static let rowLabelSpacing: CGFloat = 4
    static let monthHeaderHeight: CGFloat = 16
    static let bandCount = 1
    static let monthsPerWindow = 6
    /// Inset from each screen edge for the on-screen grid.
    static let horizontalScreenMargin: CGFloat = 14

    static func aggregates(
        sessions: [Session],
        metricMode: HistoryGridMetricMode,
        calendar: Calendar = .current
    ) -> [Date: HistoryDayAggregate] {
        var byDay: [Date: (sessions: Int, net: Int)] = [:]
        for session in sessions {
            let day = calendar.startOfDay(for: session.startTime)
            var entry = byDay[day] ?? (sessions: 0, net: 0)
            entry.sessions += 1
            if let contribution = metricMode.contribution(from: session) {
                entry.net += contribution
            }
            byDay[day] = entry
        }
        return byDay.mapValues { HistoryDayAggregate(sessionCount: $0.sessions, netValue: $0.net) }
    }

    static func layout(
        for availableWidth: CGFloat,
        periodOffset: Int = 0,
        calendar: Calendar = .current,
        forExport: Bool = false
    ) -> HistoryActivityGridLayout {
        let bounds = periodBounds(offset: periodOffset, calendar: calendar)
        let allWeekStarts = weekStarts(from: bounds.start, through: bounds.end, calendar: calendar)

        let weekAreaWidth = max(availableWidth - weekdayLabelWidth - rowLabelSpacing, 40)
        let weeksPerBand = max(1, Int(ceil(Double(allWeekStarts.count) / Double(bandCount))))

        guard !allWeekStarts.isEmpty else {
            let fallbackCell = minCellSize
            return HistoryActivityGridLayout(
                bands: [],
                monthLabelsPerBand: [],
                cellSize: fallbackCell,
                weekAreaWidth: weekAreaWidth,
                totalWidth: weekdayLabelWidth + rowLabelSpacing + weekAreaWidth,
                periodOffset: periodOffset,
                periodStart: bounds.start,
                periodEnd: bounds.end
            )
        }

        var bands: [[Date]] = []
        var monthLabelsPerBand: [Set<Int>] = []
        var sliceOffset = 0
        while sliceOffset < allWeekStarts.count {
            let end = min(sliceOffset + weeksPerBand, allWeekStarts.count)
            let slice = Array(allWeekStarts[sliceOffset..<end])
            bands.append(slice)
            monthLabelsPerBand.append(monthLabelWeekIndices(for: slice, calendar: calendar))
            sliceOffset = end
        }

        let maxWeeksInBand = max(bands.map(\.count).max() ?? 1, 1)
        let rawCellSize = (weekAreaWidth - CGFloat(maxWeeksInBand - 1) * cellGap) / CGFloat(maxWeeksInBand)
        let cellSize: CGFloat = {
            let filled = max(minCellSize, rawCellSize)
            if forExport {
                return min(exportMaxCellSize, filled)
            }
            return filled
        }()
        let fittedWeekAreaWidth = CGFloat(maxWeeksInBand) * cellSize + CGFloat(max(0, maxWeeksInBand - 1)) * cellGap
        let totalWidth = weekdayLabelWidth + rowLabelSpacing + fittedWeekAreaWidth

        return HistoryActivityGridLayout(
            bands: bands,
            monthLabelsPerBand: monthLabelsPerBand,
            cellSize: cellSize,
            weekAreaWidth: fittedWeekAreaWidth,
            totalWidth: totalWidth,
            periodOffset: periodOffset,
            periodStart: bounds.start,
            periodEnd: bounds.end
        )
    }

    static func gridContentHeight(cellSize: CGFloat) -> CGFloat {
        let bandSpacing: CGFloat = 10
        let bandHeight = monthHeaderHeight + 4 + 7 * (cellSize + cellGap) - cellGap
        return CGFloat(bandCount) * bandHeight + CGFloat(bandCount - 1) * bandSpacing
    }

    static func periodBounds(offset: Int, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let today = calendar.startOfDay(for: Date())
        let clampedOffset = max(0, offset)
        guard let periodEnd = calendar.date(byAdding: .month, value: -(clampedOffset * monthsPerWindow), to: today) else {
            return (today, today)
        }
        let periodStart = calendar.date(byAdding: .month, value: -monthsPerWindow, to: periodEnd) ?? periodEnd
        return (calendar.startOfDay(for: periodStart), calendar.startOfDay(for: periodEnd))
    }

    static func yearLabel(forPeriodOffset offset: Int, calendar: Calendar = .current) -> String {
        let bounds = periodBounds(offset: offset, calendar: calendar)
        let startYear = calendar.component(.year, from: bounds.start)
        let endYear = calendar.component(.year, from: bounds.end)
        if startYear == endYear {
            return "\(startYear)"
        }
        return "\(startYear) – \(endYear)"
    }

    static func monthRangeCaption(forPeriodOffset offset: Int, calendar: Calendar = .current) -> String {
        let bounds = periodBounds(offset: offset, calendar: calendar)
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return "\(formatter.string(from: bounds.start)) – \(formatter.string(from: bounds.end))"
    }

    static func weekStarts(from periodStart: Date, through periodEnd: Date, calendar: Calendar) -> [Date] {
        guard let firstWeek = startOfWeek(containing: periodStart, calendar: calendar),
              let lastWeek = startOfWeek(containing: periodEnd, calendar: calendar) else {
            return []
        }
        var weeks: [Date] = []
        var cursor = firstWeek
        while cursor <= lastWeek {
            weeks.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 7, to: cursor) else { break }
            cursor = next
        }
        return weeks
    }

    /// Usable width for the grid on the current device (screen width minus side margins).
    @MainActor
    static func preferredLayoutWidth() -> CGFloat {
        #if os(iOS)
        UIScreen.main.bounds.width - (horizontalScreenMargin * 2)
        #else
        390 - (horizontalScreenMargin * 2)
        #endif
    }

    static func cellFill(
        aggregate: HistoryDayAggregate?,
        maxSessions: Int,
        isFuture: Bool
    ) -> Color {
        if isFuture {
            return Color.white.opacity(0.04)
        }
        guard let aggregate, aggregate.sessionCount > 0 else {
            return Color.white.opacity(0.08)
        }
        let volume = opacityForSessionCount(aggregate.sessionCount, max: maxSessions)
        if aggregate.netValue > 0 {
            return Color.green.opacity(volume)
        }
        if aggregate.netValue < 0 {
            return Color.red.opacity(volume)
        }
        return Color.white.opacity(0.22 + volume * 0.2)
    }

    static func opacityForSessionCount(_ count: Int, max: Int) -> Double {
        let normalized = Double(count) / Double(Swift.max(max, 1))
        return 0.35 + normalized * 0.65
    }

    static func weekdaySymbols(calendar: Calendar = .current) -> [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return (0..<7).map { symbols[($0 + first) % 7] }
    }

    static func shortMonthSymbol(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter.string(from: date)
    }

    static func dateRangeCaption(sessions: [Session]) -> String? {
        guard !sessions.isEmpty,
              let first = sessions.map(\.startTime).min(),
              let last = sessions.map(\.startTime).max() else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return "\(formatter.string(from: first)) – \(formatter.string(from: last))"
    }

    private static func monthLabelWeekIndices(for weekStarts: [Date], calendar: Calendar) -> Set<Int> {
        var monthIndices = Set<Int>()
        var lastMonth: Int?
        for (index, weekStart) in weekStarts.enumerated() {
            let month = calendar.component(.month, from: weekStart)
            if lastMonth != month {
                monthIndices.insert(index)
                lastMonth = month
            }
        }
        return monthIndices
    }

    private static func startOfWeek(containing date: Date, calendar: Calendar) -> Date? {
        let weekday = calendar.component(.weekday, from: date)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: date))
    }
}

struct HistoryActivityGridBandsView: View {
    let layout: HistoryActivityGridLayout
    let aggregates: [Date: HistoryDayAggregate]
    var pressedDay: Date?
    var onDayPressChanged: ((Date?) -> Void)?
    let calendar: Calendar

    init(
        layout: HistoryActivityGridLayout,
        aggregates: [Date: HistoryDayAggregate],
        pressedDay: Date? = nil,
        onDayPressChanged: ((Date?) -> Void)? = nil,
        calendar: Calendar = .current
    ) {
        self.layout = layout
        self.aggregates = aggregates
        self.pressedDay = pressedDay
        self.onDayPressChanged = onDayPressChanged
        self.calendar = calendar
    }

    var body: some View {
        let maxSessions = aggregates.values.map(\.sessionCount).max() ?? 1
        VStack(alignment: .center, spacing: 10) {
            ForEach(Array(layout.bands.enumerated()), id: \.offset) { bandIndex, bandWeekStarts in
                bandGrid(
                    weekStarts: bandWeekStarts,
                    bandIndex: bandIndex,
                    maxSessions: maxSessions
                )
            }
        }
        .frame(width: layout.totalWidth)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func bandGrid(weekStarts: [Date], bandIndex: Int, maxSessions: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            monthHeaderRow(
                weekStarts: weekStarts,
                monthLabelWeekIndices: layout.monthLabelsPerBand[bandIndex],
                cellSize: layout.cellSize
            )
            HStack(alignment: .top, spacing: HistoryActivityGridEngine.rowLabelSpacing) {
                weekdayLabels(cellSize: layout.cellSize)
                weekColumns(weekStarts: weekStarts, maxSessions: maxSessions)
                    .frame(width: layout.weekAreaWidth, alignment: .center)
            }
        }
    }

    private func weekColumns(weekStarts: [Date], maxSessions: Int) -> some View {
        HStack(alignment: .top, spacing: HistoryActivityGridEngine.cellGap) {
            ForEach(weekStarts, id: \.self) { weekStart in
                VStack(spacing: HistoryActivityGridEngine.cellGap) {
                    ForEach(0..<7, id: \.self) { weekdayIndex in
                        let day = calendar.date(byAdding: .day, value: weekdayIndex, to: weekStart)!
                        dayCell(
                            day: day,
                            aggregate: aggregates[calendar.startOfDay(for: day)],
                            maxSessions: maxSessions,
                            cellSize: layout.cellSize
                        )
                    }
                }
            }
        }
    }

    private func monthHeaderRow(weekStarts: [Date], monthLabelWeekIndices: Set<Int>, cellSize: CGFloat) -> some View {
        let weekStride = cellSize + HistoryActivityGridEngine.cellGap
        let bandWeekAreaWidth = CGFloat(weekStarts.count) * cellSize
            + CGFloat(max(0, weekStarts.count - 1)) * HistoryActivityGridEngine.cellGap
        let labelOffset = (layout.weekAreaWidth - bandWeekAreaWidth) / 2

        return HStack(alignment: .top, spacing: HistoryActivityGridEngine.rowLabelSpacing) {
            Color.clear
                .frame(width: HistoryActivityGridEngine.weekdayLabelWidth, height: HistoryActivityGridEngine.monthHeaderHeight)
            ZStack(alignment: .topLeading) {
                Color.clear
                    .frame(width: layout.weekAreaWidth, height: HistoryActivityGridEngine.monthHeaderHeight)
                ForEach(Array(monthLabelWeekIndices).sorted(), id: \.self) { index in
                    if index < weekStarts.count {
                        Text(HistoryActivityGridEngine.shortMonthSymbol(for: weekStarts[index]))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.55))
                            .fixedSize(horizontal: true, vertical: false)
                            .offset(x: labelOffset + CGFloat(index) * weekStride)
                    }
                }
            }
            .frame(width: layout.weekAreaWidth, height: HistoryActivityGridEngine.monthHeaderHeight, alignment: .topLeading)
        }
    }

    private func weekdayLabels(cellSize: CGFloat) -> some View {
        VStack(spacing: HistoryActivityGridEngine.cellGap) {
            ForEach(HistoryActivityGridEngine.weekdaySymbols(calendar: calendar), id: \.self) { symbol in
                Text(symbol)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.45))
                    .frame(width: HistoryActivityGridEngine.weekdayLabelWidth, height: cellSize, alignment: .trailing)
            }
        }
    }

    private func dayCell(day: Date, aggregate: HistoryDayAggregate?, maxSessions: Int, cellSize: CGFloat) -> some View {
        let dayKey = calendar.startOfDay(for: day)
        let isFuture = dayKey > calendar.startOfDay(for: Date())
        let isPressed = pressedDay.map { calendar.isDate($0, inSameDayAs: dayKey) } ?? false
        let fill = HistoryActivityGridEngine.cellFill(aggregate: aggregate, maxSessions: maxSessions, isFuture: isFuture)

        return RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(fill)
            .overlay {
                if isPressed {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5)
                }
            }
            .frame(width: cellSize, height: cellSize)
            .modifier(DayPressGestureModifier(day: dayKey, onDayPressChanged: onDayPressChanged))
    }
}

private struct DayPressGestureModifier: ViewModifier {
    let day: Date
    let onDayPressChanged: ((Date?) -> Void)?

    func body(content: Content) -> some View {
        if onDayPressChanged != nil {
            content
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in onDayPressChanged?(day) }
                        .onEnded { _ in onDayPressChanged?(nil) }
                )
        } else {
            content
        }
    }
}

struct HistoryActivityGridShareCard: View {
    let sessions: [Session]
    let metricMode: HistoryGridMetricMode
    let gradient: LinearGradient
    let contentWidth: CGFloat
    var periodOffset: Int = 0

    private var innerWidth: CGFloat { contentWidth - 32 }
    private var layout: HistoryActivityGridLayout {
        HistoryActivityGridEngine.layout(for: innerWidth, periodOffset: periodOffset, forExport: true)
    }
    private var aggregates: [Date: HistoryDayAggregate] {
        HistoryActivityGridEngine.aggregates(sessions: sessions, metricMode: metricMode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TierTap Session Grid")
                        .font(.headline.bold())
                        .foregroundColor(.white)
                    Text(HistoryActivityGridEngine.yearLabel(forPeriodOffset: periodOffset))
                        .font(.subheadline.bold())
                        .foregroundColor(.white.opacity(0.9))
                    Text(HistoryActivityGridEngine.monthRangeCaption(forPeriodOffset: periodOffset))
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.72))
                }
                Spacer()
                Text(metricMode.sliderLabel)
                    .font(.caption.bold())
                    .foregroundColor(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.2))
                    .clipShape(Capsule())
            }

            HistoryActivityGridBandsView(layout: layout, aggregates: aggregates)

            HStack(spacing: 16) {
                legendSwatch(color: .green.opacity(0.85), label: "Net positive")
                legendSwatch(color: .red.opacity(0.85), label: "Net negative")
                Text("Darker = more sessions")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.55))
            }
        }
        .padding(16)
        .frame(width: contentWidth, alignment: .leading)
        .background(gradient)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }

    private func legendSwatch(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 12, height: 12)
            Text(label)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.7))
        }
    }

    static func exportHeight(for contentWidth: CGFloat, periodOffset: Int = 0) -> CGFloat {
        let layout = HistoryActivityGridEngine.layout(for: contentWidth - 32, periodOffset: periodOffset, forExport: true)
        return 16 + 52 + 14 + HistoryActivityGridEngine.gridContentHeight(cellSize: layout.cellSize) + 14 + 24 + 16
    }
}

#if os(iOS)
@MainActor
enum HistoryActivityGridShareExporter {
    static func renderImage(
        sessions: [Session],
        metricMode: HistoryGridMetricMode,
        gradient: LinearGradient,
        periodOffset: Int = 0
    ) -> UIImage? {
        let width = ShareImageExportQuality.wideCardWidthPoints
        let height = HistoryActivityGridShareCard.exportHeight(for: width, periodOffset: periodOffset)
        let card = HistoryActivityGridShareCard(
            sessions: sessions,
            metricMode: metricMode,
            gradient: gradient,
            contentWidth: width,
            periodOffset: periodOffset
        )
        let wrapped = card.frame(width: width, height: height)

        if #available(iOS 16.0, *) {
            let renderer = ImageRenderer(content: wrapped)
            renderer.scale = ShareImageExportQuality.imageRendererScale
            renderer.proposedSize = ProposedViewSize(width: width, height: height)
            return renderer.uiImage
        }

        let controller = UIHostingController(rootView: wrapped)
        let size = CGSize(width: width, height: height)
        controller.view.bounds = CGRect(origin: .zero, size: size)
        controller.view.backgroundColor = .clear
        let bitmapRenderer = UIGraphicsImageRenderer(size: size)
        return bitmapRenderer.image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
    }
}
#endif
