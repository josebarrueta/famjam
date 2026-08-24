import Foundation

public actor AuthenticatedHTTPTransport: HTTPTransport {
    private let transport: any HTTPTransport
    private let authentication: any Authentication

    public init(transport: any HTTPTransport, authentication: any Authentication) {
        self.transport = transport
        self.authentication = authentication
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var headers = request.headers
        if let token = try await authentication.currentSession()?.accessToken {
            headers["Authorization"] = "Bearer \(token)"
        }
        return try await transport.send(HTTPRequest(
            method: request.method,
            url: request.url,
            headers: headers,
            body: request.body
        ))
    }
}
