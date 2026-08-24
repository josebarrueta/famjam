import Foundation
import XCTest
@testable import FamilyCore

final class AuthenticatedHTTPTransportTests: XCTestCase {
    func testAddsTheCurrentBearerToken() async throws {
        let baseTransport = BearerRecordingTransport()
        let authentication = TokenAuthentication()
        let transport: any HTTPTransport = AuthenticatedHTTPTransport(
            transport: baseTransport,
            authentication: authentication
        )

        _ = try await transport.send(HTTPRequest(
            method: .get,
            url: URL(string: "https://api.example.com/v1/events")!
        ))

        let request = await baseTransport.lastRequest()
        XCTAssertEqual(request?.headers["Authorization"], "Bearer secret-token")
    }
}

private actor BearerRecordingTransport: HTTPTransport {
    private var request: HTTPRequest?
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        self.request = request
        return HTTPResponse(statusCode: 200)
    }
    func lastRequest() -> HTTPRequest? { request }
}

private actor TokenAuthentication: Authentication {
    func currentSession() async throws -> AuthSession? {
        AuthSession(accountID: "1", displayName: "Alex", role: .parent, accessToken: "secret-token")
    }
    func signIn(credentials: SignInCredentials) async throws -> AuthSession {
        try await currentSession()!
    }
    func signOut() async throws {}
}
