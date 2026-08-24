import SwiftUI
import FamilyCore

struct WeeklyScheduleView: View {
    @StateObject private var viewModel: WeeklyScheduleViewModel
    @State private var weekStart = Calendar.autoupdatingCurrent.dateInterval(
        of: .weekOfYear,
        for: .now
    )!.start
    @State private var isAddingEvent = false
    @State private var editingEvent: FamilyEvent?
    @State private var selectedParticipantID: KidID?

    init(eventStore: any EventStore, memberStore: any FamilyMemberStore, notificationStore: any ConflictNotificationStore) {
        _viewModel = StateObject(
            wrappedValue: WeeklyScheduleViewModel(eventStore: eventStore, memberStore: memberStore, notificationStore: notificationStore)
        )
    }

    var body: some View {
        NavigationStack {
            List {
                FamJamHeader(
                    title: "Let's jam!",
                    subtitle: "One colorful week for the whole crew."
                )
                    .listRowBackground(Color.clear)
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
                                    EventRow(
                                        display: ScheduleEventDisplay(event: event, members: viewModel.members)
                                    )
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            editingEvent = event
                                        }
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("FamJam")
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
                    Menu {
                        Button("All family members") { selectedParticipantID = nil }
                        ForEach(viewModel.members) { member in
                            Button(member.name) { selectedParticipantID = member.id }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    Button {
                        isAddingEvent = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .onAppear {
                Task {
                    await viewModel.loadEvents()
                }
            }
            .sheet(isPresented: $isAddingEvent) {
                AddEventSheet(members: viewModel.members) { event in
                    try await viewModel.addEvent(event)
                }
            }
            .sheet(item: $editingEvent) { event in
                AddEventSheet(
                    event: event,
                    members: viewModel.members,
                    onSave: { event in
                        try await viewModel.addEvent(event)
                    },
                    onDelete: { event in
                        try await viewModel.deleteEvent(event)
                    }
                )
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
        return viewModel.events.filter {
            calendar.isDate($0.startTime, inSameDayAs: day)
                && (selectedParticipantID == nil || $0.participantIDs.contains(selectedParticipantID!))
        }
    }

    private func moveWeek(by offset: Int) {
        weekStart = Calendar.autoupdatingCurrent.date(byAdding: .weekOfYear, value: offset, to: weekStart)!
    }
}

private struct EventRow: View {
    let display: ScheduleEventDisplay

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(familyColorTag: display.kidColorTag))
                .frame(width: 5)
            VStack(alignment: .leading, spacing: 4) {
                Text(display.event.title)
                    .font(.headline)
                if let kidName = display.kidName {
                    Text(kidName)
                        .font(.subheadline)
                        .foregroundStyle(Color(familyColorTag: display.kidColorTag))
                }
                Text(display.event.startTime.formatted(date: .omitted, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let location = display.event.location, !location.isEmpty {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private extension Color {
    init(familyColorTag: String?) {
        switch familyColorTag?.lowercased() {
        case "red": self = .red
        case "orange": self = .orange
        case "yellow": self = .yellow
        case "green": self = .green
        case "blue": self = .blue
        case "purple": self = .purple
        case "pink": self = .pink
        default: self = .gray
        }
    }
}
