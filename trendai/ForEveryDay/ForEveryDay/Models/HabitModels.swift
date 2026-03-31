import Foundation
import UIKit

enum DayResult: String, Codable, CaseIterable, Sendable {
    case unset
    case won
    case lost

    var symbolName: String {
        switch self {
        case .unset: return "circle.dashed"
        case .won: return "checkmark.circle.fill"
        case .lost: return "xmark.circle.fill"
        }
    }
}

struct TimeOfDay: Codable, Equatable, Hashable, Sendable {
    var hour: Int
    var minute: Int

    static let defaultStart = TimeOfDay(hour: 6, minute: 0)
    static let defaultEnd = TimeOfDay(hour: 22, minute: 0)

    func date(on calendarDay: Date, calendar: Calendar) -> Date? {
        var comps = calendar.dateComponents([.year, .month, .day], from: calendarDay)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        return calendar.date(from: comps)
    }

    var displayString: String {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        let cal = Calendar.current
        let ref = cal.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: hour, minute: minute)) ?? Date()
        return f.string(from: ref)
    }
}

struct HabitTask: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var title: String
    var sortIndex: Int
    /// Optional emoji shown beside the task or intention (lists and timeline).
    var iconEmoji: String?
    /// SF Symbol name (e.g. `star.fill`) when set instead of emoji.
    var systemSymbolName: String?
    /// JPEG bytes for an optional photo; tap in lists to view full screen.
    var attachmentImageData: Data?
    /// When non-nil, this task appears on the day timeline / schedule (when inside the day window).
    var scheduledTime: TimeOfDay?
    /// When non-nil, a local notification is scheduled for this clock time each day.
    var reminder: TimeOfDay?

    init(
        id: UUID = UUID(),
        title: String,
        sortIndex: Int,
        iconEmoji: String? = nil,
        systemSymbolName: String? = nil,
        attachmentImageData: Data? = nil,
        scheduledTime: TimeOfDay? = nil,
        reminder: TimeOfDay? = nil
    ) {
        self.id = id
        self.title = title
        self.sortIndex = sortIndex
        self.iconEmoji = iconEmoji
        self.systemSymbolName = systemSymbolName
        self.attachmentImageData = attachmentImageData
        self.scheduledTime = scheduledTime
        self.reminder = reminder
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, sortIndex, iconEmoji, systemSymbolName, attachmentImageData, scheduledTime, reminder
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        sortIndex = try c.decode(Int.self, forKey: .sortIndex)
        iconEmoji = try c.decodeIfPresent(String.self, forKey: .iconEmoji)
        systemSymbolName = try c.decodeIfPresent(String.self, forKey: .systemSymbolName)
        attachmentImageData = try c.decodeIfPresent(Data.self, forKey: .attachmentImageData)
        let hadScheduledTimeKey = c.contains(.scheduledTime)
        scheduledTime = try c.decodeIfPresent(TimeOfDay.self, forKey: .scheduledTime)
        reminder = try c.decodeIfPresent(TimeOfDay.self, forKey: .reminder)
        // Legacy JSON had only `reminder`, used for both timeline and notification.
        if !hadScheduledTimeKey, scheduledTime == nil, let r = reminder {
            scheduledTime = r
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(sortIndex, forKey: .sortIndex)
        if let iconEmoji {
            try c.encode(iconEmoji, forKey: .iconEmoji)
        } else {
            try c.encodeNil(forKey: .iconEmoji)
        }
        if let systemSymbolName {
            try c.encode(systemSymbolName, forKey: .systemSymbolName)
        } else {
            try c.encodeNil(forKey: .systemSymbolName)
        }
        if let attachmentImageData {
            try c.encode(attachmentImageData, forKey: .attachmentImageData)
        } else {
            try c.encodeNil(forKey: .attachmentImageData)
        }
        if let scheduledTime {
            try c.encode(scheduledTime, forKey: .scheduledTime)
        } else {
            try c.encodeNil(forKey: .scheduledTime)
        }
        if let reminder {
            try c.encode(reminder, forKey: .reminder)
        } else {
            try c.encodeNil(forKey: .reminder)
        }
    }
}

