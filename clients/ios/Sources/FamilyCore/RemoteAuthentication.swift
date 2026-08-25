import CryptoKit
import Foundation

public enum RemoteAuthenticationError: Error, Equatable {
    case invalidOAuthCallback
}

public actor RemoteAuthentication: Authentication {
    private struct OAuthTokenExchange: Encodable {
        let oauthToken: String
        let codeVerifier: String
        let invitationCode: String?
    }

    private let authorizationURL: URL
    private let sessionsURL: URL
    private let transport: any HTTPTransport
    private let webSession: any OAuthWebSession
    private var session: AuthSession?

    public init(
        baseURL: URL,
        transport: any HTTPTransport,
        webSession: any OAuthWebSession
    ) {
        authorizationURL = baseURL.appending(path: "v1/auth/google")
        sessionsURL = baseURL.appending(path: "v1/sessions")
        self.transport = transport
        self.webSession = webSession
    }

    @MainActor
    public init(
        baseURL: URL,
        transport: any HTTPTransport = URLSessionHTTPTransport()
    ) {
        self.init(
            baseURL: baseURL,
            transport: transport,
            webSession: SystemOAuthWebSession()
        )
    }

    public func currentSession() async throws -> AuthSession? {
        session
    }

    public func signIn(invitationCode: String?) async throws -> AuthSession {
        let codeVerifier = UUID().uuidString + UUID().uuidString
        let digest = SHA256.hash(data: Data(codeVerifier.utf8))
        let codeChallenge = Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        var components = URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "codeChallenge", value: codeChallenge)]
        guard let securedAuthorizationURL = components?.url else {
            throw RemoteAuthenticationError.invalidOAuthCallback
        }
        let callbackURL = try await webSession.authenticate(
            using: securedAuthorizationURL,
            callbackScheme: "famjam"
        )
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              components.queryItems?.first(where: { $0.name == "stytch_token_type" })?.value == "oauth",
              let oauthToken = components.queryItems?.first(where: { $0.name == "token" })?.value,
              !oauthToken.isEmpty else {
            throw RemoteAuthenticationError.invalidOAuthCallback
        }
        let response = try await transport.send(HTTPRequest(
            method: .post,
            url: sessionsURL,
            headers: ["Content-Type": "application/json"],
            body: try JSONEncoder().encode(OAuthTokenExchange(
                oauthToken: oauthToken,
                codeVerifier: codeVerifier,
                invitationCode: invitationCode
            ))
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
