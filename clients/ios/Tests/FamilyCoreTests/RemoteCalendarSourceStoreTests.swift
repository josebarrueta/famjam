import Foundation
import XCTest
@testable import FamilyCore

final class RemoteCalendarSourceStoreTests: XCTestCase {
    func testCreatesAParticipantScopedCalendarSubscription() async throws {
        let response = Data("""
        {
          "id":"00000000-0000-4000-8000-000000000301",
          "name":"Emma TeamSnap",
          "participantIDs":["kid-1"],
          "status":"pending",
          "lastSyncedAt":null,
          "lastError":null
        }
        """.utf8)
        let transport = CalendarRecordingTransport(
            responses: [HTTPResponse(statusCode: 201, body: response)]
        )
        let store: any CalendarSourceStore = RemoteCalendarSourceStore(
            baseURL: URL(string: "https://api.example.com")!,
            transport: transport
        )

        let source = try await store.create(
            name: "Emma TeamSnap",
            url: URL(string: "https://ical.example/secret.ics")!,
            participantIDs: [KidID(rawValue: "kid-1")]
        )

        XCTAssertEqual(source.name, "Emma TeamSnap")
        XCTAssertEqual(source.status, .pending)
        let requests = await transport.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(request.url.path, "/v1/calendar-sources")
        let body = try XCTUnwrap(request.body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["url"] as? String, "https://ical.example/secret.ics")
        XCTAssertEqual(json["participantIDs"] as? [String], ["kid-1"])
    }
}

private actor CalendarRecordingTransport: HTTPTransport {
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
