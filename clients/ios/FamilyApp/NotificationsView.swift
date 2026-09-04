import SwiftUI
import FamilyCore

struct NotificationsView: View {
    let notificationStore: any ConflictNotificationStore
    @State private var notifications: [ConflictNotification] = []

    var body: some View {
        NavigationStack {
            List {
                RallyrooHeader(title: "Heads up!", subtitle: "We'll keep scheduling surprises in check.")
                    .listRowBackground(Color.clear)
                ForEach(notifications) { notification in
                    VStack(alignment: .leading) {
                        Text(notification.message)
                        Text(notification.createdAt.formatted())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Alerts")
            .toolbar {
                if !notifications.isEmpty {
                    Button("Clear") {
                        Task {
                            try? await notificationStore.clear()
                            notifications = []
                        }
                    }
                }
            }
            .onAppear {
                Task {
                    notifications = Array((try? await notificationStore.notifications())?.reversed() ?? [])
                }
            }
                  .tint(AppTheme.purple)
        }
    }
}
