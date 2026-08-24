import Foundation

public actor RemoteFamilyMemberStore: FamilyMemberStore {
    private let membersURL: URL
    private let transport: any HTTPTransport
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(baseURL: URL, transport: any HTTPTransport = URLSessionHTTPTransport()) {
        membersURL = baseURL.appending(path: "v1/family-members")
        self.transport = transport
    }

    public func members() async throws -> [FamilyMember] {
        let response = try await transport.send(HTTPRequest(method: .get, url: membersURL))
        try response.requireSuccess()
        return try decoder.decode([FamilyMember].self, from: response.body)
    }

    public func save(_ member: FamilyMember) async throws {
        let response = try await transport.send(HTTPRequest(
            method: .put,
            url: membersURL.appending(path: member.id.rawValue),
            headers: ["Content-Type": "application/json"],
            body: try encoder.encode(member)
        ))
        try response.requireSuccess()
    }

    public func delete(_ member: FamilyMember) async throws {
        let response = try await transport.send(HTTPRequest(
            method: .delete,
            url: membersURL.appending(path: member.id.rawValue)
        ))
        try response.requireSuccess()
    }
}
