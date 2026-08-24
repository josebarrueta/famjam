import Foundation
import XCTest
@testable import FamilyCore

final class ConflictNotificationMessageTests: XCTestCase {
    func testNamesTheAffectedFamilyMember() {
        let member = FamilyMember(
            id: KidID(rawValue: "parent-1"),
            name: "Alex",
            role: .parent,
            colorTag: "blue"
        )
        let event = FamilyEvent(
            title: "Work meeting",
            kidID: member.id,
            participantIDs: [member.id],
            startTime: Date(timeIntervalSince1970: 1_735_841_600),
            endTime: Date(timeIntervalSince1970: 1_735_845_200),
            source: .manual,
            status: .confirmed
        )
        let conflict = EventConflict(
            kind: .overlappingParticipantActivity(member.id),
            eventIDs: [UUID(), event.id]
        )

        let message = ConflictNotificationMessage.make(
            event: event,
            conflicts: [conflict],
            members: [member]
        )

        XCTAssertEqual(message, "Heads up: Work meeting overlaps another event for Alex.")
    }
}
