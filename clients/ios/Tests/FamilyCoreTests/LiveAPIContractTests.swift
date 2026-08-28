import Foundation
import XCTest
@testable import FamilyCore

final class LiveAPIContractTests: XCTestCase {
    func testRemoteStoresMatchTheRunningRallyrooAPI() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let value = environment["RALLYROO_CONTRACT_BASE_URL"], let baseURL = URL(string: value) else {
            throw XCTSkip("RALLYROO_CONTRACT_BASE_URL is not configured")
        }
        let authentication = ContractAuthentication()
        let transport = AuthenticatedHTTPTransport(
            transport: ContractHTTPTransport(),
            authentication: authentication
        )
        let members = RemoteFamilyMemberStore(baseURL: baseURL, transport: transport)
        let events = RemoteEventStore(baseURL: baseURL, transport: transport)
        let invitations = RemoteFamilyInvitationStore(baseURL: baseURL, transport: transport)
        let kidID = KidID(rawValue: "kid-1")
        let event = FamilyEvent(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000123")!,
            title: "Live contract rehearsal",
            kidID: kidID,
            participantIDs: [kidID],
            startTime: ISO8601DateFormatter().date(from: "2026-09-02T18:00:00Z")!,
            endTime: ISO8601DateFormatter().date(from: "2026-09-02T19:00:00Z")!,
            location: "123 Main St",
            source: .manual,
            status: .confirmed
        )

        let loadedMembers = try await members.members()
        XCTAssertEqual(loadedMembers.map(\.id.rawValue), ["kid-1", "parent-1"])
        let conflicts = try await events.save(event)
        XCTAssertEqual(conflicts, [])
        let savedEvents = try await events.events()
        XCTAssertEqual(savedEvents.map(\.id), [event.id])

        let invitation = try await invitations.create(role: .kid, recipientEmail: "kid@example.com")
        XCTAssertFalse(invitation.code.isEmpty)
        let pending = try await invitations.pending()
        XCTAssertEqual(pending.map(\.id), [invitation.id])
        try await invitations.cancel(id: invitation.id)
        let pendingAfterCancellation = try await invitations.pending()
        XCTAssertEqual(pendingAfterCancellation, [])

        try await events.delete(event)
        let eventsAfterDeletion = try await events.events()
        XCTAssertEqual(eventsAfterDeletion, [])
    }
}

private actor ContractHTTPTransport: HTTPTransport {
    private let transport = URLSessionHTTPTransport()

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let response = try await transport.send(request)
        if !(200..<300).contains(response.statusCode) {
            print("Contract request failed: \(request.method.rawValue) \(request.url)")
            print(String(data: request.body ?? Data(), encoding: .utf8) ?? "")
            print(String(data: response.body, encoding: .utf8) ?? "")
        }
        return response
    }
}

private actor ContractAuthentication: Authentication {
    private let session = AuthSession(
        accountID: "parent-1",
        displayName: "Alex",
        role: .parent,
        accessToken: "contract-token"
    )

    func currentSession() async throws -> AuthSession? { session }
    func signIn(
        with provider: AuthenticationProvider,
        invitationCode: String?
    ) async throws -> AuthSession { session }
    func signOut() async throws {}
}
