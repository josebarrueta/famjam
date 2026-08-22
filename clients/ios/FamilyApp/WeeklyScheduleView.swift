import SwiftUI
import FamilyCore

struct WeeklyScheduleView: View {
    @StateObject private var viewModel: WeeklyScheduleViewModel
    @State private var weekStart = Calendar.autoupdatingCurrent.dateInterval(
        of: .weekOfYear,
        for: .now
    )!.start

    init(eventStore: any EventStore) {
        _viewModel = StateObject(wrappedValue: WeeklyScheduleViewModel(eventStore: eventStore))
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage = viewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(daysInWeek, id: \.self) { day in
                        Section(day.formatted(.dateTime.weekday(.wide).month().day())) {
                            let dayEvents = events(on: day)
                            if dayEvents.isEmpty {
                                Text("No activities")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(dayEvents) { event in
                                    EventRow(event: event)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Family Schedule")
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button("Today") {
                        weekStart = startOfCurrentWeek
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        moveWeek(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    Button {
                        moveWeek(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                }
            }
            .task {
                await viewModel.loadEvents()
            }
        }
    }

    private var startOfCurrentWeek: Date {
        Calendar.autoupdatingCurrent.dateInterval(of: .weekOfYear, for: .now)!.start
    }

    private var daysInWeek: [Date] {
        let calendar = Calendar.autoupdatingCurrent
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private func events(on day: Date) -> [FamilyEvent] {
        let calendar = Calendar.autoupdatingCurrent
        return viewModel.events.filter { calendar.isDate($0.startTime, inSameDayAs: day) }
    }

    private func moveWeek(by offset: Int) {
        weekStart = Calendar.autoupdatingCurrent.date(byAdding: .weekOfYear, value: offset, to: weekStart)!
    }
}

private struct EventRow: View {
    let event: FamilyEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.title)
                .font(.headline)
            Text(event.startTime.formatted(date: .omitted, time: .shortened))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let location = event.location, !location.isEmpty {
                Label(location, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
