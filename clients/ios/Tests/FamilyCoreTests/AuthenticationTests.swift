import XCTest
@testable import FamilyCore

final class AuthenticationTests: XCTestCase {
    func testLocalAuthenticationStartsWithAParentSession() async throws {
        let authentication: any Authentication = LocalAuthentication()

        let session = try await authentication.currentSession()

        XCTAssertEqual(session?.role, .parent)
        XCTAssertEqual(session?.displayName, "Local Parent")
    }

    func testLocalAuthenticationCanSignOutAndBackIn() async throws {
        let authentication: any Authentication = LocalAuthentication()
        try await authentication.signOut()
        let signedOutSession = try await authentication.currentSession()
        XCTAssertNil(signedOutSession)

        let session = try await authentication.signIn(
            credentials: SignInCredentials(email: "parent@example.com", password: "password")
        )

        XCTAssertEqual(session.role, .parent)
    }
}
