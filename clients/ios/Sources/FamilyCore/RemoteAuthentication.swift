import Foundation

public actor RemoteAuthentication: Authentication {
    private let sessionsURL: URL
    private let transport: any HTTPTransport
    private var session: AuthSession?

    public init(baseURL: URL, transport: any HTTPTransport = URLSessionHTTPTransport()) {
        sessionsURL = baseURL.appending(path: "v1/sessions")
        self.transport = transport
    }

    public func currentSession() async throws -> AuthSession? {
        session
    }

    public func signIn(credentials: SignInCredentials) async throws -> AuthSession {
        let response = try await transport.send(HTTPRequest(
            method: .post,
            url: sessionsURL,
            headers: ["Content-Type": "application/json"],
            body: try JSONEncoder().encode(credentials)
        ))
        try response.requireSuccess()
        let authenticatedSession = try JSONDecoder().decode(AuthSession.self, from: response.body)
        session = authenticatedSession
        return authenticatedSession
    }

    public func signOut() async throws {
        guard let session else { return }
        let headers = session.accessToken.map { ["Authorization": "Bearer \($0)"] } ?? [:]
        let response = try await transport.send(HTTPRequest(
            method: .delete,
            url: sessionsURL,
            headers: headers
        ))
        try response.requireSuccess()
        self.session = nil
    }
}
