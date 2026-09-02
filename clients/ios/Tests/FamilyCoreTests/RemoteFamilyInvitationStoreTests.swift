import Foundation
import XCTest
@testable import FamilyCore

final class RemoteFamilyInvitationStoreTests: XCTestCase {
    func testSendsAnInvitationEmailThroughTheRemoteAPI() async throws {
        let response = """
        {"id":"invite-1","code":"secure-code","email":"kid@example.com","role":"kid","expiresAt":"2026-09-01T12:00:00Z"}
        """.data(using: .utf8)!
        let transport = InvitationHTTPTransport(
            responses: [HTTPResponse(statusCode: 201, body: response)]
        )
        let store: any FamilyInvitationStore = RemoteFamilyInvitationStore(
            baseURL: URL(string: "https://api.example.com")!,
            transport: transport
        )

        let invitation = try await store.create(
            role: .kid,
            recipientEmail: "kid@example.com",
            guardianConsent: true
        )

        XCTAssertEqual(invitation.id, "invite-1")
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.first?.method, .post)
        XCTAssertEqual(requests.first?.url.path, "/v1/invitations")
        let body = try JSONSerialization.jsonObject(with: requests.first!.body!) as? [String: Any]
        XCTAssertEqual(body?["role"] as? String, "kid")
        XCTAssertEqual(body?["email"] as? String, "kid@example.com")
        XCTAssertEqual(body?["guardianConsent"] as? Bool, true)
    }

    func testListsPendingInvitationsFromTheRemoteAPI() async throws {
        let response = """
        [{"id":"invite-1","email":"kid@example.com","role":"kid","expiresAt":"2026-09-01T12:00:00Z"}]
        """.data(using: .utf8)!
        let transport = InvitationHTTPTransport(
            responses: [HTTPResponse(statusCode: 200, body: response)]
        )
        let store: any FamilyInvitationStore = RemoteFamilyInvitationStore(
            baseURL: URL(string: "https://api.example.com")!,
            transport: transport
        )

        let invitations = try await store.pending()

        XCTAssertEqual(invitations.map(\.id), ["invite-1"])
        XCTAssertEqual(invitations.map(\.role), [.kid])
        XCTAssertEqual(invitations.map(\.email), ["kid@example.com"])
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.first?.method, .get)
        XCTAssertEqual(requests.first?.url.path, "/v1/invitations")
    }

    func testCancelsAnInvitationThroughTheRemoteAPI() async throws {
        let transport = InvitationHTTPTransport(responses: [HTTPResponse(statusCode: 204)])
        let store: any FamilyInvitationStore = RemoteFamilyInvitationStore(
            baseURL: URL(string: "https://api.example.com")!,
            transport: transport
        )

        try await store.cancel(id: "invite-1")

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.first?.method, .delete)
        XCTAssertEqual(requests.first?.url.path, "/v1/invitations/invite-1")
    }

    func testResendsAnInvitationThroughTheRemoteAPI() async throws {
        let response = """
        {"id":"invite-1","code":"replacement-code","role":"parent","expiresAt":"2026-09-01T12:00:00Z"}
        """.data(using: .utf8)!
        let transport = InvitationHTTPTransport(
            responses: [HTTPResponse(statusCode: 200, body: response)]
        )
        let store: any FamilyInvitationStore = RemoteFamilyInvitationStore(
            baseURL: URL(string: "https://api.example.com")!,
            transport: transport
        )

        let invitation = try await store.resend(id: "invite-1")

        XCTAssertEqual(invitation.id, "invite-1")
        XCTAssertEqual(invitation.code, "replacement-code")
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.first?.method, .post)
        XCTAssertEqual(requests.first?.url.path, "/v1/invitations/invite-1/resend")
    }
}

private actor InvitationHTTPTransport: HTTPTransport {
    private var responses: [HTTPResponse]
    private var requests: [HTTPRequest] = []
    init(responses: [HTTPResponse]) { self.responses = responses }
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        return responses.removeFirst()
    }
    func recordedRequests() -> [HTTPRequest] { requests }
}