extension HabitTask {
    /// SF Symbol name that actually renders on this OS, if any.
    var resolvedSystemSymbolName: String? {
        guard let s = systemSymbolName?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty,
              UIImage(systemName: s) != nil else { return nil }
        return s
    }

    /// Prefix for compact timeline labels (emoji or a camera glyph when only a photo is set).
    var timelineTitleDisplay: String {
        if let e = iconEmoji, !e.isEmpty {
            return "\(e) \(title)"
        }
        if resolvedSystemSymbolName != nil {
            return title
        }
        if attachmentImageData != nil {
            return "📷 \(title)"
        }
        return title
    }
}

struct PersistedState: Codable, Sendable {
    /// Action items for the day (optional schedule / reminders)—distinct from soft “intentions”.
    var tasks: [HabitTask]
    /// Daily intentions (e.g. “one coffee”); same completion IDs as tasks, no timeline/reminders.
    var intentions: [HabitTask]
    var dayStart: TimeOfDay
    var dayEnd: TimeOfDay
    /// yyyy-MM-dd → sorted list of completed task IDs for that calendar day
    var completionsByDay: [String: [UUID]]
    /// yyyy-MM-dd → result
    var dayResults: [String: DayResult]
    /// Best consecutive win streak ever recorded (updated when current exceeds it).
    var longestStreakEver: Int
    /// Goal streak length in days (0 = not set).
    var targetStreak: Int
    /// yyyy-MM-dd → copy of `tasks` as it applied to that calendar day (past days only; today/future use live `tasks`).
    var taskListSnapshots: [String: [HabitTask]]
    /// yyyy-MM-dd → copy of `intentions` for that calendar day (past days only).
    var intentionListSnapshots: [String: [HabitTask]]

    static let empty = PersistedState(
        tasks: [],
        intentions: [],
        dayStart: .defaultStart,
        dayEnd: .defaultEnd,
        completionsByDay: [:],
        dayResults: [:],
        longestStreakEver: 0,
        targetStreak: 0,
        taskListSnapshots: [:],
        intentionListSnapshots: [:]
    )

    private enum CodingKeys: String, CodingKey {
        case tasks, intentions, dayStart, dayEnd, completionsByDay, dayResults, longestStreakEver, targetStreak, taskListSnapshots, intentionListSnapshots
    }

    init(
        tasks: [HabitTask],
        intentions: [HabitTask] = [],
        dayStart: TimeOfDay,
        dayEnd: TimeOfDay,
        completionsByDay: [String: [UUID]],
        dayResults: [String: DayResult],
        longestStreakEver: Int = 0,
        targetStreak: Int = 0,
        taskListSnapshots: [String: [HabitTask]] = [:],
        intentionListSnapshots: [String: [HabitTask]] = [:]
    ) {
        self.tasks = tasks
        self.intentions = intentions
        self.dayStart = dayStart
        self.dayEnd = dayEnd
        self.completionsByDay = completionsByDay
        self.dayResults = dayResults
        self.longestStreakEver = longestStreakEver
        self.targetStreak = targetStreak
        self.taskListSnapshots = taskListSnapshots
        self.intentionListSnapshots = intentionListSnapshots
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tasks = try c.decode([HabitTask].self, forKey: .tasks)
        intentions = try c.decodeIfPresent([HabitTask].self, forKey: .intentions) ?? []
        dayStart = try c.decode(TimeOfDay.self, forKey: .dayStart)
        dayEnd = try c.decode(TimeOfDay.self, forKey: .dayEnd)
        completionsByDay = try c.decode([String: [UUID]].self, forKey: .completionsByDay)
        dayResults = try c.decode([String: DayResult].self, forKey: .dayResults)
        longestStreakEver = try c.decodeIfPresent(Int.self, forKey: .longestStreakEver) ?? 0
        targetStreak = try c.decodeIfPresent(Int.self, forKey: .targetStreak) ?? 0
        taskListSnapshots = try c.decodeIfPresent([String: [HabitTask]].self, forKey: .taskListSnapshots) ?? [:]
        intentionListSnapshots = try c.decodeIfPresent([String: [HabitTask]].self, forKey: .intentionListSnapshots) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(tasks, forKey: .tasks)
        try c.encode(intentions, forKey: .intentions)
        try c.encode(dayStart, forKey: .dayStart)
        try c.encode(dayEnd, forKey: .dayEnd)
        try c.encode(completionsByDay, forKey: .completionsByDay)
        try c.encode(dayResults, forKey: .dayResults)
        try c.encode(longestStreakEver, forKey: .longestStreakEver)
        try c.encode(targetStreak, forKey: .targetStreak)
        try c.encode(taskListSnapshots, forKey: .taskListSnapshots)
        try c.encode(intentionListSnapshots, forKey: .intentionListSnapshots)
    }

