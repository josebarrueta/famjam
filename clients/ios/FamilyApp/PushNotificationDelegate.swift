import UIKit
@preconcurrency import UserNotifications

final class PushNotificationDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        NotificationCenter.default.post(name: .didRegisterDeviceToken, object: token)
    }
}

extension Notification.Name {
    static let didRegisterDeviceToken = Notification.Name("didRegisterDeviceToken")
}
