import Foundation

public struct EventRecurrence: Codable, Equatable, Sendable {
    public enum Frequency: String, Codable, CaseIterable, Sendable {
        case daily
        case weekly
        case monthly
    }

    public let frequency: Frequency
    public let interval: Int
    public let endDate: Date

    public init(frequency: Frequency, interval: Int = 1, endDate: Date) {
        self.frequency = frequency
        self.interval = max(1, interval)
        self.endDate = endDate
    }
}

public struct EventOccurrence: Identifiable, Equatable, Sendable {
    public let id: String
    public let event: FamilyEvent
    public let sourceEvent: FamilyEvent
}

public enum EventOccurrenceExpander {
    public static func occurrences(
        of events: [FamilyEvent],
        in range: DateInterval,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [EventOccurrence] {
        events.flatMap { occurrences(of: $0, in: range, calendar: calendar) }
            .sorted { $0.event.startTime < $1.event.startTime }
    }

    private static func occurrences(
        of source: FamilyEvent,
        in range: DateInterval,
        calendar: Calendar
    ) -> [EventOccurrence] {
        guard let recurrence = source.recurrence else {
            guard range.contains(source.startTime) else { return [] }
            return [occurrence(source: source, startTime: source.startTime)]
        }

        var result: [EventOccurrence] = []
        var startTime = source.startTime
        while startTime < range.end, startTime <= recurrence.endDate {
            if startTime >= range.start {
                result.append(occurrence(source: source, startTime: startTime))
            }
            guard let next = nextDate(after: startTime, recurrence: recurrence, calendar: calendar),
                  next > startTime else { break }
            startTime = next
        }
        return result
    }

    private static func occurrence(source: FamilyEvent, startTime: Date) -> EventOccurrence {
        var event = source
        event.startTime = startTime
        event.endTime = startTime.addingTimeInterval(source.endTime.timeIntervalSince(source.startTime))
        return EventOccurrence(
            id: "\(source.id.uuidString)-\(Int(startTime.timeIntervalSince1970))",
            event: event,
            sourceEvent: source
        )
    }

    private static func nextDate(
        after date: Date,
        recurrence: EventRecurrence,
        calendar: Calendar
    ) -> Date? {
        switch recurrence.frequency {
        case .daily:
            calendar.date(byAdding: .day, value: recurrence.interval, to: date)
        case .weekly:
            calendar.date(byAdding: .day, value: recurrence.interval * 7, to: date)
        case .monthly:
            calendar.date(byAdding: .month, value: recurrence.interval, to: date)
        }
    }
}
