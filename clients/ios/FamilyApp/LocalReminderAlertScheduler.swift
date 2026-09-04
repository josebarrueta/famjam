import FamilyCore
import Foundation
import UserNotifications

actor LocalReminderAlertScheduler: ReminderAlertScheduler {
    private let notificationCenter = UNUserNotificationCenter.current()

    func schedule(_ reminder: FamilyReminder) async throws {
        await cancel(reminder)
        guard reminder.status == .open, let leadTime = reminder.alertLeadTime else { return }
        let fireAt = reminder.dueAt.addingTimeInterval(-Double(leadTime.rawValue * 60))
        guard fireAt > .now else { return }
        guard try await notificationCenter.requestAuthorization(options: [.alert, .badge, .sound]) else { return }

        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = "Reminder due. Open Rallyroo to review."
        content.sound = .default
        content.userInfo = ["reminderID": reminder.id.uuidString]
        let interval = max(1, fireAt.timeIntervalSinceNow)
        try await notificationCenter.add(UNNotificationRequest(
            identifier: identifier(for: reminder),
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        ))
    }

    func cancel(_ reminder: FamilyReminder) async {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier(for: reminder)])
    }

    private func identifier(for reminder: FamilyReminder) -> String {
        "rallyroo.reminder.\(reminder.id.uuidString.lowercased())"
    }
}
