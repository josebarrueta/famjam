import XCTest
@testable import FamilyCore

final class ActivityPresetTests: XCTestCase {
    func testSoccerPresetPrefillsTitleAndSelectedKid() {
        let kidID = KidID(rawValue: "kid-1")

        let prefill = ActivityPreset.soccer.prefill(for: kidID)

        XCTAssertEqual(prefill.title, "Soccer Practice")
        XCTAssertEqual(prefill.participantIDs, [kidID])
        XCTAssertEqual(ActivityPreset.soccer.systemImage, "soccerball")
    }
}
