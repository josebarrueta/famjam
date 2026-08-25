import Foundation

public protocol FamilyChangeMonitor: Sendable {
    func hasChanges() async throws -> Bool
}

public actor RemoteFamilyChangeMonitor: FamilyChangeMonitor {
    private struct ChangeResponse: Decodable { let version: Int }

    private let changesURL: URL
    private let transport: any HTTPTransport
    private var lastVersion: Int?

    public init(baseURL: URL, transport: any HTTPTransport) {
        changesURL = baseURL.appending(path: "v1/changes")
        self.transport = transport
    }

    public func hasChanges() async throws -> Bool {
        let response = try await transport.send(HTTPRequest(method: .get, url: changesURL))
        try response.requireSuccess()
        let version = try JSONDecoder().decode(ChangeResponse.self, from: response.body).version
        defer { lastVersion = version }
        guard let lastVersion else { return false }
        return version != lastVersion
    }
}
