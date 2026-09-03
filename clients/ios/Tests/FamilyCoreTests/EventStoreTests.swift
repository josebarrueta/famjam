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

    func testReportsAConflictOnAFutureRecurringOccurrence() async throws {
        let repository: any EventStore = LocalEventStore(storageURL: temporaryStorageURL())
        let kidID = KidID(rawValue: "emma")
        let start = Date(timeIntervalSince1970: 1_735_841_600)
        let existing = FamilyEvent(
            title: "Doctor appointment",
            kidID: kidID,
            startTime: start.addingTimeInterval(7 * 24 * 60 * 60),
            endTime: start.addingTimeInterval(7 * 24 * 60 * 60 + 3600),
            source: .manual,
            status: .confirmed
        )
        let recurring = FamilyEvent(
            title: "Soccer practice",
            kidID: kidID,
            startTime: start,
            endTime: start.addingTimeInterval(3600),
            source: .manual,
            status: .confirmed,
            recurrence: EventRecurrence(
                frequency: .weekly,
                endDate: start.addingTimeInterval(14 * 24 * 60 * 60)
            )
        )
        try await repository.save(existing)

        let conflicts = try await repository.save(recurring)

        XCTAssertEqual(conflicts.first?.kind, .overlappingKidActivity(kidID))
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

    func testReportsAnOverlappingActivityForTheSameParent() async throws {
        let repository: any EventStore = LocalEventStore(storageURL: temporaryStorageURL())
        let parentID = KidID(rawValue: "parent-1")
        let workMeeting = FamilyEvent(
            title: "Work meeting",
            kidID: nil,
            participantIDs: [parentID],
            startTime: Date(timeIntervalSince1970: 1_735_841_600),
            endTime: Date(timeIntervalSince1970: 1_735_845_200),
            source: .manual,
            status: .confirmed
        )
        let doctorAppointment = FamilyEvent(
            title: "Doctor appointment",
            kidID: nil,
            participantIDs: [parentID],
            startTime: Date(timeIntervalSince1970: 1_735_843_400),
            endTime: Date(timeIntervalSince1970: 1_735_847_000),
            source: .manual,
            status: .confirmed
        )
        try await repository.save(workMeeting)

        let conflicts = try await repository.save(doctorAppointment)

        XCTAssertEqual(conflicts, [
            EventConflict(
                kind: .overlappingParticipantActivity(parentID),
                eventIDs: [workMeeting.id, doctorAppointment.id]
            ),
        ])
    }

    func testRenamingARecurringEventDoesNotConflictWithTheSameSeries() async throws {
        let repository: any EventStore = LocalEventStore(storageURL: temporaryStorageURL())
        let eventID = UUID(uuidString: "ABCDEFAB-CDEF-4ABC-8DEF-ABCDEFABCDEA")!
        let start = Date(timeIntervalSince1970: 1_735_848_800)
        let recurrence = EventRecurrence(
            frequency: .weekly,
            endDate: start.addingTimeInterval(12 * 7 * 24 * 60 * 60)
        )
        let original = FamilyEvent(
            id: eventID,
            title: "Weekly practice",
            kidID: KidID(rawValue: "jake"),
            startTime: start,
            endTime: start.addingTimeInterval(3_600),
            source: .manual,
            status: .confirmed,
            recurrence: recurrence
        )
        let renamed = FamilyEvent(
            id: eventID,
            title: "Renamed weekly practice",
            kidID: KidID(rawValue: "jake"),
            startTime: start,
            endTime: start.addingTimeInterval(3_600),
            source: .manual,
            status: .confirmed,
            recurrence: recurrence
        )
        try await repository.save(original)

        let conflicts = try await repository.save(renamed)

        let savedEvents = try await repository.events()
        XCTAssertEqual(conflicts, [])
        XCTAssertEqual(savedEvents, [renamed])
    }

    func testEditingAnEventStillReportsAConflictWithASeparateEvent() async throws {
        let repository: any EventStore = LocalEventStore(storageURL: temporaryStorageURL())
        let kidID = KidID(rawValue: "jake")
        let existing = FamilyEvent(
            title: "Soccer practice",
            kidID: kidID,
            startTime: Date(timeIntervalSince1970: 1_735_841_600),
            endTime: Date(timeIntervalSince1970: 1_735_845_200),
            source: .manual,
            status: .confirmed
        )
        let eventID = UUID(uuidString: "ABCDEFAB-CDEF-4ABC-8DEF-ABCDEFABCDEB")!
        let original = FamilyEvent(
            id: eventID,
            title: "Doctor appointment",
            kidID: kidID,
            startTime: Date(timeIntervalSince1970: 1_735_848_800),
            endTime: Date(timeIntervalSince1970: 1_735_852_400),
            source: .manual,
            status: .confirmed
        )
        let edited = FamilyEvent(
            id: eventID,
            title: "Earlier doctor appointment",
            kidID: kidID,
            startTime: Date(timeIntervalSince1970: 1_735_843_400),
            endTime: Date(timeIntervalSince1970: 1_735_847_000),
            source: .manual,
            status: .confirmed
        )
        try await repository.save(existing)
        try await repository.save(original)

        let conflicts = try await repository.save(edited)

        XCTAssertEqual(conflicts, [
            EventConflict(
                kind: .overlappingKidActivity(kidID),
                eventIDs: [existing.id, edited.id]
            ),
        ])
    }

    func testUpdatesAnEventWithTheSameID() async throws {
        let repository: any EventStore = LocalEventStore(storageURL: temporaryStorageURL())
        let eventID = UUID(uuidString: "00000000-0000-0000-0000-000000000005")!
        let originalEvent = FamilyEvent(
            id: eventID,
            title: "Soccer practice",
            kidID: KidID(rawValue: "jake"),
            startTime: Date(timeIntervalSince1970: 1_735_841_600),
            endTime: Date(timeIntervalSince1970: 1_735_845_200),
            source: .manual,
            status: .confirmed
        )
        let updatedEvent = FamilyEvent(
            id: eventID,
            title: "Soccer game",
            kidID: KidID(rawValue: "jake"),
            startTime: Date(timeIntervalSince1970: 1_735_843_400),
            endTime: Date(timeIntervalSince1970: 1_735_847_000),
            source: .manual,
            status: .confirmed
        )
        try await repository.save(originalEvent)

        try await repository.save(updatedEvent)

        let savedEvents = try await repository.events()
        XCTAssertEqual(savedEvents, [updatedEvent])
    }

    func testDeletesAnEvent() async throws {
        let repository: any EventStore = LocalEventStore(storageURL: temporaryStorageURL())
        let event = FamilyEvent(
            title: "Soccer practice",
            kidID: KidID(rawValue: "jake"),
            startTime: Date(timeIntervalSince1970: 1_735_841_600),
            endTime: Date(timeIntervalSince1970: 1_735_845_200),
            source: .manual,
            status: .confirmed
        )
        try await repository.save(event)

        try await repository.delete(event)

        let savedEvents = try await repository.events()
        XCTAssertEqual(savedEvents, [])
    }

    private func temporaryStorageURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("json")
    }
}
