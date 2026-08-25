import Foundation

public enum AccountRole: String, Codable, Equatable, Sendable {
    case parent
    case kid
}

public struct AuthSession: Codable, Equatable, Sendable {
    public let accountID: String
    public let displayName: String
    public let role: AccountRole
    public let accessToken: String?

    public init(
        accountID: String,
        displayName: String,
        role: AccountRole,
        accessToken: String? = nil
    ) {
        self.accountID = accountID
        self.displayName = displayName
        self.role = role
        self.accessToken = accessToken
    }
}

/// Vendor-neutral authentication seam used by local and remote adapters.
public protocol Authentication: Sendable {
    func currentSession() async throws -> AuthSession?
    func signIn(invitationCode: String?) async throws -> AuthSession
    func signOut() async throws
}

public extension Authentication {
    func signIn() async throws -> AuthSession {
        try await signIn(invitationCode: nil)
    }
}

public actor LocalAuthentication: Authentication {
    private var session: AuthSession?

    public init() {
        session = Self.localParentSession
    }

    public func currentSession() async throws -> AuthSession? {
        session
    }

    public func signIn(invitationCode: String?) async throws -> AuthSession {
        session = Self.localParentSession
        return Self.localParentSession
    }

    public func signOut() async throws {
        session = nil
    }

    private static let localParentSession = AuthSession(
        accountID: "local-parent",
        displayName: "Local Parent",
        role: .parent
    )
}