    /// One-time migration: days with stored outcomes but no snapshot get a copy of the current template (best effort).
    mutating func migrateLegacyTaskSnapshotsIfNeeded(calendar: Calendar = .current) {
        let todayKey = DayKey.string(for: Date(), calendar: calendar)
        let keys = Set(completionsByDay.keys).union(dayResults.keys)
        let frozenTasks = tasks.map { $0 }
        let frozenIntentions = intentions.map { $0 }
        for key in keys where key < todayKey {
            if taskListSnapshots[key] == nil {
                taskListSnapshots[key] = frozenTasks
            }
            if intentionListSnapshots[key] == nil {
                intentionListSnapshots[key] = frozenIntentions
            }
        }
    }

    /// Before changing the live task list or intentions, freeze lists for past days that already have history (plus yesterday).
    mutating func freezeTaskListSnapshotsForPastDaysBeforeTemplateChange(calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: Date())
        let todayKey = DayKey.string(for: today, calendar: calendar)
        var keys = Set(completionsByDay.keys)
            .union(dayResults.keys)
            .union(taskListSnapshots.keys)
            .union(intentionListSnapshots.keys)
        if let y = calendar.date(byAdding: .day, value: -1, to: today) {
            keys.insert(DayKey.string(for: y, calendar: calendar))
        }
        let frozenTasks = tasks.map { $0 }
        let frozenIntentions = intentions.map { $0 }
        for key in keys where key < todayKey {
            if taskListSnapshots[key] == nil {
                taskListSnapshots[key] = frozenTasks
            }
            if intentionListSnapshots[key] == nil {
                intentionListSnapshots[key] = frozenIntentions
            }
        }
    }
}

// MARK: - Day outcome & streak (single source of truth for calendar + streaks)

extension PersistedState {
    /// Task rows that count for this calendar day (snapshot for past days; live list for today and future).
    func tasksForCalendarDay(_ date: Date, calendar: Calendar = .current) -> [HabitTask] {
        let key = DayKey.string(for: date, calendar: calendar)
        let todayStart = calendar.startOfDay(for: Date())
        let dayStart = calendar.startOfDay(for: date)
        if dayStart >= todayStart {
            return tasks.sorted { $0.sortIndex < $1.sortIndex }
        }
        if let snap = taskListSnapshots[key] {
            return snap.sorted { $0.sortIndex < $1.sortIndex }
        }
        return []
    }

    func intentionsForCalendarDay(_ date: Date, calendar: Calendar = .current) -> [HabitTask] {
        let key = DayKey.string(for: date, calendar: calendar)
        let todayStart = calendar.startOfDay(for: Date())
        let dayStart = calendar.startOfDay(for: date)
        if dayStart >= todayStart {
            return intentions.sorted { $0.sortIndex < $1.sortIndex }
        }
        if let snap = intentionListSnapshots[key] {
            return snap.sorted { $0.sortIndex < $1.sortIndex }
        }
        return []
    }

