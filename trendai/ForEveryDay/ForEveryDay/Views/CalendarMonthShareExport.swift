import SwiftUI
import UIKit

struct CalendarMonthSharePayload {
    let monthTitle: String
    let weekdayLabels: [String]
    let gridCells: [CalendarMonthShareGridCell]
    let currentStreak: Int
    let longestStreak: Int
    let targetStreak: Int
}

enum CalendarMonthShareGridCell: Equatable {
    case padding
    case day(dayOfMonth: Int, result: DayResult)
}

// MARK: - Card

private struct CalendarMonthShareCard: View {
    let payload: CalendarMonthSharePayload
    let orientation: ScheduleShareOrientation

    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        Group {
            switch orientation {
            case .vertical:
                verticalLayout
            case .horizontal:
                horizontalLayout
            }
        }
    }

    private var verticalLayout: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            weekdayRow
            monthGrid(cellHeight: 46, corner: 10, iconSize: .title3)
            streakBlock
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var horizontalLayout: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 16) {
                header
                weekdayRow
                monthGrid(cellHeight: 44, corner: 9, iconSize: .body)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 14) {
                legend
                streakBlock
            }
            .frame(width: 200, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("For Every Day")
                .font(.title2.bold())
                .foregroundStyle(.primary)
            Text(payload.monthTitle)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(payload.weekdayLabels.enumerated()), id: \.offset) { _, label in
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func monthGrid(cellHeight: CGFloat, corner: CGFloat, iconSize: Font) -> some View {
        LazyVGrid(columns: gridColumns, spacing: 6) {
            ForEach(Array(payload.gridCells.enumerated()), id: \.offset) { _, cell in
                switch cell {
                case .padding:
                    Color.clear.frame(height: cellHeight)
                case .day(let day, let result):
                    exportDayCell(day: day, result: result, height: cellHeight, corner: corner, iconFont: iconSize)
                }
            }
        }
    }

    private func exportDayCell(day: Int, result: DayResult, height: CGFloat, corner: CGFloat, iconFont: Font) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
            VStack(spacing: 4) {
                Text("\(day)")
                    .font(.subheadline.weight(.medium))
                resultIcon(result, font: iconFont)
            }
        }
        .frame(height: height)
    }

    @ViewBuilder
    private func resultIcon(_ result: DayResult, font: Font) -> some View {
        switch result {
        case .won:
            Image(systemName: "checkmark")
                .font(font.weight(.bold))
                .foregroundStyle(.green)
        case .lost:
            Image(systemName: "xmark")
                .font(font.weight(.bold))
                .foregroundStyle(.red)
        case .unset:
            Image(systemName: "circle")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Key")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            legendRow("Won", systemImage: "checkmark", color: .green)
            legendRow("Lost", systemImage: "xmark", color: .red)
            legendRow("Open / future", systemImage: "circle", color: Color.secondary)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.tertiarySystemFill))
        }
    }

    private func legendRow(_ title: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 18, alignment: .center)
            Text(title)
                .font(.caption)
                .foregroundStyle(.primary)
        }
    }

    private var streakBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Streaks")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text("Current: \(payload.currentStreak) days")
                .font(.subheadline.weight(.medium))
            Text("Longest: \(payload.longestStreak) days")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(payload.targetStreak > 0 ? "Target: \(payload.targetStreak) days" : "Target: —")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        }
    }
}

// MARK: - Renderer + payload builder

enum CalendarMonthShare {
    @MainActor
    static func renderImage(payload: CalendarMonthSharePayload, orientation: ScheduleShareOrientation) -> UIImage? {
        let content = CalendarMonthShareCard(payload: payload, orientation: orientation)
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Color(.systemBackground))

        let renderer = ImageRenderer(content: content)
        renderer.scale = UIScreen.main.scale
        switch orientation {
        case .vertical:
            renderer.proposedSize = ProposedViewSize(width: 390, height: nil)
        case .horizontal:
            renderer.proposedSize = ProposedViewSize(width: 780, height: nil)
        }
        return renderer.uiImage
    }

    @MainActor
    static func payload(store: HabitStore, monthAnchor: Date, calendar: Calendar) -> CalendarMonthSharePayload {
        let days = daysInMonthGrid(anchor: monthAnchor, calendar: calendar)
        let cells: [CalendarMonthShareGridCell] = days.map { date in
            guard let date else { return .padding }
            let d = calendar.component(.day, from: date)
            let r = store.displayResult(on: date, calendar: calendar)
            return .day(dayOfMonth: d, result: r)
        }

        let monthTitle: String = {
            let f = DateFormatter()
            f.dateFormat = "LLLL yyyy"
            return f.string(from: monthAnchor)
        }()

        let symbols = calendar.shortWeekdaySymbols
        let weekdayLabels = (0..<7).map { i -> String in
            let idx = (i + calendar.firstWeekday - 1) % 7
            return symbols[idx].uppercased()
        }

        return CalendarMonthSharePayload(
            monthTitle: monthTitle,
            weekdayLabels: weekdayLabels,
            gridCells: cells,
            currentStreak: store.currentStreak(calendar: calendar),
            longestStreak: store.longestStreakEver,
            targetStreak: store.targetStreak
        )
    }

    private static func daysInMonthGrid(anchor: Date, calendar: Calendar) -> [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: anchor),
              let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: anchor))
        else { return [] }

        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7

        var cells: [Date?] = Array(repeating: nil, count: leading)
        for d in range {
            var c = calendar.dateComponents([.year, .month], from: monthStart)
            c.day = d
            cells.append(calendar.date(from: c))
        }
        while cells.count % 7 != 0 {
            cells.append(nil)
        }
        return cells
    }
}
