import SwiftUI
import FamilyCore

@main
struct FamilyActivityCoordinatorApp: App {
    private let eventStore: any EventStore
    private let memberStore: any FamilyMemberStore

    init() {
        eventStore = LocalEventStore(storageURL: AppStorage.eventsURL)
        memberStore = LocalFamilyMemberStore(storageURL: AppStorage.membersURL)
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                WeeklyScheduleView(eventStore: eventStore, memberStore: memberStore)
                    .tabItem {
                        Label("Schedule", systemImage: "calendar")
                    }
                FamilyMembersView(memberStore: memberStore)
                    .tabItem {
                        Label("Kids", systemImage: "person.2")
                    }
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

    static var membersURL: URL {
        storageDirectory
            .appendingPathComponent("members")
            .appendingPathExtension("json")
    }

    private static var storageDirectory: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appending(path: "FamilyActivityCoordinator")
    }
}
