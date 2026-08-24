import Foundation
import XCTest
@testable import FamilyCore

final class RemoteAuthenticationTests: XCTestCase {
    func testSignsInAndStoresTheRemoteSession() async throws {
        let expectedSession = AuthSession(
            accountID: "account-1",
            displayName: "Alex",
            role: .parent,
            accessToken: "secret-token"
        )
        let transport = AuthenticationHTTPTransport(responses: [
            HTTPResponse(statusCode: 200, body: try JSONEncoder().encode(expectedSession))
        ])
        let authentication: any Authentication = RemoteAuthentication(
            baseURL: URL(string: "https://api.example.com")!,
            transport: transport
        )

        let session = try await authentication.signIn(
            credentials: SignInCredentials(email: "alex@example.com", password: "password")
        )

        XCTAssertEqual(session, expectedSession)
        let currentSession = try await authentication.currentSession()
        XCTAssertEqual(currentSession, expectedSession)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.first?.method, .post)
        XCTAssertEqual(requests.first?.url.path, "/v1/sessions")
    }
}

private actor AuthenticationHTTPTransport: HTTPTransport {
    private var responses: [HTTPResponse]
    private var requests: [HTTPRequest] = []
    init(responses: [HTTPResponse]) { self.responses = responses }
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        return responses.removeFirst()
    }
    func recordedRequests() -> [HTTPRequest] { requests }
}
