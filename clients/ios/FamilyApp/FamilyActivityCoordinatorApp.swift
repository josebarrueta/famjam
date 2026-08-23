import SwiftUI
import FamilyCore

@main
struct FamilyActivityCoordinatorApp: App {
    private let eventStore: any EventStore
    private let memberStore: any FamilyMemberStore
    private let notificationStore: any ConflictNotificationStore

    init() {
        AppStorage.resetForUnifiedFamilyMembersIfNeeded()
        eventStore = LocalEventStore(storageURL: AppStorage.eventsURL)
        memberStore = LocalFamilyMemberStore(storageURL: AppStorage.membersURL)
        notificationStore = LocalConflictNotificationStore(storageURL: AppStorage.notificationsURL)
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                WeeklyScheduleView(eventStore: eventStore, memberStore: memberStore, notificationStore: notificationStore)
                    .tabItem {
                        Label("Schedule", systemImage: "calendar")
                    }
                FamilyMembersView(memberStore: memberStore, eventStore: eventStore)
                    .tabItem { Label("Family", systemImage: "person.2") }
                NotificationsView(notificationStore: notificationStore)
                    .tabItem { Label("Alerts", systemImage: "bell") }
            }
        }
    }
}

enum AppStorage {
    static var eventsURL: URL {
        storageDirectory
            .appendingPathComponent("events")
            .appendingPathExtension("json")
    }

    static var notificationsURL: URL {
        storageDirectory.appendingPathComponent("conflicts").appendingPathExtension("json")
    }

    static var membersURL: URL {
        storageDirectory
            .appendingPathComponent("members")
            .appendingPathExtension("json")
    }

    static func resetForUnifiedFamilyMembersIfNeeded() {
        let resetKey = "didResetForUnifiedFamilyMembers"
        guard !UserDefaults.standard.bool(forKey: resetKey) else { return }
        try? FileManager.default.removeItem(at: storageDirectory)
        UserDefaults.standard.set(true, forKey: resetKey)
    }

    private static var storageDirectory: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appending(path: "FamilyActivityCoordinator")
    }
}
