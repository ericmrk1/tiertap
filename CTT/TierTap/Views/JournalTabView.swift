import SwiftUI

private enum JournalMode: String, CaseIterable, Identifiable {
    case history
    case photos
    case calendar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .history: return "History"
        case .photos: return "Photos"
        case .calendar: return "Calendar"
        }
    }

    var systemImage: String {
        switch self {
        case .history: return "list.bullet.rectangle"
        case .photos: return "photo.on.rectangle.angled"
        case .calendar: return "calendar"
        }
    }
}

/// Sprint 2 Journal tab: History list/grid, photo feed, and session calendar.
struct JournalTabView: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var rewardWalletStore: RewardWalletStore
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var subscriptionStore: SubscriptionStore

    @State private var mode: JournalMode = .history
    @State private var calendarSelectedDate: Date?
    @State private var selectedSession: Session?

    private var sessionsOnSelectedDay: [Session] {
        guard let day = calendarSelectedDate else { return [] }
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        return store.sessions
            .filter { $0.startTime >= start && $0.startTime < end }
            .sorted { $0.startTime > $1.startTime }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                VStack(spacing: 0) {
                    modePicker
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom, 6)

                    switch mode {
                    case .history:
                        HistoryView(presentsAsSheet: false)
                    case .photos:
                        HistoryPhotoFeedView()
                    case .calendar:
                        calendarPane
                    }
                }
            }
            .localizedNavigationTitle("Journal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .adaptiveSheet(item: $selectedSession) { session in
                SessionDetailView(session: session)
                    .environmentObject(store)
                    .environmentObject(settingsStore)
                    .environmentObject(rewardWalletStore)
                    .environmentObject(subscriptionStore)
                    .environmentObject(authStore)
            }
        }
    }

    private var modePicker: some View {
        Picker("", selection: $mode) {
            ForEach(JournalMode.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .tint(.green)
    }

    private var calendarPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SessionCalendarView(sessions: store.sessions, selectedDate: $calendarSelectedDate)
                    .padding(.horizontal)
                    .padding(.top, 8)

                if let day = calendarSelectedDate {
                    Text(dayHeader(day))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal)

                    if sessionsOnSelectedDay.isEmpty {
                        Text("No sessions on this day.")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.horizontal)
                    } else {
                        ForEach(sessionsOnSelectedDay) { session in
                            Button {
                                selectedSession = session
                            } label: {
                                SessionRow(session: session)
                                    .padding(.horizontal)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    Text("Tap a day to see sessions.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal)
                }
            }
            .padding(.bottom, 24)
        }
    }

    private func dayHeader(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter.string(from: date)
    }
}
