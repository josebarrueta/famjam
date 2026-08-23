import Foundation
import XCTest
@testable import FamilyCore

final class ConflictNotificationStoreTests: XCTestCase {
    func testStoresAndListsAConflictNotification() async throws {
        let store: any ConflictNotificationStore = LocalConflictNotificationStore(storageURL: temporaryStorageURL())
        let notification = ConflictNotification(message: "Alex's work meeting overlaps with Emma's practice.")

        try await store.save(notification)

        let savedNotifications = try await store.notifications()
        XCTAssertEqual(savedNotifications, [notification])
    }

    private func temporaryStorageURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appendingPathExtension("json")
    }
}
