import SwiftUI
import UIKit

private enum CalendarScope: String, CaseIterable {
    case month = "Month"
    case year = "Year"
}

struct CalendarMonthView: View {
    @EnvironmentObject private var store: HabitStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var monthAnchor: Date = Date()
    @State private var pickedDay: Date?
    @State private var calendarScope: CalendarScope = .month
    @State private var showingTargetStreakEditor = false
    @State private var shareImage: UIImage?
    @State private var showShareSheet = false
    @State private var isPreparingShareImage = false

    private var calendar: Calendar {
        var c = Calendar.current
        c.firstWeekday = 1
        return c
    }

    private var displayedYear: Int {
        calendar.component(.year, from: monthAnchor)
    }

    /// Slightly shrink the year-at-a-glance column so more months fit on screen (true “overview” scaling).
    private var yearOverviewScale: CGFloat {
        guard calendarScope == .year else { return 1 }
        return horizontalSizeClass == .compact ? 0.88 : 0.94
    }

    private var daysInCurrentMonth: [Date?] {
        daysInMonth(for: monthAnchor)
    }

    private func yearOverviewMonthScrollId(_ month: Int) -> String {
        "year-\(displayedYear)-month-\(month)"
    }

    /// Month to center in year view: this month when browsing the current year, otherwise mid-year.
    private var yearOverviewFocusedMonth: Int {
        let now = Date()
        let y = calendar.component(.year, from: now)
        if displayedYear == y {
            return calendar.component(.month, from: now)
        }
        return 6
    }

    private func scheduleYearOverviewScroll(proxy: ScrollViewProxy) {
        guard calendarScope == .year else { return }
        let id = yearOverviewMonthScrollId(yearOverviewFocusedMonth)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            withAnimation(.easeInOut(duration: 0.45)) {
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(spacing: 16) {
                        if calendarScope == .month {
                            HStack {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        shiftMonth(-1)
                                    }
                                } label: {
                                    Image(systemName: "chevron.left.circle.fill")
                                        .imageScale(.large)
                                }
                                .buttonStyle(HapticAnimatedButtonStyle(pressedScale: 0.9))
                                Spacer()
                                Text(monthTitle(for: monthAnchor))
                                    .font(.title2.weight(.semibold))
                                Spacer()
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        shiftMonth(1)
                                    }
                                } label: {
                                    Image(systemName: "chevron.right.circle.fill")
                                        .imageScale(.large)
                                }
                                .buttonStyle(HapticAnimatedButtonStyle(pressedScale: 0.9))
                            }
                            .padding(.horizontal)

