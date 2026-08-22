import SwiftUI
import FamilyCore

@main
struct FamilyActivityCoordinatorApp: App {
    private let eventStore: any EventStore

    init() {
        eventStore = LocalEventStore(storageURL: AppStorage.eventsURL)
    }

    var body: some Scene {
        WindowGroup {
            WeeklyScheduleView(eventStore: eventStore)
        }
    }
}

enum AppStorage {
    static var eventsURL: URL {
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return directory
            .appending(path: "FamilyActivityCoordinator")
            .appendingPathComponent("events")
            .appendingPathExtension("json")
    }
}
