import Foundation
import SwiftUI

@MainActor
final class HabitStore: ObservableObject {
    @Published private(set) var state: PersistedState {
        didSet { save() }
    }

    /// Increments when `currentStreak` newly meets or exceeds `targetStreak` (for UI celebration).
    @Published private(set) var targetStreakCelebrationTick: Int = 0

    private let io = PersistenceIO()
    private let reminders = ReminderScheduler.shared

    init() {
        reminders.configure()
        if var loaded = io.load() {
            loaded.migrateLegacyTaskSnapshotsIfNeeded()
            self.state = loaded
        } else {
            self.state = .empty
        }
        reminders.scheduleReminders(for: state.tasks)
    }

    private func save() {
        io.save(state)
        reminders.scheduleReminders(for: state.tasks)
    }

    private func commit(_ update: (inout PersistedState) -> Void, updateLongestStreak: Bool = true) {
        let cal = Calendar.current
        let beforeCurrent = state.currentStreak(calendar: cal)
        let beforeTarget = state.targetStreak
        let beforeMet = beforeTarget > 0 && beforeCurrent >= beforeTarget

        var next = state
        update(&next)
        if updateLongestStreak {
            let cur = next.currentStreak(calendar: cal)
            next.longestStreakEver = max(next.longestStreakEver, cur)
        }
        state = next

        let afterCurrent = state.currentStreak(calendar: cal)
        let afterTarget = state.targetStreak
        let afterMet = afterTarget > 0 && afterCurrent >= afterTarget
        if afterMet && !beforeMet {
            targetStreakCelebrationTick += 1
        }
    }

    func resetLongestStreak() {
        commit({ $0.longestStreakEver = 0 }, updateLongestStreak: false)
    }

    func currentStreak(calendar: Calendar = .current) -> Int {
        state.currentStreak(calendar: calendar)
    }

    var longestStreakEver: Int { state.longestStreakEver }

    var targetStreak: Int { state.targetStreak }

    /// Persist goal streak (0 = none). Clamped to 0…9999.
    func setTargetStreak(_ value: Int) {
        let clamped = min(max(0, value), 9999)
        commit({ $0.targetStreak = clamped }, updateLongestStreak: false)
    }

    func requestNotificationPermission() {
        Task {
            _ = await reminders.requestAuthorization()
            reminders.scheduleReminders(for: state.tasks)
        }
    }

    // MARK: - Day window

    var dayStartBinding: Binding<TimeOfDay> {
        Binding(
            get: { self.state.dayStart },
            set: { newValue in self.commit { $0.dayStart = newValue } }
        )
    }

    var dayEndBinding: Binding<TimeOfDay> {
        Binding(
            get: { self.state.dayEnd },
            set: { newValue in self.commit { $0.dayEnd = newValue } }
        )
    }

    // MARK: - Tasks

    func tasksForCalendarDay(_ date: Date, calendar: Calendar = .current) -> [HabitTask] {
        state.tasksForCalendarDay(date, calendar: calendar)
    }

    func intentionsForCalendarDay(_ date: Date, calendar: Calendar = .current) -> [HabitTask] {
        state.intentionsForCalendarDay(date, calendar: calendar)
    }

    /// When opening a past day in the checklist, freeze that day’s template to the live list once (if not already frozen).
    func ensureSnapshotWhenBrowsingPastDay(_ date: Date, calendar: Calendar = .current) {
        let todayStart = calendar.startOfDay(for: Date())
        let dayStart = calendar.startOfDay(for: date)
        guard dayStart < todayStart else { return }
        let key = DayKey.string(for: date, calendar: calendar)
        let needsTasks = state.taskListSnapshots[key] == nil
        let needsIntentions = state.intentionListSnapshots[key] == nil
        guard needsTasks || needsIntentions else { return }
        commit { s in
            if s.taskListSnapshots[key] == nil {
                s.taskListSnapshots[key] = s.tasks.map { $0 }
            }
            if s.intentionListSnapshots[key] == nil {
                s.intentionListSnapshots[key] = s.intentions.map { $0 }
            }
        }
    }