                            weekdayHeader(compact: false)

                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                                ForEach(Array(daysInCurrentMonth.enumerated()), id: \.offset) { _, day in
                                    if let day {
                                        dayCell(day, compact: false)
                                    } else {
                                        Color.clear.frame(height: 56)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        } else {
                            yearNavigationBar
                                .padding(.horizontal)

                            VStack(spacing: 14) {
                                ForEach(1...12, id: \.self) { month in
                                    compactMonthBlock(month: month)
                                        .id(yearOverviewMonthScrollId(month))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .scaleEffect(yearOverviewScale, anchor: .center)
                            .padding(.horizontal)
                        }

                        streakCard
                            .padding(.top, 8)
                    }
                    .padding(.bottom, 24)
                }
                .onAppear {
                    scheduleYearOverviewScroll(proxy: scrollProxy)
                }
                .onChange(of: calendarScope) { _, newScope in
                    if newScope == .year {
                        scheduleYearOverviewScroll(proxy: scrollProxy)
                    }
                }
                .onChange(of: displayedYear) { _, _ in
                    scheduleYearOverviewScroll(proxy: scrollProxy)
                }
            }
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Scope", selection: $calendarScope) {
                        ForEach(CalendarScope.allCases, id: \.self) { scope in
                            Text(scope.rawValue).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 220)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if calendarScope == .month {
                        Menu {
                            ForEach(ScheduleShareOrientation.allCases, id: \.self) { orientation in
                                Button(orientation.menuTitle) {
                                    shareMonthCalendar(orientation: orientation)
                                }
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .symbolRenderingMode(.hierarchical)
                        }
                        .disabled(isPreparingShareImage)
                        .buttonStyle(HapticToolbarButtonStyle())
                    }
                }
            }
            .sheet(item: Binding(
                get: {
                    pickedDay.map { DaySelection(id: DayKey.string(for: $0, calendar: calendar), date: $0) }
                },
                set: { pickedDay = $0?.date }
            )) { selection in
                DayOutcomeSheet(date: selection.date) {
                    pickedDay = nil
                }
                .environmentObject(store)
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showingTargetStreakEditor) {
                TargetStreakEditorSheet(initialValue: store.targetStreak) { store.setTargetStreak($0) }
                    .presentationDetents([.height(240)])
            }
            .sheet(isPresented: $showShareSheet, onDismiss: { shareImage = nil }) {
                if let shareImage {
                    ActivityShareSheet(activityItems: [shareImage])
                }
            }
            .overlay {
                if isPreparingShareImage {
                    ZStack {
                        Color.black.opacity(0.2)
                            .ignoresSafeArea()
                        ProgressView("Preparing…")
                            .padding(20)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
        }
    }

    private func shareMonthCalendar(orientation: ScheduleShareOrientation) {
        guard calendarScope == .month, !isPreparingShareImage else { return }
        isPreparingShareImage = true
        Task { @MainActor in
            await Task.yield()
            let payload = CalendarMonthShare.payload(store: store, monthAnchor: monthAnchor, calendar: calendar)
            let image = CalendarMonthShare.renderImage(payload: payload, orientation: orientation)
            isPreparingShareImage = false
            guard let image else { return }
            HapticButton.lightImpact()
            shareImage = image
            showShareSheet = true
        }
    }

    private var streakCard: some View {
        let current = store.currentStreak(calendar: calendar)
        let target = store.targetStreak
        let targetMet = target > 0 && current >= target

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("Current Streak")
                    .foregroundStyle(.secondary)
                if targetMet {
                    Text("– met target")
                        .foregroundStyle(.green)
                }
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .center)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Spacer(minLength: 0)
                Text("\(current)")
                    .font(.system(size: 68, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
                Text("days")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textCase(.lowercase)
                Spacer(minLength: 0)
            }

            Divider()
                .opacity(0.45)

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Longest Streak")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("\(store.longestStreakEver)")
                        .font(.title.weight(.semibold))
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 6) {
                    Text("Target Streak")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(store.targetStreak > 0 ? "\(store.targetStreak)" : "—")
                            .font(.title.weight(.semibold))
                            .foregroundStyle(targetMet ? .green : .primary)
                            .monospacedDigit()
                        Button("Set") {
                            HapticButton.lightImpact()
                            showingTargetStreakEditor = true
                        }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.bordered)
                    }
                }
            }

            HStack {
                Spacer(minLength: 0)
                Button("Reset longest") {
                    HapticButton.mediumImpact()
                    withAnimation(.easeInOut(duration: 0.25)) {
                        store.resetLongestStreak()
                    }
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        }
        .padding(.horizontal)
    }

    private var yearNavigationBar: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    shiftYear(-1)
                }
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .imageScale(.large)
            }
            .buttonStyle(HapticAnimatedButtonStyle(pressedScale: 0.9))
            Spacer()
            Text("\(displayedYear)")
                .font(.title2.weight(.semibold))
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    shiftYear(1)
                }
            } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .imageScale(.large)
            }
            .buttonStyle(HapticAnimatedButtonStyle(pressedScale: 0.9))
        }
    }

    private func monthTitle(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "LLLL yyyy"
        return f.string(from: date)
    }

    @ViewBuilder
    private func weekdayHeader(compact: Bool) -> some View {
        let symbols = calendar.shortWeekdaySymbols
        let ord = (0..<7).map { i -> String in
            let idx = (i + calendar.firstWeekday - 1) % 7
            return symbols[idx]
        }
        HStack(spacing: 0) {
            ForEach(Array(ord.enumerated()), id: \.offset) { _, s in
                Text(compact ? String(s.prefix(1)).uppercased() : s.uppercased())
                    .font(compact ? .system(size: 9, weight: .bold) : .caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, compact ? 0 : 16)
    }

    private func daysInMonth(for anchor: Date) -> [Date?] {
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

    private func shiftMonth(_ delta: Int) {
        if let next = calendar.date(byAdding: .month, value: delta, to: monthAnchor) {
            monthAnchor = next
        }
    }

    private func shiftYear(_ delta: Int) {
        if let next = calendar.date(byAdding: .year, value: delta, to: monthAnchor) {
            monthAnchor = next
        }
    }

    @ViewBuilder
    private func dayCell(_ day: Date, compact: Bool) -> some View {
        let result = store.displayResult(on: day, calendar: calendar)
        let n = calendar.component(.day, from: day)
        let height: CGFloat = compact ? 30 : 56
        let corner: CGFloat = compact ? 6 : 12

        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                pickedDay = day
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))

                VStack(spacing: compact ? 2 : 4) {
                    Text("\(n)")
                        .font(compact ? .caption2.weight(.medium) : .subheadline.weight(.medium))
                    resultIcon(result, compact: compact)
                }
            }
            .frame(height: height)
        }
        .buttonStyle(HapticAnimatedButtonStyle(pressedScale: compact ? 0.92 : 0.94))
    }

    @ViewBuilder
    private func resultIcon(_ result: DayResult, compact: Bool) -> some View {
        switch result {
        case .won:
            Image(systemName: "checkmark")
                .font(compact ? .caption.weight(.bold) : .title2.weight(.bold))
                .foregroundStyle(.green)
        case .lost:
            Image(systemName: "xmark")
                .font(compact ? .caption.weight(.bold) : .title2.weight(.bold))
                .foregroundStyle(.red)
        case .unset:
            Image(systemName: "circle")
                .font(compact ? .system(size: 7) : .caption)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func compactMonthBlock(month: Int) -> some View {
        if let anchor = calendar.date(from: DateComponents(year: displayedYear, month: month, day: 1)) {
            VStack(alignment: .leading, spacing: 6) {
                Text(monthNameInYear(anchor))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                weekdayHeader(compact: true)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                    ForEach(Array(daysInMonth(for: anchor).enumerated()), id: \.offset) { _, day in
                        if let day {
                            dayCell(day, compact: true)
                        } else {
                            Color.clear.frame(height: 30)
                        }
                    }
                }
            }
        }
    }

    private func monthNameInYear(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "LLLL"
        return f.string(from: date)
    }
}

