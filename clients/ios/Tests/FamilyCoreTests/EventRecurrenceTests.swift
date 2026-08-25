import Foundation
import XCTest
@testable import FamilyCore

final class EventRecurrenceTests: XCTestCase {
    func testExpandsEveryTwoWeeksWithinVisibleRange() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 1, day: 5, hour: 16
        )))
        let event = FamilyEvent(
            title: "Chess Class",
            kidID: KidID(rawValue: "kid-1"),
            startTime: start,
            endTime: start.addingTimeInterval(3600),
            source: .manual,
            status: .confirmed,
            recurrence: EventRecurrence(
                frequency: .weekly,
                interval: 2,
                endDate: calendar.date(byAdding: .month, value: 2, to: start)!
            )
        )
        let range = DateInterval(
            start: start,
            end: calendar.date(byAdding: .month, value: 1, to: start)!
        )

        let occurrences = EventOccurrenceExpander.occurrences(
            of: [event],
            in: range,
            calendar: calendar
        )

        XCTAssertEqual(occurrences.map(\.event.startTime), [
            start,
            calendar.date(byAdding: .day, value: 14, to: start)!,
            calendar.date(byAdding: .day, value: 28, to: start)!,
        ])
        XCTAssertEqual(Set(occurrences.map(\.id)).count, 3)
        XCTAssertEqual(occurrences.last?.sourceEvent.id, event.id)
    }
}
