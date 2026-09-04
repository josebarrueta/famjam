import Foundation

public enum ReminderStatus: String, Codable, Sendable {
    case open
    case completed
}

public enum ReminderAlertLeadTime: Int, Codable, CaseIterable, Sendable {
    case atDueTime = 0
    case fiveMinutes = 5
    case fifteenMinutes = 15
    case oneHour = 60
    case oneDay = 1_440
}

public struct FamilyReminder: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var assigneeIDs: [KidID]
    public var dueAt: Date
    public var status: ReminderStatus
    public var completedAt: Date?
    public var completedByMemberID: KidID?
    public var alertLeadTime: ReminderAlertLeadTime?

    private enum CodingKeys: String, CodingKey {
        case id, title, assigneeIDs, dueAt, status, completedAt, completedByMemberID
        case alertLeadTime = "alertLeadTimeMinutes"
    }

    public init(
        id: UUID = UUID(),
        title: String,
        assigneeIDs: [KidID],
        dueAt: Date,
        status: ReminderStatus = .open,
        completedAt: Date? = nil,
        completedByMemberID: KidID? = nil,
        alertLeadTime: ReminderAlertLeadTime? = nil
    ) {
        self.id = id
        self.title = title
        self.assigneeIDs = assigneeIDs
        self.dueAt = dueAt
        self.status = status
        self.completedAt = completedAt
        self.completedByMemberID = completedByMemberID
        self.alertLeadTime = alertLeadTime
    }
}

public enum ReminderStoreError: Error, Equatable, Sendable {
    case titleRequired
    case assigneeRequired
    case reminderNotFound
}

public protocol ReminderAlertScheduler: Sendable {
    func schedule(_ reminder: FamilyReminder) async throws
    func cancel(_ reminder: FamilyReminder) async
}

public protocol ReminderStore: Sendable {
    func reminders() async throws -> [FamilyReminder]
    func save(_ reminder: FamilyReminder) async throws
    func delete(_ reminder: FamilyReminder) async throws
    func complete(_ reminder: FamilyReminder, by memberID: KidID) async throws
    func reopen(_ reminder: FamilyReminder) async throws
}

public actor LocalReminderStore: ReminderStore {
    private let storageURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(storageURL: URL) {
        self.storageURL = storageURL
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func reminders() async throws -> [FamilyReminder] {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return [] }
        return try decoder.decode([FamilyReminder].self, from: Data(contentsOf: storageURL))
            .sorted { $0.dueAt < $1.dueAt }
    }

    public func save(_ reminder: FamilyReminder) async throws {
        guard !reminder.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReminderStoreError.titleRequired
        }
        guard !reminder.assigneeIDs.isEmpty else {
            throw ReminderStoreError.assigneeRequired
        }
        var saved = try await reminders()
        saved.removeAll { $0.id == reminder.id }
        saved.append(reminder)
        try write(saved)
    }

    public func delete(_ reminder: FamilyReminder) async throws {
        var saved = try await reminders()
        saved.removeAll { $0.id == reminder.id }
        try write(saved)
    }

    public func complete(_ reminder: FamilyReminder, by memberID: KidID) async throws {
        var saved = try await reminders()
        guard let index = saved.firstIndex(where: { $0.id == reminder.id }) else {
            throw ReminderStoreError.reminderNotFound
        }
        saved[index].status = .completed
        saved[index].completedAt = .now
        saved[index].completedByMemberID = memberID
        try write(saved)
    }

    public func reopen(_ reminder: FamilyReminder) async throws {
        var saved = try await reminders()
        guard let index = saved.firstIndex(where: { $0.id == reminder.id }) else {
            throw ReminderStoreError.reminderNotFound
        }
        saved[index].status = .open
        saved[index].completedAt = nil
        saved[index].completedByMemberID = nil
        try write(saved)
    }

    private func write(_ reminders: [FamilyReminder]) throws {
        try FileManager.default.createDirectory(
            at: storageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(reminders).write(to: storageURL, options: .atomic)
    }
}
