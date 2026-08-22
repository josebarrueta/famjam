import Foundation

public struct KidID: Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct Kid: Codable, Equatable, Identifiable, Sendable {
    public let id: KidID
    public var name: String
    public var gradeOrBirthYear: String
    public var colorTag: String

    public init(id: KidID, name: String, gradeOrBirthYear: String, colorTag: String) {
        self.id = id
        self.name = name
        self.gradeOrBirthYear = gradeOrBirthYear
        self.colorTag = colorTag
    }
}

public enum EventSource: String, Codable, Sendable {
    case manual
    case emailSuggested = "email_suggested"
    case voice
}

public enum EventStatus: String, Codable, Sendable {
    case confirmed
    case pendingReview = "pending_review"
}

public struct FamilyEvent: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var kidID: KidID?
    public var startTime: Date
    public var endTime: Date
    public var location: String?
    public var driver: String?
    public var source: EventSource
    public var status: EventStatus

    public init(
        id: UUID = UUID(),
        title: String,
        kidID: KidID?,
        startTime: Date,
        endTime: Date,
        location: String? = nil,
        driver: String? = nil,
        source: EventSource,
        status: EventStatus
    ) {
        self.id = id
        self.title = title
        self.kidID = kidID
        self.startTime = startTime
        self.endTime = endTime
        self.location = location
        self.driver = driver
        self.source = source
        self.status = status
    }
}

public struct EventConflict: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case overlappingKidActivity(KidID)
        case doubleBookedDriver(String)
    }

    public let kind: Kind
    public let eventIDs: [UUID]

    public init(kind: Kind, eventIDs: [UUID]) {
        self.kind = kind
        self.eventIDs = eventIDs
    }
}

public final class EventRepository {
    private let storageURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(storageURL: URL) {
        self.storageURL = storageURL
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    @discardableResult
    public func save(_ event: FamilyEvent) throws -> [EventConflict] {
        var savedEvents = try events()
        savedEvents.removeAll { $0.id == event.id }
        let conflicts = conflicts(for: event, against: savedEvents)
        savedEvents.append(event)
        try write(savedEvents)
        return conflicts
    }

    public func events() throws -> [FamilyEvent] {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            return []
        }

        return try decoder.decode([FamilyEvent].self, from: Data(contentsOf: storageURL))
    }

    private func conflicts(for event: FamilyEvent, against savedEvents: [FamilyEvent]) -> [EventConflict] {
        savedEvents.compactMap { savedEvent in
            guard event.startTime < savedEvent.endTime, savedEvent.startTime < event.endTime else {
                return nil
            }

            if let kidID = event.kidID, kidID == savedEvent.kidID {
                return EventConflict(
                    kind: .overlappingKidActivity(kidID),
                    eventIDs: [savedEvent.id, event.id]
                )
            }

            if let driver = event.driver, !driver.isEmpty, driver == savedEvent.driver {
                return EventConflict(
                    kind: .doubleBookedDriver(driver),
                    eventIDs: [savedEvent.id, event.id]
                )
            }

            return nil
        }
    }

    private func write(_ events: [FamilyEvent]) throws {
        try FileManager.default.createDirectory(
            at: storageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(events).write(to: storageURL, options: .atomic)
    }
}