private struct TargetStreakEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let initialValue: Int
    var onSave: (Int) -> Void

    @State private var text: String

    init(initialValue: Int, onSave: @escaping (Int) -> Void) {
        self.initialValue = initialValue
        self.onSave = onSave
        _text = State(initialValue: initialValue > 0 ? "\(initialValue)" : "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Days", text: $text)
                        .keyboardType(.numberPad)
                } footer: {
                    Text("Use 0 to clear the target. Maximum 9999 days.")
                }
            }
            .navigationTitle("Target streak")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        HapticButton.lightImpact()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        let value = Int(trimmed) ?? 0
                        HapticButton.mediumImpact()
                        onSave(value)
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct DaySelection: Identifiable {
    let id: String
    let date: Date
}

private struct DayOutcomeSheet: View {
    @EnvironmentObject private var store: HabitStore
    let date: Date
    var onClose: () -> Void

    private var header: String {
        let f = DateFormatter()
        f.dateStyle = .full
        return f.string(from: date)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(header)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                Text("Mark whether you won this day. This overrides the automatic status from your checklist.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                HStack(spacing: 16) {
                    Button {
                        HapticButton.mediumImpact()
                        withAnimation(.easeInOut(duration: 0.22)) {
                            store.setManualResult(.won, on: date)
                        }
                    } label: {
                        Label("Yes, I won", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                    Button {
                        HapticButton.mediumImpact()
                        withAnimation(.easeInOut(duration: 0.22)) {
                            store.setManualResult(.lost, on: date)
                        }
                    } label: {
                        Label("No", systemImage: "xmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
                .padding(.horizontal)

                Button("Use automatic (clear my choice)") {
                    HapticButton.lightImpact()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        store.setManualResult(.unset, on: date)
                    }
                }
                .font(.subheadline)

                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        HapticButton.lightImpact()
                        onClose()
                    }
                }
            }
        }
    }
}
