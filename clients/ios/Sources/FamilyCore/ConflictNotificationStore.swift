import Foundation

public struct ConflictNotification: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let message: String
    public let createdAt: Date

    public init(id: UUID = UUID(), message: String, createdAt: Date = .now) {
        self.id = id
        self.message = message
        self.createdAt = createdAt
    }
}

public protocol ConflictNotificationStore: Sendable {
    func save(_ notification: ConflictNotification) async throws
    func clear() async throws
    func notifications() async throws -> [ConflictNotification]
}

public actor LocalConflictNotificationStore: ConflictNotificationStore {
    private let storageURL: URL
    public init(storageURL: URL) { self.storageURL = storageURL }
    public func save(_ notification: ConflictNotification) async throws {
        var saved = try await notifications()
        saved.append(notification)
        try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(saved).write(to: storageURL, options: .atomic)
    }
    public func clear() async throws {
        try FileManager.default.removeItem(at: storageURL)
    }
    public func notifications() async throws -> [ConflictNotification] {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return [] }
        return try JSONDecoder().decode([ConflictNotification].self, from: Data(contentsOf: storageURL))
    }
}
