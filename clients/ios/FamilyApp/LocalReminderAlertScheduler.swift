import FamilyCore
import Foundation
@preconcurrency import UserNotifications

actor LocalReminderAlertScheduler: ReminderAlertScheduler {
     // UNUserNotificationCenter is a thread-safe singleton; nonisolated(unsafe) lets Swift 6
     // know it is safe to reference across the actor boundary without copying.
    nonisolated(unsafe) private let notificationCenter = UNUserNotificationCenter.current()

    func schedule(_ reminder: FamilyReminder) async throws {
        await cancel(reminder)
        guard reminder.status == .open, let leadTime = reminder.alertLeadTime else { return }

        // Check authorization status without prompting — the prompt is requested
        // at app startup via requestPushNotifications(). If the user has not
        // granted permission we do not schedule a local notification.
        let settings = await notificationCenter.notificationSettings()
        guard settings.authorizationStatus == .authorized ||
              settings.authorizationStatus == .provisional ||
              settings.authorizationStatus == .ephemeral else { return }

        let fireAt = reminder.dueAt.addingTimeInterval(-Double(leadTime.rawValue * 60))
        guard fireAt > .now else { return }

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
