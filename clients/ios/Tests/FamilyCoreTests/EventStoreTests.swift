import Foundation
import XCTest
@testable import FamilyCore

final class EventStoreTests: XCTestCase {
    func testCreatesAndListsAnEvent() async throws {
        let repository: any EventStore = LocalEventStore(storageURL: temporaryStorageURL())
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

        try await repository.save(event)

        let savedEvents = try await repository.events()
        XCTAssertEqual(savedEvents, [event])
    }

    func testReportsAnOverlappingActivityForTheSameKid() async throws {
        let repository: any EventStore = LocalEventStore(storageURL: temporaryStorageURL())
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
        try await repository.save(practice)

        let conflicts = try await repository.save(game)

        XCTAssertEqual(conflicts, [
            EventConflict(
                kind: .overlappingKidActivity(kidID),
                eventIDs: [practice.id, game.id]
            ),
        ])
    }

    func testReportsADoubleBookedDriverAcrossKids() async throws {
        let repository: any EventStore = LocalEventStore(storageURL: temporaryStorageURL())
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
        try await repository.save(practice)

        let conflicts = try await repository.save(game)

        XCTAssertEqual(conflicts, [
            EventConflict(
                kind: .doubleBookedDriver("Parent 1"),
                eventIDs: [practice.id, game.id]
            ),
        ])
    }

    func testRejectsAnEventWhoseEndTimeIsNotAfterItsStartTime() async throws {
        let repository: any EventStore = LocalEventStore(storageURL: temporaryStorageURL())
        let event = FamilyEvent(
            title: "Invalid practice",
            kidID: KidID(rawValue: "emma"),
            startTime: Date(timeIntervalSince1970: 1_735_845_200),
            endTime: Date(timeIntervalSince1970: 1_735_841_600),
            source: .manual,
            status: .confirmed
        )

        do {
            _ = try await repository.save(event)
            XCTFail("Expected the store to reject an invalid time range")
        } catch let error as EventValidationError {
            XCTAssertEqual(error, .endTimeMustFollowStartTime)
        }
    }

    private func temporaryStorageURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("json")
    }
}
