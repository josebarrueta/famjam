import Foundation

public protocol DeviceRegistrationStore: Sendable {
    func register(token: String) async throws
    func unregister(token: String) async throws
}

public actor RemoteDeviceRegistrationStore: DeviceRegistrationStore {
    private let devicesURL: URL
    private let transport: any HTTPTransport

    public init(baseURL: URL, transport: any HTTPTransport) {
        devicesURL = baseURL.appending(path: "v1/devices")
        self.transport = transport
    }

    public func register(token: String) async throws {
        let response = try await transport.send(HTTPRequest(
            method: .put,
            url: devicesURL.appending(path: token)
        ))
        try response.requireSuccess()
    }

    public func unregister(token: String) async throws {
        let response = try await transport.send(HTTPRequest(
            method: .delete,
            url: devicesURL.appending(path: token)
        ))
        try response.requireSuccess()
    }
}
