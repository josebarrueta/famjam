import Foundation
import XCTest
@testable import FamilyCore

final class FamilyMemberStoreTests: XCTestCase {
    func testStoresAParentAndAKid() async throws {
        let store: any FamilyMemberStore = LocalFamilyMemberStore(storageURL: temporaryStorageURL())
        let parent = FamilyMember(id: KidID(rawValue: "parent-1"), name: "Alex", role: .parent, colorTag: "blue")
        let kid = FamilyMember(id: KidID(rawValue: "kid-1"), name: "Emma", role: .kid, gradeOrBirthYear: "5th grade", colorTag: "purple")

        try await store.save(parent)
        try await store.save(kid)

        let savedMembers = try await store.members()
        XCTAssertEqual(savedMembers, [parent, kid])
    }

    func testDeletesAMemberWithoutScheduledEvents() async throws {
        let store: any FamilyMemberStore = LocalFamilyMemberStore(storageURL: temporaryStorageURL())
        let parent = FamilyMember(id: KidID(rawValue: "parent-1"), name: "Alex", role: .parent, colorTag: "blue")
        try await store.save(parent)

        try await store.delete(parent)

        let savedMembers = try await store.members()
        XCTAssertEqual(savedMembers, [])
    }

    func testBlocksDeletionOfAMemberWithScheduledEvents() async throws {
        let memberStore: any FamilyMemberStore = LocalFamilyMemberStore(storageURL: temporaryStorageURL())
        let eventStore: any EventStore = LocalEventStore(storageURL: temporaryStorageURL())
        let parent = FamilyMember(id: KidID(rawValue: "parent-1"), name: "Alex", role: .parent, colorTag: "blue")
        try await memberStore.save(parent)
        try await eventStore.save(FamilyEvent(
            title: "Work meeting",
            kidID: parent.id,
            participantIDs: [parent.id],
            startTime: Date(timeIntervalSince1970: 1_735_841_600),
            endTime: Date(timeIntervalSince1970: 1_735_845_200),
            source: .manual,
            status: .confirmed
        ))
        let deletionService = FamilyMemberDeletionService(memberStore: memberStore, eventStore: eventStore)

        do {
            try await deletionService.delete(parent)
            XCTFail("Expected deletion to be blocked")
        } catch FamilyMemberDeletionError.hasScheduledEvents {
        }
    }

    func testBlocksDeletionOfAMemberWithAnOpenReminder() async throws {
        let memberStore: any FamilyMemberStore = LocalFamilyMemberStore(storageURL: temporaryStorageURL())
        let eventStore: any EventStore = LocalEventStore(storageURL: temporaryStorageURL())
        let reminderStore: any ReminderStore = LocalReminderStore(storageURL: temporaryStorageURL())
        let parent = FamilyMember(id: KidID(rawValue: "parent-1"), name: "Alex", role: .parent, colorTag: "blue")
        try await memberStore.save(parent)
        try await reminderStore.save(FamilyReminder(
            title: "Bring forms",
            assigneeIDs: [parent.id],
            dueAt: Date(timeIntervalSince1970: 1_735_841_600)
        ))
        let deletionService = FamilyMemberDeletionService(
            memberStore: memberStore,
            eventStore: eventStore,
            reminderStore: reminderStore
        )

        do {
            try await deletionService.delete(parent)
            XCTFail("Expected deletion to be blocked")
        } catch FamilyMemberDeletionError.hasOpenReminders {
        }
    }

    private func temporaryStorageURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appendingPathExtension("json")
    }
}
