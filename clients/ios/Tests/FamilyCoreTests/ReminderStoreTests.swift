import Foundation
import XCTest
@testable import FamilyCore

final class ReminderStoreTests: XCTestCase {
    func testCreatesCompletesAndReopensAReminderWithoutAnEndTime() async throws {
        let store: any ReminderStore = LocalReminderStore(storageURL: reminderStorageURL())
        let assigneeID = KidID(rawValue: "kid-1")
        let reminder = FamilyReminder(
            id: UUID(uuidString: "ABCDEFAB-CDEF-4ABC-8DEF-ABCDEFABC001")!,
            title: "Bring the permission slip",
            assigneeIDs: [assigneeID],
            dueAt: Date(timeIntervalSince1970: 1_800_000_000),
            alertLeadTime: .oneHour
        )

        try await store.save(reminder)
        try await store.complete(reminder, by: assigneeID)
        let completedReminders = try await store.reminders()
        let completed = try XCTUnwrap(completedReminders.first)
        XCTAssertEqual(completed.status, .completed)
        XCTAssertEqual(completed.completedByMemberID, assigneeID)
        XCTAssertNotNil(completed.completedAt)

        try await store.reopen(completed)
        let reopenedReminders = try await store.reminders()
        let reopened = try XCTUnwrap(reopenedReminders.first)
        XCTAssertEqual(reopened.status, .open)
        XCTAssertNil(reopened.completedAt)
        XCTAssertNil(reopened.completedByMemberID)
    }

    private func reminderStorageURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("reminders.json")
    }
}
