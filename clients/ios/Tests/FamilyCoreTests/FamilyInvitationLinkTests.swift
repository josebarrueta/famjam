import Foundation
import XCTest
@testable import FamilyCore

final class FamilyInvitationLinkTests: XCTestCase {
    func testExtractsTheCodeFromARallyrooInvitationLink() {
        let url = URL(string: "rallyroo://invite?code=secure-code-123")!

        XCTAssertEqual(FamilyInvitationLink(url: url)?.code, "secure-code-123")
    }

    func testRejectsLinksWithoutAnInvitationCode() {
        XCTAssertNil(FamilyInvitationLink(url: URL(string: "rallyroo://invite")!))
        XCTAssertNil(FamilyInvitationLink(url: URL(string: "rallyroo://settings?code=secure-code")!))
        XCTAssertNil(FamilyInvitationLink(url: URL(string: "https://example.com/invite?code=secure-code")!))
    }

    func testShareURLRoundTripsThroughTheInvitationLink() {
        let invitation = FamilyInvitation(
            id: "invite-1",
            code: "secure-code-123",
            role: .kid,
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertEqual(invitation.shareURL.absoluteString, "rallyroo://invite?code=secure-code-123")
        XCTAssertEqual(FamilyInvitationLink(url: invitation.shareURL)?.code, invitation.code)
    }
}
