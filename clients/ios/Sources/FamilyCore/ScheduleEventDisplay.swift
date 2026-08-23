import Foundation

/// Event data resolved for display without exposing persistence details to a view.
public struct ScheduleEventDisplay: Equatable, Sendable {
    public let event: FamilyEvent
    public let kidName: String?
    public let kidColorTag: String?

    public init(event: FamilyEvent, kids: [Kid]) {
        self.event = event
        let kid = kids.first { $0.id == event.kidID }
        kidName = kid?.name
        kidColorTag = kid?.colorTag
    }
}
