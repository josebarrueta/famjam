import Foundation

/// Event data resolved for display without exposing persistence details to a view.
public struct ScheduleEventDisplay: Equatable, Sendable {
    public let event: FamilyEvent
    public let kidName: String?
    public let kidColorTag: String?

    public init(event: FamilyEvent, members: [FamilyMember]) {
        self.event = event
        let member = members.first { event.participantIDs.contains($0.id) }
        kidName = member?.name
        kidColorTag = member?.colorTag
    }
}
