import PhotosUI
import SwiftUI
import UIKit

struct DailyChecklistView: View {
    @EnvironmentObject private var store: HabitStore
    @Binding var showingAddTask: Bool
    @Binding var showingAddIntention: Bool
    @State private var selectedDate = Date()
    @State private var showHorizontalTimeline = false
    @State private var editingTask: HabitTask?
    @State private var editingIntention: HabitTask?
    @State private var dayWindowExpanded = false
    @State private var timelineExpanded = true
    @State private var tasksExpanded = true
    @State private var intentionsExpanded = true
    @State private var showDailyIntentionsPopup = false
    @State private var shareImage: UIImage?
    @State private var showShareSheet = false
    @State private var isPreparingShareImage = false
    @State private var fullScreenTaskImage: FullScreenTaskImageItem?

    private var checklistCalendar: Calendar {
        var c = Calendar.current
        c.timeZone = .current
        return c
    }

    private var tasksForSelectedDay: [HabitTask] {
        store.tasksForCalendarDay(selectedDate, calendar: checklistCalendar)
    }

    private var intentionsForSelectedDay: [HabitTask] {
        store.intentionsForCalendarDay(selectedDate, calendar: checklistCalendar)
    }

    private var scheduledTasksForDay: [HabitTask] {
        tasksForSelectedDay
            .filter { $0.scheduledTime != nil }
            .sorted { a, b in
                guard let ta = a.scheduledTime, let tb = b.scheduledTime else { return false }
                if ta.hour != tb.hour { return ta.hour < tb.hour }
                if ta.minute != tb.minute { return ta.minute < tb.minute }
                return a.sortIndex < b.sortIndex
            }
    }

    private var unscheduledTasksForDay: [HabitTask] {
        tasksForSelectedDay
            .filter { $0.scheduledTime == nil }
            .sorted { $0.sortIndex < $1.sortIndex }
    }

    private var allowsTaskTemplateEdit: Bool {
        checklistCalendar.startOfDay(for: selectedDate) >= checklistCalendar.startOfDay(for: Date())
    }

    private var tasksSubtitle: String {
        if tasksForSelectedDay.isEmpty {
            return allowsTaskTemplateEdit
                ? "Tap + to add tasks."
                : "No tasks were saved for this day. Pick today to edit your list."
        }
        let sched = scheduledTasksForDay.count
        let unsched = unscheduledTasksForDay.count
        if sched > 0, unsched > 0 {
            return "\(sched) scheduled, \(unsched) unscheduled"
        }
        if sched > 0 {
            return "\(sched) scheduled"
        }
        return "\(unsched) unscheduled"
    }

    private var intentionsSubtitle: String {
        if intentionsForSelectedDay.isEmpty {
            return allowsTaskTemplateEdit ? "Soft goals for the day—tap + → New intention." : "No intentions saved for this day."
        }
        let n = intentionsForSelectedDay.count
        return "\(n) intention\(n == 1 ? "" : "s")"
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    CollapsibleBubble(
                        title: "Start Up & Wind Down",
                        subtitle: "",
                        isExpanded: $dayWindowExpanded
                    ) {
                        TimeOfDayPicker(label: "Day starts", time: store.dayStartBinding)
                        TimeOfDayPicker(label: "Day ends", time: store.dayEndBinding)
                    }

                    CollapsibleBubble(
                        title: "Timeline",
                        subtitle: "",
                        isExpanded: $timelineExpanded
                    ) {
                        VerticalDayTimelineContent(date: selectedDate, store: store)
                            .environment(\.calendar, checklistCalendar)
                            .frame(minHeight: 120)
                    }

                    DatePicker("", selection: $selectedDate, displayedComponents: .date)
                        .environment(\.timeZone, TimeZone.current)
                        .padding(.horizontal, 4)
                }

