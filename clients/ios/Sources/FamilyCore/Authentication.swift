import Foundation

public enum AccountRole: String, Codable, Equatable, Sendable {
    case parent
    case kid
}

public struct AuthSession: Codable, Equatable, Sendable {
    public let accountID: String
    public let displayName: String
    public let role: AccountRole

    public init(accountID: String, displayName: String, role: AccountRole) {
        self.accountID = accountID
        self.displayName = displayName
        self.role = role
    }
}

public struct SignInCredentials: Sendable {
    public let email: String
    public let password: String

    public init(email: String, password: String) {
        self.email = email
        self.password = password
    }
}

/// Vendor-neutral authentication seam used by local and remote adapters.
public protocol Authentication: Sendable {
    func currentSession() async throws -> AuthSession?
    func signIn(credentials: SignInCredentials) async throws -> AuthSession
    func signOut() async throws
}

public actor LocalAuthentication: Authentication {
    private var session: AuthSession?

    public init() {
        session = Self.localParentSession
    }

    public func currentSession() async throws -> AuthSession? {
        session
    }

    public func signIn(credentials: SignInCredentials) async throws -> AuthSession {
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
