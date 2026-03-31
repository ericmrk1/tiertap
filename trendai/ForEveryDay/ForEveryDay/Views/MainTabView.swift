import SwiftUI
import UIKit

private enum MainTab: Hashable {
    case daily
    case calendar
    case analysis
    case settings
}

struct MainTabView: View {
    @EnvironmentObject private var store: HabitStore
    @State private var selectedTab: MainTab = .daily
    @State private var showingAddTask = false
    @State private var showingAddIntention = false

    var body: some View {
        TabView(selection: $selectedTab) {
            DailyChecklistView(showingAddTask: $showingAddTask, showingAddIntention: $showingAddIntention)
                .tabItem {
                    Label("Daily Tasks", systemImage: "checklist")
                }
                .tag(MainTab.daily)
            CalendarMonthView()
                .tabItem {
                    Label("Calendar", systemImage: "calendar")
                }
                .tag(MainTab.calendar)
            AnalysisView()
                .tabItem {
                    Label("Analysis", systemImage: "chart.xyaxis.line")
                }
                .tag(MainTab.analysis)
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(MainTab.settings)
        }
        .overlay {
            ConfettiBurstView(burstID: store.targetStreakCelebrationTick)
                .ignoresSafeArea()
        }
        .onChange(of: store.targetStreakCelebrationTick) { _, newVal in
            guard newVal > 0 else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        .sheet(isPresented: $showingAddTask) {
            TaskEditorSheet(mode: .add) { title, scheduledTime, reminder, iconEmoji, systemSymbolName, imageData in
                store.addTask(
                    title: title,
                    scheduledTime: scheduledTime,
                    reminder: reminder,
                    iconEmoji: iconEmoji,
                    systemSymbolName: systemSymbolName,
                    attachmentImageData: imageData
                )
                store.requestNotificationPermission()
                showingAddTask = false
            } onCancel: {
                showingAddTask = false
            }
        }
        .sheet(isPresented: $showingAddIntention) {
            IntentionEditorSheet(mode: .add) { title, iconEmoji, systemSymbolName, imageData in
                store.addIntention(
                    title: title,
                    iconEmoji: iconEmoji,
                    systemSymbolName: systemSymbolName,
                    attachmentImageData: imageData
                )
                showingAddIntention = false
            } onCancel: {
                showingAddIntention = false
            }
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(HabitStore())
}
