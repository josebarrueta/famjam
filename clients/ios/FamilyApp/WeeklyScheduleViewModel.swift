import Combine
import Foundation
import FamilyCore

@MainActor
final class WeeklyScheduleViewModel: ObservableObject {
    @Published private(set) var events: [FamilyEvent] = []
    @Published private(set) var errorMessage: String?

    private let eventStore: any EventStore

    init(eventStore: any EventStore) {
        self.eventStore = eventStore
    }

    func loadEvents() async {
        do {
            events = try await eventStore.events().sorted { $0.startTime < $1.startTime }
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
}
