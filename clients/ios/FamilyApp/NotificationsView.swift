import SwiftUI
import FamilyCore

struct NotificationsView: View {
    let notificationStore: any ConflictNotificationStore
    @State private var notifications: [ConflictNotification] = []

    var body: some View {
        NavigationStack {
            List(notifications) { notification in
                VStack(alignment: .leading) {
                    Text(notification.message)
                    Text(notification.createdAt.formatted())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Alerts")
            .task { notifications = (try? await notificationStore.notifications().reversed()) ?? [] }
        }
    }
}
