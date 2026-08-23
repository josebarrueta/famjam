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

    private func temporaryStorageURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appendingPathExtension("json")
    }
}
