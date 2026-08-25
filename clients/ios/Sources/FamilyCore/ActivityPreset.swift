public struct ActivityEventPrefill: Equatable, Sendable {
    public let title: String
    public let participantIDs: [KidID]

    public init(title: String, participantIDs: [KidID]) {
        self.title = title
        self.participantIDs = participantIDs
    }
}

public enum ActivityPreset: String, CaseIterable, Identifiable, Sendable {
    case soccer
    case chess
    case swimming
    case music
    case basketball

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .soccer: "Soccer Practice"
        case .chess: "Chess Class"
        case .swimming: "Swim Practice"
        case .music: "Music Lesson"
        case .basketball: "Basketball Practice"
        }
    }

    public var systemImage: String {
        switch self {
        case .soccer: "soccerball"
        case .chess: "checkerboard.rectangle"
        case .swimming: "figure.pool.swim"
        case .music: "music.note"
        case .basketball: "basketball"
        }
    }

    public func prefill(for participantID: KidID) -> ActivityEventPrefill {
        ActivityEventPrefill(title: title, participantIDs: [participantID])
    }
}
