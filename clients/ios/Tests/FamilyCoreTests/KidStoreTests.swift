import Foundation
import XCTest
@testable import FamilyCore

final class KidStoreTests: XCTestCase {
    func testCreatesAndListsAKid() async throws {
        let store: any KidStore = LocalKidStore(storageURL: temporaryStorageURL())
        let kid = Kid(
            id: KidID(rawValue: "emma"),
            name: "Emma",
            gradeOrBirthYear: "5th grade",
            colorTag: "purple"
        )

        try await store.save(kid)

        let savedKids = try await store.kids()
        XCTAssertEqual(savedKids, [kid])
    }

    func testDeletesAKid() async throws {
        let store: any KidStore = LocalKidStore(storageURL: temporaryStorageURL())
        let kid = Kid(
            id: KidID(rawValue: "emma"),
            name: "Emma",
            gradeOrBirthYear: "5th grade",
            colorTag: "purple"
        )
        try await store.save(kid)

        try await store.delete(kid)

        let savedKids = try await store.kids()
        XCTAssertEqual(savedKids, [])
    }

    func testDoesNotDeleteAKidWithScheduledEvents() async throws {
        let kidStore: any KidStore = LocalKidStore(storageURL: temporaryStorageURL())
        let eventStore: any EventStore = LocalEventStore(storageURL: temporaryStorageURL())
        let kid = Kid(
            id: KidID(rawValue: "emma"),
            name: "Emma",
            gradeOrBirthYear: "5th grade",
            colorTag: "purple"
        )
        try await kidStore.save(kid)
        try await eventStore.save(FamilyEvent(
            title: "Soccer practice",
            kidID: kid.id,
            startTime: Date(timeIntervalSince1970: 1_735_841_600),
            endTime: Date(timeIntervalSince1970: 1_735_845_200),
            source: .manual,
            status: .confirmed
        ))
        let deletionService = KidDeletionService(kidStore: kidStore, eventStore: eventStore)

        do {
            try await deletionService.delete(kid)
            XCTFail("Expected deletion to be blocked")
        } catch let error as KidDeletionError {
            XCTAssertEqual(error, .kidHasScheduledEvents)
        }

        let savedKids = try await kidStore.kids()
        XCTAssertEqual(savedKids, [kid])
    }

    private func temporaryStorageURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("json")
    }
}
