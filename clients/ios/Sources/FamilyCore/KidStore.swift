import Foundation

/// Backend-neutral persistence boundary for family members.
public protocol KidStore: Sendable {
    func save(_ kid: Kid) async throws
    func kids() async throws -> [Kid]
}

public actor LocalKidStore: KidStore {
    private let storageURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(storageURL: URL) {
        self.storageURL = storageURL
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    public func save(_ kid: Kid) async throws {
        var savedKids = try await kids()
        savedKids.removeAll { $0.id == kid.id }
        savedKids.append(kid)
        try FileManager.default.createDirectory(
            at: storageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(savedKids).write(to: storageURL, options: .atomic)
    }

    public func kids() async throws -> [Kid] {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            return []
        }

        return try decoder.decode([Kid].self, from: Data(contentsOf: storageURL))
    }
}
