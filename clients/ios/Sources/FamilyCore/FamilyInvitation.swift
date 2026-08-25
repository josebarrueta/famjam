import Foundation

public struct FamilyInvitation: Codable, Equatable, Identifiable, Sendable {
    public let code: String
    public let role: FamilyMemberRole
    public let expiresAt: Date

    public var id: String { code }

    public init(code: String, role: FamilyMemberRole, expiresAt: Date) {
        self.code = code
        self.role = role
        self.expiresAt = expiresAt
    }

    public var shareURL: URL {
        var components = URLComponents()
        components.scheme = "famjam"
        components.host = "invite"
        components.queryItems = [URLQueryItem(name: "code", value: code)]
        return components.url!
    }
}

public protocol FamilyInvitationStore: Sendable {
    func create(role: FamilyMemberRole) async throws -> FamilyInvitation
}

public actor RemoteFamilyInvitationStore: FamilyInvitationStore {
    private struct CreateRequest: Encodable { let role: FamilyMemberRole }

    private let invitationsURL: URL
    private let transport: any HTTPTransport
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(baseURL: URL, transport: any HTTPTransport) {
        invitationsURL = baseURL.appending(path: "v1/invitations")
        self.transport = transport
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func create(role: FamilyMemberRole) async throws -> FamilyInvitation {
        let response = try await transport.send(HTTPRequest(
            method: .post,
            url: invitationsURL,
            headers: ["Content-Type": "application/json"],
            body: try encoder.encode(CreateRequest(role: role))
        ))
        try response.requireSuccess()
        return try decoder.decode(FamilyInvitation.self, from: response.body)
    }
}
