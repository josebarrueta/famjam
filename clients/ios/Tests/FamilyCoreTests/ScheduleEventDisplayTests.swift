import Foundation
import XCTest
@testable import FamilyCore

final class ScheduleEventDisplayTests: XCTestCase {
    func testResolvesTheKidNameAndColorForAnEvent() {
        let kid = Kid(
            id: KidID(rawValue: "emma"),
            name: "Emma",
            gradeOrBirthYear: "5th grade",
            colorTag: "purple"
        )
        let event = FamilyEvent(
            title: "Basketball practice",
            kidID: kid.id,
            startTime: Date(timeIntervalSince1970: 1_735_841_600),
            endTime: Date(timeIntervalSince1970: 1_735_845_200),
            source: .manual,
            status: .confirmed
        )

        let display = ScheduleEventDisplay(event: event, kids: [kid])

        XCTAssertEqual(display.kidName, "Emma")
        XCTAssertEqual(display.kidColorTag, "purple")
    }

    func testKeepsKidDetailsEmptyWhenNoKidIsAssigned() {
        let event = FamilyEvent(
            title: "Family dinner",
            kidID: nil,
            startTime: Date(timeIntervalSince1970: 1_735_841_600),
            endTime: Date(timeIntervalSince1970: 1_735_845_200),
            source: .manual,
            status: .confirmed
        )

        let display = ScheduleEventDisplay(event: event, kids: [])

        XCTAssertNil(display.kidName)
        XCTAssertNil(display.kidColorTag)
    }
}
