import SwiftUI

struct SessionCalendarView: View {
    let sessions: [Session]
    @Binding var selectedDate: Date?

    @State private var displayedMonthStart: Date = SessionCalendarView.startOfMonth(for: Date())

    private let calendar = Calendar.current

    private var countsByDay: [Date: Int] {
        var dict: [Date: Int] = [:]
        for s in sessions {
            let day = calendar.startOfDay(for: s.startTime)
            dict[day, default: 0] += 1
        }
        return dict
    }

    private var monthStart: Date {
        displayedMonthStart
    }

    private var currentMonthStart: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
    }

    private var canGoToNextMonth: Bool {
        monthStart < currentMonthStart
    }

    private var dayCells: [DayCell] {
        guard let range = calendar.range(of: .day, in: .month, for: monthStart) else { return [] }

        let firstWeekdayOfMonth = calendar.component(.weekday, from: monthStart)
        let weekdayOffset = (firstWeekdayOfMonth - calendar.firstWeekday + 7) % 7

        var cells: [DayCell] = []
        for _ in 0..<weekdayOffset {
            cells.append(DayCell(date: nil))
        }
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) {
                cells.append(DayCell(date: date))
            }
        }
        return cells
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: monthStart)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    shiftDisplayedMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.9))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Previous month")

                Text(monthTitle)
                    .font(.caption.bold())
                    .foregroundColor(.white.opacity(0.85))
                    .frame(maxWidth: .infinity)

                Button {
                    shiftDisplayedMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.title3)
                        .foregroundColor(canGoToNextMonth ? Color.white.opacity(0.9) : Color.white.opacity(0.25))
                }
                .buttonStyle(.plain)
                .disabled(!canGoToNextMonth)
                .accessibilityLabel("Next month")
            }

            let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

            HStack {
                ForEach(calendar.shortWeekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(dayCells) { cell in
                    if let date = cell.date {
                        let day = calendar.component(.day, from: date)
                        let dayKey = calendar.startOfDay(for: date)
                        let count = countsByDay[dayKey] ?? 0
                        let isSelected = selectedDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false

                        Button {
                            selectedDate = date
                        } label: {
                            VStack(spacing: 2) {
                                Text("\(day)")
                                    .font(.caption2)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                if count > 0 {
                                    Circle()
                                        .fill(Color.green.opacity(isSelected ? 1.0 : 0.8))
                                        .frame(width: 4, height: 4)
                                } else {
                                    Circle()
                                        .fill(Color.clear)
                                        .frame(width: 4, height: 4)
                                }
                            }
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, minHeight: 32)
                            .background(backgroundColor(for: count, selected: isSelected))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                }
            }
        }
        .onAppear {
            if let selectedDate {
                displayedMonthStart = Self.startOfMonth(for: selectedDate)
            }
        }
        .onChange(of: selectedDate) { newValue in
            if let newValue {
                displayedMonthStart = Self.startOfMonth(for: newValue)
            }
        }
    }

    private func shiftDisplayedMonth(by delta: Int) {
        if let next = calendar.date(byAdding: .month, value: delta, to: monthStart) {
            displayedMonthStart = next
        }
    }

    private static func startOfMonth(for date: Date) -> Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: date)) ?? date
    }

    private func backgroundColor(for count: Int, selected: Bool) -> Color {
        if selected {
            return Color.green.opacity(0.7)
        }
        switch count {
        case 0:
            return Color.clear
        case 1:
            return Color.green.opacity(0.25)
        case 2...3:
            return Color.green.opacity(0.4)
        default:
            return Color.green.opacity(0.6)
        }
    }

    private struct DayCell: Identifiable {
        let id = UUID()
        let date: Date?
    }
}

