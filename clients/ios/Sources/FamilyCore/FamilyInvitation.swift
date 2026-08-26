import Foundation

public struct FamilyInvitationLink: Equatable, Sendable {
    public let code: String

    public init?(url: URL) {
        guard url.scheme?.lowercased() == "famjam", url.host?.lowercased() == "invite",
              let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        code = value
    }
}

public struct FamilyInvitation: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let code: String
    public let role: FamilyMemberRole
    public let expiresAt: Date

    public init(id: String? = nil, code: String, role: FamilyMemberRole, expiresAt: Date) {
        self.id = id ?? code
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

public struct PendingFamilyInvitation: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let email: String?
    public let role: FamilyMemberRole
    public let expiresAt: Date

    public init(id: String, email: String? = nil, role: FamilyMemberRole, expiresAt: Date) {
        self.id = id
        self.email = email
        self.role = role
        self.expiresAt = expiresAt
    }
}

public protocol FamilyInvitationStore: Sendable {
    func create(role: FamilyMemberRole, recipientEmail: String) async throws -> FamilyInvitation
    func pending() async throws -> [PendingFamilyInvitation]
    func cancel(id: String) async throws
    func resend(id: String) async throws -> FamilyInvitation
}

public actor RemoteFamilyInvitationStore: FamilyInvitationStore {
    private struct CreateRequest: Encodable {
        let role: FamilyMemberRole
        let email: String
    }

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

    public func pending() async throws -> [PendingFamilyInvitation] {
        let response = try await transport.send(HTTPRequest(method: .get, url: invitationsURL))
        try response.requireSuccess()
        return try decoder.decode([PendingFamilyInvitation].self, from: response.body)
    }

    public func cancel(id: String) async throws {
        let response = try await transport.send(HTTPRequest(
            method: .delete,
            url: invitationsURL.appending(path: id)
        ))
        try response.requireSuccess()
    }

    public func resend(id: String) async throws -> FamilyInvitation {
        let response = try await transport.send(HTTPRequest(
            method: .post,
            url: invitationsURL.appending(path: id).appending(path: "resend")
        ))
        try response.requireSuccess()
        return try decoder.decode(FamilyInvitation.self, from: response.body)
    }

    public func create(role: FamilyMemberRole, recipientEmail: String) async throws -> FamilyInvitation {
        let response = try await transport.send(HTTPRequest(
            method: .post,
            url: invitationsURL,
            headers: ["Content-Type": "application/json"],
            body: try encoder.encode(CreateRequest(role: role, email: recipientEmail))
        ))
        try response.requireSuccess()
        return try decoder.decode(FamilyInvitation.self, from: response.body)
    }
}