    func addTask(
        title: String,
        scheduledTime: TimeOfDay?,
        reminder: TimeOfDay?,
        iconEmoji: String? = nil,
        systemSymbolName: String? = nil,
        attachmentImageData: Data? = nil
    ) {
        commit { s in
            s.freezeTaskListSnapshotsForPastDaysBeforeTemplateChange(calendar: .current)
            let nextIndex = (s.tasks.map(\.sortIndex).max() ?? -1) + 1
            let task = HabitTask(
                title: title,
                sortIndex: nextIndex,
                iconEmoji: iconEmoji,
                systemSymbolName: systemSymbolName,
                attachmentImageData: attachmentImageData,
                scheduledTime: scheduledTime,
                reminder: reminder
            )
            s.tasks.append(task)
            s.tasks.sort { $0.sortIndex < $1.sortIndex }
        }
    }

    func updateTask(_ task: HabitTask) {
        commit { s in
            s.freezeTaskListSnapshotsForPastDaysBeforeTemplateChange(calendar: .current)
            guard let i = s.tasks.firstIndex(where: { $0.id == task.id }) else { return }
            s.tasks[i] = task
            s.tasks.sort { $0.sortIndex < $1.sortIndex }
        }
    }

    func deleteTasks(at offsets: IndexSet) {
        commit { s in
            s.freezeTaskListSnapshotsForPastDaysBeforeTemplateChange(calendar: .current)
            let cal = Calendar.current
            let todayKey = DayKey.string(for: Date(), calendar: cal)
            let ids = offsets.map { s.tasks[$0].id }
            s.tasks.remove(atOffsets: offsets)
            for id in ids {
                for key in s.completionsByDay.keys where key >= todayKey {
                    s.completionsByDay[key]?.removeAll { $0 == id }
                    if s.completionsByDay[key]?.isEmpty == true {
                        s.completionsByDay[key] = nil
                    }
                }
            }
        }
    }

    func deleteTask(_ task: HabitTask) {
        if let idx = state.tasks.firstIndex(of: task) {
            deleteTasks(at: IndexSet(integer: idx))
        }
    }

    // MARK: - Intentions

    func addIntention(
        title: String,
        iconEmoji: String? = nil,
        systemSymbolName: String? = nil,
        attachmentImageData: Data? = nil
    ) {
        commit { s in
            s.freezeTaskListSnapshotsForPastDaysBeforeTemplateChange(calendar: .current)
            let nextIndex = (s.intentions.map(\.sortIndex).max() ?? -1) + 1
            let row = HabitTask(
                title: title,
                sortIndex: nextIndex,
                iconEmoji: iconEmoji,
                systemSymbolName: systemSymbolName,
                attachmentImageData: attachmentImageData,
                scheduledTime: nil,
                reminder: nil
            )
            s.intentions.append(row)
            s.intentions.sort { $0.sortIndex < $1.sortIndex }
        }
    }

    func updateIntention(_ intention: HabitTask) {
        commit { s in
            s.freezeTaskListSnapshotsForPastDaysBeforeTemplateChange(calendar: .current)
            guard let i = s.intentions.firstIndex(where: { $0.id == intention.id }) else { return }
            s.intentions[i] = intention
            s.intentions.sort { $0.sortIndex < $1.sortIndex }
        }
    }

    func deleteIntentions(at offsets: IndexSet) {
        commit { s in
            s.freezeTaskListSnapshotsForPastDaysBeforeTemplateChange(calendar: .current)
            let cal = Calendar.current
            let todayKey = DayKey.string(for: Date(), calendar: cal)
            let ids = offsets.map { s.intentions[$0].id }
            s.intentions.remove(atOffsets: offsets)
            for id in ids {
                for key in s.completionsByDay.keys where key >= todayKey {
                    s.completionsByDay[key]?.removeAll { $0 == id }
                    if s.completionsByDay[key]?.isEmpty == true {
                        s.completionsByDay[key] = nil
                    }
                }
            }
        }
    }

