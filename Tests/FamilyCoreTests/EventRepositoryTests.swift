import Foundation
import XCTest
@testable import FamilyCore

final class EventRepositoryTests: XCTestCase {
    func testCreatesAndListsAnEvent() throws {
        let repository = EventRepository(storageURL: temporaryStorageURL())
        let event = FamilyEvent(
            title: "Soccer practice",
            kidID: KidID(rawValue: "jake"),
            startTime: Date(timeIntervalSince1970: 1_735_841_600),
            endTime: Date(timeIntervalSince1970: 1_735_845_200),
            location: "North Field",
            driver: "Parent 1",
            source: .manual,
            status: .confirmed
        )

        try repository.save(event)

        XCTAssertEqual(try repository.events(), [event])
    }

    func testReportsAnOverlappingActivityForTheSameKid() throws {
        let repository = EventRepository(storageURL: temporaryStorageURL())
        let kidID = KidID(rawValue: "emma")
        let practice = FamilyEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            title: "Basketball practice",
            kidID: kidID,
            startTime: Date(timeIntervalSince1970: 1_735_841_600),
            endTime: Date(timeIntervalSince1970: 1_735_845_200),
            source: .manual,
            status: .confirmed
        )
        let game = FamilyEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            title: "Soccer game",
            kidID: kidID,
            startTime: Date(timeIntervalSince1970: 1_735_843_400),
            endTime: Date(timeIntervalSince1970: 1_735_847_000),
            source: .manual,
            status: .confirmed
        )
        try repository.save(practice)

        let conflicts = try repository.save(game)

        XCTAssertEqual(conflicts, [
            EventConflict(
                kind: .overlappingKidActivity(kidID),
                eventIDs: [practice.id, game.id]
            ),
        ])
    }

    func testReportsADoubleBookedDriverAcrossKids() throws {
        let repository = EventRepository(storageURL: temporaryStorageURL())
        let practice = FamilyEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            title: "Basketball practice",
            kidID: KidID(rawValue: "emma"),
            startTime: Date(timeIntervalSince1970: 1_735_841_600),
            endTime: Date(timeIntervalSince1970: 1_735_845_200),
            driver: "Parent 1",
            source: .manual,
            status: .confirmed
        )
        let game = FamilyEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            title: "Soccer game",
            kidID: KidID(rawValue: "jake"),
            startTime: Date(timeIntervalSince1970: 1_735_843_400),
            endTime: Date(timeIntervalSince1970: 1_735_847_000),
            driver: "Parent 1",
            source: .manual,
            status: .confirmed
        )
        try repository.save(practice)

        let conflicts = try repository.save(game)

        XCTAssertEqual(conflicts, [
            EventConflict(
                kind: .doubleBookedDriver("Parent 1"),
                eventIDs: [practice.id, game.id]
            ),
        ])
    }

    private func temporaryStorageURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("json")
    }
}
