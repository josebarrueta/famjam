import Foundation
import XCTest
@testable import FamilyCore

final class RemoteEventStoreTests: XCTestCase {
    func testListsEventsFromTheRemoteAPI() async throws {
        let event = sampleEvent()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let transport = RecordingHTTPTransport(
            responses: [HTTPResponse(statusCode: 200, body: try encoder.encode([event]))]
        )
        let store: any EventStore = RemoteEventStore(
            baseURL: URL(string: "https://api.example.com")!,
            transport: transport
        )

        let events = try await store.events()

        XCTAssertEqual(events, [event])
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.first?.method, .get)
        XCTAssertEqual(requests.first?.url.absoluteString, "https://api.example.com/v1/events")
    }

    func testSavesAnEventThroughTheRemoteAPI() async throws {
        let transport = RecordingHTTPTransport(
            responses: [HTTPResponse(statusCode: 200, body: Data("{\"conflicts\":[]}".utf8))]
        )
        let store: any EventStore = RemoteEventStore(
            baseURL: URL(string: "https://api.example.com")!,
            transport: transport
        )

        let conflicts = try await store.save(sampleEvent())

        XCTAssertEqual(conflicts, [])
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.first?.method, .put)
        XCTAssertTrue(requests.first?.url.path.hasPrefix("/v1/events/") == true)
        let body = try XCTUnwrap(requests.first?.body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["participantIDs"] as? [String], ["parent-1"])
    }

    private func sampleEvent() -> FamilyEvent {
        FamilyEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
            title: "Family dinner",
            kidID: nil,
            participantIDs: [KidID(rawValue: "parent-1")],
            startTime: Date(timeIntervalSince1970: 1_735_841_600),
            endTime: Date(timeIntervalSince1970: 1_735_845_200),
            source: .manual,
            status: .confirmed
        )
    }
}

private actor RecordingHTTPTransport: HTTPTransport {
    private var responses: [HTTPResponse]
    private var requests: [HTTPRequest] = []

    init(responses: [HTTPResponse]) {
        self.responses = responses
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        return responses.removeFirst()
    }

    func recordedRequests() -> [HTTPRequest] {
        requests
    }
}
