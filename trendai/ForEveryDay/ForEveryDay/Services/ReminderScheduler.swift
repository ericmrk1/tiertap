import Foundation
import UserNotifications

final class ReminderScheduler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderScheduler()

    private override init() {
        super.init()
    }

    func configure() {
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func scheduleReminders(for tasks: [HabitTask]) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                let habitIds = requests.map(\.identifier).filter { $0.hasPrefix("habit-task-") }
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: habitIds)

                for task in tasks {
                    guard let reminder = task.reminder else { continue }
                    var dateComponents = DateComponents()
                    dateComponents.hour = reminder.hour
                    dateComponents.minute = reminder.minute
                    let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
                    let content = UNMutableNotificationContent()
                    content.title = "For Every Day"
                    content.body = task.title
                    content.sound = .default
                    let request = UNNotificationRequest(
                        identifier: "habit-task-\(task.id.uuidString)",
                        content: content,
                        trigger: trigger
                    )
                    UNUserNotificationCenter.current().add(request)
                }
            }
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
