import Foundation

public enum HTTPMethod: String, Equatable, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

public struct HTTPRequest: Equatable, Sendable {
    public let method: HTTPMethod
    public let url: URL
    public let headers: [String: String]
    public let body: Data?

    public init(method: HTTPMethod, url: URL, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

public struct HTTPResponse: Equatable, Sendable {
    public let statusCode: Int
    public let body: Data

    public init(statusCode: Int, body: Data = Data()) {
        self.statusCode = statusCode
        self.body = body
    }
}

public protocol HTTPTransport: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

public actor URLSessionHTTPTransport: HTTPTransport {
    public init() {}

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        request.headers.forEach { urlRequest.setValue($1, forHTTPHeaderField: $0) }
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RemoteStoreError.invalidResponse
        }
        return HTTPResponse(statusCode: httpResponse.statusCode, body: data)
    }
}

public enum RemoteStoreError: Error, Equatable, Sendable {
    case invalidResponse
    case requestFailed(statusCode: Int)
}

extension HTTPResponse {
    func requireSuccess() throws {
        guard (200..<300).contains(statusCode) else {
            throw RemoteStoreError.requestFailed(statusCode: statusCode)
        }
    }
}

public actor RemoteEventStore: EventStore {
    private let eventsURL: URL
    private let transport: any HTTPTransport
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(baseURL: URL, transport: any HTTPTransport = URLSessionHTTPTransport()) {
        eventsURL = baseURL.appending(path: "v1/events")
        self.transport = transport
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func events() async throws -> [FamilyEvent] {
        let response = try await transport.send(HTTPRequest(method: .get, url: eventsURL))
        try response.requireSuccess()
        return try decoder.decode([FamilyEvent].self, from: response.body)
    }

    public func save(_ event: FamilyEvent) async throws -> [EventConflict] {
        let response = try await transport.send(HTTPRequest(
            method: .put,
            url: eventsURL.appending(path: event.id.uuidString),
            headers: ["Content-Type": "application/json"],
            body: try encoder.encode(event)
        ))
        try response.requireSuccess()
        let payload = try decoder.decode(SaveResponse.self, from: response.body)
        return payload.conflicts.compactMap { $0.eventConflict }
    }

    public func delete(_ event: FamilyEvent) async throws {
        let response = try await transport.send(HTTPRequest(
            method: .delete,
            url: eventsURL.appending(path: event.id.uuidString)
        ))
        try response.requireSuccess()
    }

}

private struct SaveResponse: Codable {
    let conflicts: [ConflictPayload]
}

private struct ConflictPayload: Codable {
    let kind: String
    let memberID: String?
    let driver: String?
    let eventIDs: [UUID]

    var eventConflict: EventConflict? {
        let conflictKind: EventConflict.Kind
        switch kind {
        case "overlapping_participant":
            guard let memberID else { return nil }
            conflictKind = .overlappingParticipantActivity(KidID(rawValue: memberID))
        case "double_booked_driver":
            guard let driver else { return nil }
            conflictKind = .doubleBookedDriver(driver)
        default:
            return nil
        }
        return EventConflict(kind: conflictKind, eventIDs: eventIDs)
    }
}
