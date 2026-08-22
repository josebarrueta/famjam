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

    private func temporaryStorageURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("json")
    }
}