                CollapsibleBubble(
                    title: "Tasks",
                    subtitle: tasksSubtitle,
                    isExpanded: $tasksExpanded
                ) {
                    Group {
                        if tasksForSelectedDay.isEmpty {
                            Text("No tasks yet.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                        } else {
                            List {
                                if !scheduledTasksForDay.isEmpty {
                                    Section("Scheduled") {
                                        ForEach(scheduledTasksForDay) { task in
                                            taskRow(task)
                                        }
                                        .onDelete { offsets in
                                            deleteTasksMatchingSlice(scheduledTasksForDay, offsets: offsets)
                                        }
                                    }
                                }
                                if !unscheduledTasksForDay.isEmpty {
                                    Section("Unscheduled") {
                                        ForEach(unscheduledTasksForDay) { task in
                                            taskRow(task)
                                        }
                                        .onDelete { offsets in
                                            deleteTasksMatchingSlice(unscheduledTasksForDay, offsets: offsets)
                                        }
                                    }
                                }
                            }
                            .listStyle(.plain)
                            .scrollContentBackground(.hidden)
                        }
                    }
                    .frame(minHeight: 120)
                }
                .frame(maxHeight: tasksExpanded ? .infinity : nil, alignment: .top)

                CollapsibleBubble(
                    title: "Intentions",
                    subtitle: intentionsSubtitle,
                    isExpanded: $intentionsExpanded
                ) {
                    Group {
                        if intentionsForSelectedDay.isEmpty {
                            Text("No intentions yet.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                        } else {
                            List {
                                ForEach(intentionsForSelectedDay) { intention in
                                    intentionRow(intention)
                                }
                                .onDelete { offsets in
                                    guard allowsTaskTemplateEdit else { return }
                                    let ids = offsets.map { intentionsForSelectedDay[$0].id }
                                    let liveIndices = IndexSet(
                                        ids.compactMap { id in store.state.intentions.firstIndex(where: { $0.id == id }) }
                                    )
                                    guard !liveIndices.isEmpty else { return }
                                    store.deleteIntentions(at: liveIndices)
                                }
                            }
                            .listStyle(.plain)
                            .scrollContentBackground(.hidden)
                        }
                    }
                    .frame(minHeight: 100)
                }
                .frame(maxHeight: intentionsExpanded ? .infinity : nil, alignment: .top)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onChange(of: selectedDate) { _, newValue in
                store.ensureSnapshotWhenBrowsingPastDay(newValue, calendar: checklistCalendar)
            }
            .onAppear {
                store.ensureSnapshotWhenBrowsingPastDay(selectedDate, calendar: checklistCalendar)
            }
            .navigationTitle("For Every Day")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        showDailyIntentionsPopup = true
                    } label: {
                        Image(systemName: "leaf.fill")
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(HapticToolbarButtonStyle())
                    .accessibilityLabel("All daily intentions")

                    Menu {
                        ForEach(ScheduleShareOrientation.allCases, id: \.self) { orientation in
                            Button(orientation.menuTitle) {
                                shareDailySchedule(orientation: orientation)
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
            .overlay(alignment: .bottomTrailing) {
                Menu {
                    Button("New task") {
                        HapticButton.lightImpact()
                        showingAddTask = true
                    }
                    Button("New intention") {
                        HapticButton.lightImpact()
                        showingAddIntention = true
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 54))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.accentColor)
                        .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)
                }
                .buttonStyle(HapticAnimatedButtonStyle(pressedScale: 0.86, hapticStyle: .medium))
                .disabled(!allowsTaskTemplateEdit)
                .opacity(allowsTaskTemplateEdit ? 1 : 0.35)
                .padding(.trailing, 20)
                .padding(.bottom, 12)
            }
            .sheet(isPresented: $showHorizontalTimeline) {
                NavigationStack {
                    DayTimelineView(date: selectedDate, store: store, onOpenVertical: nil)
                        .environment(\.calendar, checklistCalendar)
                        .navigationTitle("Horizontal timeline")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") {
                                    HapticButton.lightImpact()
                                    showHorizontalTimeline = false
                                }
                            }
                        }
                }
                .presentationDetents([.fraction(0.85)])
            }
            .sheet(isPresented: $showDailyIntentionsPopup) {
                DailyIntentionsListSheet(
                    date: selectedDate,
                    store: store,
                    calendar: checklistCalendar,
                    allowsEdit: allowsTaskTemplateEdit,
                    onEdit: { intention in
                        editingIntention = intention
                    }
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(item: $editingTask) { task in
                TaskEditorSheet(mode: .edit(task)) { title, scheduledTime, reminder, iconEmoji, systemSymbolName, attachmentImageData in
                    var t = task
                    t.title = title
                    t.scheduledTime = scheduledTime
                    t.reminder = reminder
                    t.iconEmoji = iconEmoji
                    t.systemSymbolName = systemSymbolName
                    t.attachmentImageData = attachmentImageData
                    store.updateTask(t)
                    store.requestNotificationPermission()
                    editingTask = nil
                } onCancel: {
                    editingTask = nil
                }
            }
            .sheet(item: $editingIntention) { intention in
                IntentionEditorSheet(mode: .edit(intention)) { title, iconEmoji, systemSymbolName, attachmentImageData in
                    var i = intention
                    i.title = title
                    i.iconEmoji = iconEmoji
                    i.systemSymbolName = systemSymbolName
                    i.attachmentImageData = attachmentImageData
                    store.updateIntention(i)
                    editingIntention = nil
                } onCancel: {
                    editingIntention = nil
                }
            }
            .fullScreenCover(item: $fullScreenTaskImage) { item in
                TaskAttachmentFullScreenView(image: item.image, title: item.title)
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

    @ViewBuilder
    private func taskRow(_ task: HabitTask) -> some View {
        let completed = store.isCompleted(taskId: task.id, on: selectedDate)
        HStack(alignment: .top, spacing: 10) {
            Button {
                store.toggleCompleted(taskId: task.id, on: selectedDate)
            } label: {
                Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                    .imageScale(.large)
                    .foregroundStyle(completed ? .green : .secondary)
            }
            .buttonStyle(.plain)

            TaskLeadingAttachmentView(task: task) {
                guard let data = task.attachmentImageData, let ui = UIImage(data: data) else { return }
                fullScreenTaskImage = FullScreenTaskImageItem(id: task.id, image: ui, title: task.title)
            }

            Button {
                store.toggleCompleted(taskId: task.id, on: selectedDate)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    if let st = task.scheduledTime {
                        Label(st.displayString, systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let rm = task.reminder {
                        Label("Reminder \(rm.displayString)", systemImage: "bell")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(HapticAnimatedButtonStyle(pressedScale: 0.985))
        }
        .listRowBackground(Color.clear)
        .swipeActions(edge: .trailing) {
            if allowsTaskTemplateEdit {
                Button(role: .destructive) {
                    HapticButton.mediumImpact()
                    store.deleteTask(task)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                Button {
                    HapticButton.lightImpact()
                    editingTask = task
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(.indigo)
            }
        }
    }

    @ViewBuilder
    private func intentionRow(_ intention: HabitTask) -> some View {
        let completed = store.isCompleted(taskId: intention.id, on: selectedDate)
        HStack(alignment: .top, spacing: 10) {
            Button {
                store.toggleCompleted(taskId: intention.id, on: selectedDate)
            } label: {
                Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                    .imageScale(.large)
                    .foregroundStyle(completed ? .green : .secondary)
            }
            .buttonStyle(.plain)

            TaskLeadingAttachmentView(task: intention) {
                guard let data = intention.attachmentImageData, let ui = UIImage(data: data) else { return }
                fullScreenTaskImage = FullScreenTaskImageItem(id: intention.id, image: ui, title: intention.title)
            }

            Button {
                store.toggleCompleted(taskId: intention.id, on: selectedDate)
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "leaf")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(intention.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(HapticAnimatedButtonStyle(pressedScale: 0.985))
        }
        .listRowBackground(Color.clear)
        .swipeActions(edge: .trailing) {
            if allowsTaskTemplateEdit {
                Button(role: .destructive) {
                    HapticButton.mediumImpact()
                    store.deleteIntention(intention)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                Button {
                    HapticButton.lightImpact()
                    editingIntention = intention
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(.indigo)
            }
        }
    }

    private func deleteTasksMatchingSlice(_ slice: [HabitTask], offsets: IndexSet) {
        guard allowsTaskTemplateEdit else { return }
        let ids = offsets.map { slice[$0].id }
        let liveIndices = IndexSet(ids.compactMap { id in store.state.tasks.firstIndex(where: { $0.id == id }) })
        guard !liveIndices.isEmpty else { return }
        store.deleteTasks(at: liveIndices)
    }

    private func shareDailySchedule(orientation: ScheduleShareOrientation) {
        guard !isPreparingShareImage else { return }
        isPreparingShareImage = true
        Task { @MainActor in
            await Task.yield()
            let payload = store.dailyScheduleSharePayload(for: selectedDate, calendar: checklistCalendar)
            let image = DailyScheduleShare.renderImage(payload: payload, orientation: orientation)
            isPreparingShareImage = false
            guard let image else { return }
            HapticButton.lightImpact()
            shareImage = image
            showShareSheet = true
        }
    }
}

// MARK: - Daily intentions (full list)

struct DailyIntentionsListSheet: View {
    let date: Date
    @ObservedObject var store: HabitStore
    var calendar: Calendar
    var allowsEdit: Bool
    var onEdit: (HabitTask) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var fullScreenTaskImage: FullScreenTaskImageItem?

    private var intentions: [HabitTask] {
        store.intentionsForCalendarDay(date, calendar: calendar)
    }

    var body: some View {
        NavigationStack {
            Group {
                if intentions.isEmpty {
                    ContentUnavailableView(
                        "No intentions",
                        systemImage: "leaf",
                        description: Text(
                            allowsEdit
                                ? "Add intentions from the checklist—with small, concrete goals for the day."
                                : "Nothing was saved for this day."
                        )
                    )
                } else {
                    List {
                        ForEach(intentions) { intention in
                            let completed = store.isCompleted(taskId: intention.id, on: date)
                            HStack(alignment: .top, spacing: 10) {
                                Button {
                                    store.toggleCompleted(taskId: intention.id, on: date)
                                } label: {
                                    Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                                        .imageScale(.large)
                                        .foregroundStyle(completed ? .green : .secondary)
                                }
                                .buttonStyle(.plain)

                                TaskLeadingAttachmentView(task: intention) {
                                    guard let data = intention.attachmentImageData, let ui = UIImage(data: data) else { return }
                                    fullScreenTaskImage = FullScreenTaskImageItem(id: intention.id, image: ui, title: intention.title)
                                }

                                Button {
                                    store.toggleCompleted(taskId: intention.id, on: date)
                                } label: {
                                    Text(intention.title)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(HapticAnimatedButtonStyle(pressedScale: 0.985))
                            }
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing) {
                                if allowsEdit {
                                    Button(role: .destructive) {
                                        HapticButton.mediumImpact()
                                        store.deleteIntention(intention)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    Button {
                                        HapticButton.lightImpact()
                                        onEdit(intention)
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(.indigo)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Daily intentions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        HapticButton.lightImpact()
                        dismiss()
                    }
                }
            }
            .fullScreenCover(item: $fullScreenTaskImage) { item in
                TaskAttachmentFullScreenView(image: item.image, title: item.title)
            }
        }
    }
}

// MARK: - Task editor

enum TaskEditorMode {
    case add
    case edit(HabitTask)

    var title: String {
        switch self {
        case .add: return "New task"
        case .edit: return "Edit task"
        }
    }
}

struct TaskEditorSheet: View {
    let mode: TaskEditorMode
    var onSave: (String, TimeOfDay?, TimeOfDay?, String?, String?, Data?) -> Void
    var onCancel: () -> Void

    @State private var titleText: String = ""
    @State private var iconKind: TaskEditorIconKind = .none
    @State private var selectedEmoji: String?
    @State private var systemSymbolName: String?
    @State private var attachmentImageData: Data?
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showSymbolPicker = false
    @State private var showPhotoPreview = false
    @State private var scheduleOn: Bool = false
    @State private var scheduleTime: TimeOfDay = TimeOfDay(hour: 14, minute: 0)
    @State private var reminderOn: Bool = false
    @State private var reminderTime: TimeOfDay = TimeOfDay(hour: 9, minute: 0)

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TaskEditorPhotoHero(attachmentImageData: attachmentImageData) {
                        if attachmentImageData != nil { showPhotoPreview = true }
                    }
                }
                TextField("Task", text: $titleText)
                TaskLookEditorSection(
                    iconKind: $iconKind,
                    selectedEmoji: $selectedEmoji,
                    systemSymbolName: $systemSymbolName,
                    attachmentImageData: $attachmentImageData,
                    photoPickerItem: $photoPickerItem,
                    showSymbolPicker: $showSymbolPicker,
                    isDisabled: false
                )
                Section {
                    Toggle("Time of day", isOn: $scheduleOn)
                    if scheduleOn {
                        TimeOfDayPicker(label: "On your timeline", time: $scheduleTime)
                    }
                    Toggle("Reminder", isOn: $reminderOn)
                    if reminderOn {
                        TimeOfDayPicker(label: "Notify at", time: $reminderTime)
                    }
                } footer: {
                    Text("Use time of day to place the task on your schedule. Reminder sends a daily notification—each can be on alone or both.")
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        HapticButton.lightImpact()
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        HapticButton.mediumImpact()
                        let emojiOut = iconKind == .emoji ? selectedEmoji : nil
                        let symOut: String?
                        if iconKind == .systemSymbol,
                           let s = systemSymbolName?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty,
                           UIImage(systemName: s) != nil {
                            symOut = s
                        } else {
                            symOut = nil
                        }
                        onSave(
                            trimmed,
                            scheduleOn ? scheduleTime : nil,
                            reminderOn ? reminderTime : nil,
                            emojiOut,
                            symOut,
                            attachmentImageData
                        )
                    }
                    .disabled(titleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .sheet(isPresented: $showSymbolPicker) {
                SystemSymbolPickerSheet(selectedName: $systemSymbolName)
            }
            .fullScreenCover(isPresented: $showPhotoPreview) {
                if let data = attachmentImageData, let ui = UIImage(data: data) {
                    TaskAttachmentFullScreenView(
                        image: ui,
                        title: titleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Photo" : titleText
                    )
                }
            }
            .onChange(of: photoPickerItem) { _, newItem in
                Task {
                    let data = await TaskAttachmentEditorSupport.loadPhotoData(from: newItem)
                    await MainActor.run { attachmentImageData = data }
                }
            }
            .onAppear {
                switch mode {
                case .add:
                    titleText = ""
                    iconKind = .none
                    selectedEmoji = nil
                    systemSymbolName = nil
                    attachmentImageData = nil
                    photoPickerItem = nil
                    scheduleOn = false
                    reminderOn = false
                case .edit(let task):
                    titleText = task.title
                    attachmentImageData = task.attachmentImageData
                    photoPickerItem = nil
                    if let s = task.systemSymbolName,
                       !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       UIImage(systemName: s) != nil {
                        iconKind = .systemSymbol
                        systemSymbolName = s
                        selectedEmoji = nil
                    } else if let e = task.iconEmoji, !e.isEmpty {
                        iconKind = .emoji
                        selectedEmoji = e
                        systemSymbolName = nil
                    } else {
                        iconKind = .none
                        selectedEmoji = nil
                        systemSymbolName = nil
                    }
                    if let st = task.scheduledTime {
                        scheduleOn = true
                        scheduleTime = st
                    } else {
                        scheduleOn = false
                    }
                    if let r = task.reminder {
                        reminderOn = true
                        reminderTime = r
                    } else {
                        reminderOn = false
                    }
                }
            }
        }
    }
}

// MARK: - Intention editor

enum IntentionEditorMode {
    case add
    case edit(HabitTask)

    var title: String {
        switch self {
        case .add: return "New intention"
        case .edit: return "Edit intention"
        }
    }
}

struct IntentionEditorSheet: View {
    let mode: IntentionEditorMode
    var onSave: (String, String?, String?, Data?) -> Void
    var onCancel: () -> Void

    @State private var titleText: String = ""
    @State private var iconKind: TaskEditorIconKind = .none
    @State private var selectedEmoji: String?
    @State private var systemSymbolName: String?
    @State private var attachmentImageData: Data?
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showSymbolPicker = false
    @State private var showPhotoPreview = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TaskEditorPhotoHero(attachmentImageData: attachmentImageData) {
                        if attachmentImageData != nil { showPhotoPreview = true }
                    }
                }
                TextField("Intention", text: $titleText, axis: .vertical)
                    .lineLimit(3...6)
                TaskLookEditorSection(
                    iconKind: $iconKind,
                    selectedEmoji: $selectedEmoji,
                    systemSymbolName: $systemSymbolName,
                    attachmentImageData: $attachmentImageData,
                    photoPickerItem: $photoPickerItem,
                    showSymbolPicker: $showSymbolPicker,
                    isDisabled: false
                )
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        HapticButton.lightImpact()
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        HapticButton.mediumImpact()
                        let emojiOut = iconKind == .emoji ? selectedEmoji : nil
                        let symOut: String?
                        if iconKind == .systemSymbol,
                           let s = systemSymbolName?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty,
                           UIImage(systemName: s) != nil {
                            symOut = s
                        } else {
                            symOut = nil
                        }
                        onSave(trimmed, emojiOut, symOut, attachmentImageData)
                    }
                    .disabled(titleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .sheet(isPresented: $showSymbolPicker) {
                SystemSymbolPickerSheet(selectedName: $systemSymbolName)
            }
            .fullScreenCover(isPresented: $showPhotoPreview) {
                if let data = attachmentImageData, let ui = UIImage(data: data) {
                    TaskAttachmentFullScreenView(
                        image: ui,
                        title: titleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Photo" : titleText
                    )
                }
            }
            .onChange(of: photoPickerItem) { _, newItem in
                Task {
                    let data = await TaskAttachmentEditorSupport.loadPhotoData(from: newItem)
                    await MainActor.run { attachmentImageData = data }
                }
            }
            .onAppear {
                switch mode {
                case .add:
                    titleText = ""
                    iconKind = .none
                    selectedEmoji = nil
                    systemSymbolName = nil
                    attachmentImageData = nil
                    photoPickerItem = nil
                case .edit(let row):
                    titleText = row.title
                    attachmentImageData = row.attachmentImageData
                    photoPickerItem = nil
                    if let s = row.systemSymbolName,
                       !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       UIImage(systemName: s) != nil {
                        iconKind = .systemSymbol
                        systemSymbolName = s
                        selectedEmoji = nil
                    } else if let e = row.iconEmoji, !e.isEmpty {
                        iconKind = .emoji
                        selectedEmoji = e
                        systemSymbolName = nil
                    } else {
                        iconKind = .none
                        selectedEmoji = nil
                        systemSymbolName = nil
                    }
                }
            }
        }
    }
}