    func deleteIntention(_ intention: HabitTask) {
        if let idx = state.intentions.firstIndex(of: intention) {
            deleteIntentions(at: IndexSet(integer: idx))
        }
    }

    // MARK: - Completions

    func isCompleted(taskId: UUID, on date: Date, calendar: Calendar = .current) -> Bool {
        let key = DayKey.string(for: date, calendar: calendar)
        return state.completionsByDay[key, default: []].contains(taskId)
    }

    func toggleCompleted(taskId: UUID, on date: Date, calendar: Calendar = .current) {
        let key = DayKey.string(for: date, calendar: calendar)
        commit { s in
            var list = s.completionsByDay[key, default: []]
            if let i = list.firstIndex(of: taskId) {
                list.remove(at: i)
            } else {
                list.append(taskId)
            }
            s.completionsByDay[key] = list.isEmpty ? nil : list
        }
    }

    func allTasksCompleted(on date: Date, calendar: Calendar = .current) -> Bool {
        state.allTasksCompleted(on: date, calendar: calendar)
    }

    /// Calendar cell: explicit Yes/No overrides; otherwise tasks + schedule determine appearance.
    func displayResult(on date: Date, calendar: Calendar = .current) -> DayResult {
        state.displayResult(on: date, calendar: calendar)
    }

    /// Snapshot for exporting / sharing the checklist and schedule for one calendar day.
    func dailyScheduleSharePayload(for date: Date, calendar: Calendar = .current) -> DailyScheduleSharePayload {
        let key = DayKey.string(for: date, calendar: calendar)
        let completedIds = Set(state.completionsByDay[key, default: []])
        let timedPairs = state.tasksWithReminders(on: date, calendar: calendar)
        let unscheduled = state.unscheduledTasks(on: date, calendar: calendar)
        let intentions = intentionsForCalendarDay(date, calendar: calendar)
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        timeFormatter.dateStyle = .none
        let scheduledRows = timedPairs.map { pair in
            DailyScheduleSharePayload.ScheduledRow(
                taskId: pair.0.id,
                time: timeFormatter.string(from: pair.1),
                title: pair.0.title
            )
        }
        let unscheduledRows = unscheduled.map { task in
            DailyScheduleSharePayload.UnscheduledRow(taskId: task.id, title: task.title)
        }
        let intentionRows = intentions.map { row in
            DailyScheduleSharePayload.IntentionRow(id: row.id, title: row.title)
        }
        return DailyScheduleSharePayload(
            date: date,
            dayStart: state.dayStart,
            dayEnd: state.dayEnd,
            completedTaskIds: completedIds,
            scheduledRows: scheduledRows,
            unscheduledRows: unscheduledRows,
            intentionRows: intentionRows
        )
    }

    func manualResult(on date: Date, calendar: Calendar = .current) -> DayResult {
        let key = DayKey.string(for: date, calendar: calendar)
        return state.dayResults[key, default: .unset]
    }

    func setManualResult(_ result: DayResult, on date: Date, calendar: Calendar = .current) {
        let key = DayKey.string(for: date, calendar: calendar)
        commit { s in
            if result == .unset {
                s.dayResults[key] = nil
            } else {
                s.dayResults[key] = result
            }
        }
    }
}

// MARK: - Persistence

private struct PersistenceIO {
    private var url: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("ForEveryDay", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("habits.json")
    }

    func save(_ state: PersistedState) {
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: url, options: [.atomic])
        } catch {
            // Single-user app; ignore write failures in UI
        }
    }

    func load() -> PersistedState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PersistedState.self, from: data)
    }
}
