import SwiftUI
import FamilyCore

@main
struct FamilyActivityCoordinatorApp: App {
    private let eventStore: any EventStore
    private let kidStore: any KidStore

    init() {
        eventStore = LocalEventStore(storageURL: AppStorage.eventsURL)
        kidStore = LocalKidStore(storageURL: AppStorage.kidsURL)
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                WeeklyScheduleView(eventStore: eventStore, kidStore: kidStore)
                    .tabItem {
                        Label("Schedule", systemImage: "calendar")
                    }
                KidsView(kidStore: kidStore, eventStore: eventStore)
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

    static var kidsURL: URL {
        storageDirectory
            .appendingPathComponent("kids")
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
