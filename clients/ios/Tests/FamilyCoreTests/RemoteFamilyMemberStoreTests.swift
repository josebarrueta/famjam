import Foundation
import XCTest
@testable import FamilyCore

final class RemoteFamilyMemberStoreTests: XCTestCase {
    func testListsFamilyMembersFromTheRemoteAPI() async throws {
        let member = FamilyMember(
            id: KidID(rawValue: "parent-1"),
            name: "Alex",
            role: .parent,
            colorTag: "blue"
        )
        let transport = FamilyMemberHTTPTransport(
            responses: [HTTPResponse(statusCode: 200, body: try JSONEncoder().encode([member]))]
        )
        let store: any FamilyMemberStore = RemoteFamilyMemberStore(
            baseURL: URL(string: "https://api.example.com")!,
            transport: transport
        )

        let members = try await store.members()

        XCTAssertEqual(members, [member])
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.first?.url.absoluteString, "https://api.example.com/v1/family-members")
    }

    func testSavesAFamilyMemberThroughTheRemoteAPI() async throws {
        let transport = FamilyMemberHTTPTransport(responses: [HTTPResponse(statusCode: 204)])
        let store: any FamilyMemberStore = RemoteFamilyMemberStore(
            baseURL: URL(string: "https://api.example.com")!,
            transport: transport
        )
        let member = FamilyMember(
            id: KidID(rawValue: "parent-1"),
            name: "Alex",
            role: .parent,
            colorTag: "blue"
        )

        try await store.save(member)

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.first?.method, .put)
        XCTAssertEqual(requests.first?.url.path, "/v1/family-members/parent-1")
    }
}

private actor FamilyMemberHTTPTransport: HTTPTransport {
    private var responses: [HTTPResponse]
    private var requests: [HTTPRequest] = []
    init(responses: [HTTPResponse]) { self.responses = responses }
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        return responses.removeFirst()
    }
    func recordedRequests() -> [HTTPRequest] { requests }
}