    func allTasksCompleted(on date: Date, calendar: Calendar = .current) -> Bool {
        let dayTasks = tasksForCalendarDay(date, calendar: calendar)
        let dayIntentions = intentionsForCalendarDay(date, calendar: calendar)
        guard !dayTasks.isEmpty || !dayIntentions.isEmpty else { return false }
        let key = DayKey.string(for: date, calendar: calendar)
        let done = Set(completionsByDay[key, default: []])
        let tasksDone = dayTasks.isEmpty || dayTasks.allSatisfy { done.contains($0.id) }
        let intentionsDone = dayIntentions.isEmpty || dayIntentions.allSatisfy { done.contains($0.id) }
        return tasksDone && intentionsDone
    }

    func displayResult(on date: Date, calendar: Calendar = .current) -> DayResult {
        let key = DayKey.string(for: date, calendar: calendar)
        if let manual = dayResults[key], manual != .unset {
            return manual
        }
        let dayTasks = tasksForCalendarDay(date, calendar: calendar)
        let dayIntentions = intentionsForCalendarDay(date, calendar: calendar)
        if dayTasks.isEmpty && dayIntentions.isEmpty { return .unset }
        if allTasksCompleted(on: date, calendar: calendar) { return .won }

        let thisDayStart = calendar.startOfDay(for: date)
        let todayStart = calendar.startOfDay(for: Date())
        if thisDayStart > todayStart { return .unset }
        if thisDayStart < todayStart { return .lost }

        guard let endDate = dayEnd.date(on: date, calendar: calendar) else { return .unset }
        return Date() >= endDate ? .lost : .unset
    }

    /// Consecutive `.won` days: includes today if already a win; if today is still in play (`unset`), counts through yesterday.
    func currentStreak(calendar: Calendar = .current) -> Int {
        let today = calendar.startOfDay(for: Date())
        let todayResult = displayResult(on: today, calendar: calendar)
        if todayResult == .lost { return 0 }

        var count = 0
        var d: Date

        if todayResult == .won {
            d = today
        } else {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }
            d = calendar.startOfDay(for: yesterday)
        }

        while displayResult(on: d, calendar: calendar) == .won {
            count += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: d) else { break }
            d = calendar.startOfDay(for: prev)
        }

        return count
    }

    /// Tasks that have a scheduled time falling inside the day window on `date`, ordered by time.
    func tasksWithReminders(on date: Date, calendar: Calendar = .current) -> [(HabitTask, Date)] {
        let day = date
        let dayTasks = tasksForCalendarDay(date, calendar: calendar)
        return dayTasks.compactMap { task -> (HabitTask, Date)? in
            guard let st = task.scheduledTime,
                  let at = st.date(on: day, calendar: calendar) else { return nil }
            guard let winStart = dayStart.date(on: day, calendar: calendar),
                  let winEnd = dayEnd.date(on: day, calendar: calendar),
                  winEnd > winStart else { return nil }
            if at >= winStart && at <= winEnd { return (task, at) }
            return nil
        }
        .sorted { $0.1 < $1.1 }
    }

    /// Tasks for this day with no scheduled time (“unscheduled”).
    func unscheduledTasks(on date: Date, calendar: Calendar = .current) -> [HabitTask] {
        tasksForCalendarDay(date, calendar: calendar)
            .filter { $0.scheduledTime == nil }
            .sorted { $0.sortIndex < $1.sortIndex }
    }
}

enum DayKey {
    static func string(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let y = c.year ?? 0
        let m = c.month ?? 0
        let d = c.day ?? 0
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    static func startOfDay(for key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var comps = DateComponents()
        comps.year = parts[0]
        comps.month = parts[1]
        comps.day = parts[2]
        return calendar.date(from: comps)
    }
}
