import Combine
import Foundation
import FamilyCore

@MainActor
final class WeeklyScheduleViewModel: ObservableObject {
    @Published private(set) var events: [FamilyEvent] = []
    @Published private(set) var members: [FamilyMember] = []
    @Published private(set) var errorMessage: String?

    private let eventStore: any EventStore
    private let memberStore: any FamilyMemberStore
    private let notificationStore: any ConflictNotificationStore
    private let alertPreferences: ConflictAlertPreferences

    init(
        eventStore: any EventStore,
        memberStore: any FamilyMemberStore,
        notificationStore: any ConflictNotificationStore,
        alertPreferences: ConflictAlertPreferences = ConflictAlertPreferences()
    ) {
        self.eventStore = eventStore
        self.memberStore = memberStore
        self.notificationStore = notificationStore
        self.alertPreferences = alertPreferences
    }

    func loadEvents() async {
        do {
            events = try await eventStore.events().sorted { $0.startTime < $1.startTime }
            members = try await memberStore.members().sorted { $0.name < $1.name }
            errorMessage = nil
        } catch {
            errorMessage = "Your schedule could not be loaded."
        }
    }

    func addEvent(_ event: FamilyEvent) async throws -> [EventConflict] {
        let conflicts = try await eventStore.save(event)
        if !conflicts.isEmpty, alertPreferences.areConflictAlertsEnabled {
            let message = ConflictNotificationMessage.make(
                event: event,
                conflicts: conflicts,
                members: members
            )
            try await notificationStore.save(ConflictNotification(message: message))
        }
        events = try await eventStore.events().sorted { $0.startTime < $1.startTime }
        return conflicts
    }

    func deleteEvent(_ event: FamilyEvent) async throws {
        try await eventStore.delete(event)
        events = try await eventStore.events().sorted { $0.startTime < $1.startTime }
    }
}
