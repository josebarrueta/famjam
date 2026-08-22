import Combine
import Foundation
import FamilyCore

@MainActor
final class WeeklyScheduleViewModel: ObservableObject {
    @Published private(set) var events: [FamilyEvent] = []
    @Published private(set) var kids: [Kid] = []
    @Published private(set) var errorMessage: String?

    private let eventStore: any EventStore
    private let kidStore: any KidStore

    init(eventStore: any EventStore, kidStore: any KidStore) {
        self.eventStore = eventStore
        self.kidStore = kidStore
    }

    func loadEvents() async {
        do {
            events = try await eventStore.events().sorted { $0.startTime < $1.startTime }
            kids = try await kidStore.kids().sorted { $0.name < $1.name }
            errorMessage = nil
        } catch {
            errorMessage = "Your schedule could not be loaded."
        }
    }

    func addEvent(_ event: FamilyEvent) async throws -> [EventConflict] {
        let conflicts = try await eventStore.save(event)
        events = try await eventStore.events().sorted { $0.startTime < $1.startTime }
        return conflicts
    }

    func deleteEvent(_ event: FamilyEvent) async throws {
        try await eventStore.delete(event)
        events = try await eventStore.events().sorted { $0.startTime < $1.startTime }
    }
}
