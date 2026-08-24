import CryptoKit
import Foundation
import XCTest
@testable import FamilyCore

final class RemoteAuthenticationTests: XCTestCase {
    func testSignsInThroughBackendOwnedGoogleOAuthAndStoresSession() async throws {
        let expectedSession = AuthSession(
            accountID: "account-1",
            displayName: "Alex",
            role: .parent,
            accessToken: "secret-token"
        )
        let transport = AuthenticationHTTPTransport(responses: [
            HTTPResponse(statusCode: 200, body: try JSONEncoder().encode(expectedSession))
        ])
        let webSession = StubOAuthWebSession(
            callbackURL: URL(string: "famjam://oauth-callback?stytch_token_type=oauth&token=oauth-token")!
        )
        let authentication: any Authentication = RemoteAuthentication(
            baseURL: URL(string: "https://api.example.com")!,
            transport: transport,
            webSession: webSession
        )

        let session = try await authentication.signIn()

        XCTAssertEqual(session, expectedSession)
        let currentSession = try await authentication.currentSession()
        XCTAssertEqual(currentSession, expectedSession)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.map(\.method), [.post])
        XCTAssertEqual(requests.map(\.url.path), ["/v1/sessions"])
        let exchange = try XCTUnwrap(requests.last?.body)
        let tokenExchange = try JSONDecoder().decode(OAuthTokenExchange.self, from: exchange)
        XCTAssertEqual(tokenExchange.oauthToken, "oauth-token")
        let challenge = await webSession.recordedChallenge()
        let digest = SHA256.hash(data: Data(tokenExchange.codeVerifier.utf8))
        let expectedChallenge = Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        XCTAssertEqual(challenge, expectedChallenge)
    }
}

private struct OAuthTokenExchange: Codable {
    let oauthToken: String
    let codeVerifier: String
}

private actor StubOAuthWebSession: OAuthWebSession {
    let callbackURL: URL
    private var challenge: String?

    init(callbackURL: URL) {
        self.callbackURL = callbackURL
    }

    func authenticate(using authorizationURL: URL, callbackScheme: String) async throws -> URL {
        let components = URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)
        challenge = components?.queryItems?.first(where: { $0.name == "codeChallenge" })?.value
        XCTAssertEqual(components?.path, "/v1/auth/google")
        XCTAssertEqual(callbackScheme, "famjam")
        return callbackURL
    }

    func recordedChallenge() -> String? { challenge }
}

private actor AuthenticationHTTPTransport: HTTPTransport {
    private var responses: [HTTPResponse]
    private var requests: [HTTPRequest] = []
    init(responses: [HTTPResponse]) { self.responses = responses }
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        return responses.removeFirst()
    }
    func recordedRequests() -> [HTTPRequest] { requests }
}
