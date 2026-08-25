import SwiftUI
import FamilyCore

struct AddEventSheet: View {
    let onSave: (FamilyEvent) async throws -> [EventConflict]
    let onDelete: ((FamilyEvent) async throws -> Void)?
    let members: [FamilyMember]

    private let existingEvent: FamilyEvent?
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var selectedParticipantIDs: Set<KidID>
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var location: String
    @State private var driver: String
    @State private var isSaving = false
    @State private var alertMessage = ""
    @State private var dismissAfterAlert = false
    @State private var isShowingAlert = false
    @State private var isShowingDeleteConfirmation = false

    init(
        event: FamilyEvent? = nil,
        prefill: ActivityEventPrefill? = nil,
        members: [FamilyMember],
        onSave: @escaping (FamilyEvent) async throws -> [EventConflict],
        onDelete: ((FamilyEvent) async throws -> Void)? = nil
    ) {
        existingEvent = event
        self.onSave = onSave
        self.onDelete = onDelete
        self.members = members
        _title = State(initialValue: event?.title ?? prefill?.title ?? "")
        _selectedParticipantIDs = State(initialValue: Set(
            event?.participantIDs ?? event?.kidID.map { [$0] } ?? prefill?.participantIDs ?? []
        ))
        _startTime = State(initialValue: event?.startTime ?? .now)
        _endTime = State(initialValue: event?.endTime ?? .now.addingTimeInterval(60 * 60))
        _location = State(initialValue: event?.location ?? "")
        _driver = State(initialValue: event?.driver ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Activity") {
                    TextField("Title", text: $title)
                    ForEach(members) { member in
                        Toggle(member.name, isOn: participantBinding(for: member.id))
                    }
                }

                Section("Time") {
                    DatePicker("Starts", selection: $startTime)
                    DatePicker("Ends", selection: $endTime)
                }

                Section("Details") {
                    TextField("Location", text: $location)
                    TextField("Driver", text: $driver)
                }
            }
            .navigationTitle(existingEvent == nil ? "Add Event" : "Edit Event")
            .toolbar {
                if existingEvent != nil, onDelete != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Delete", role: .destructive) {
                            isShowingDeleteConfirmation = true
                        }
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .alert("Event status", isPresented: $isShowingAlert) {
                Button("OK") {
                    if dismissAfterAlert {
                        dismiss()
                    }
                }
            } message: {
                Text(alertMessage)
            }
            .confirmationDialog(
                "Delete this event?",
                isPresented: $isShowingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    delete()
                }
            } message: {
                Text("This cannot be undone.")
            }
        }
    }

    private func save() {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let conflicts = try await onSave(event)
                if conflicts.isEmpty {
                    dismiss()
                } else {
                    alertMessage = ConflictNotificationMessage.make(
                        event: event,
                        conflicts: conflicts,
                        members: members
                    )
                    dismissAfterAlert = true
                    isShowingAlert = true
                }
            } catch EventValidationError.endTimeMustFollowStartTime {
                alertMessage = "The end time must be after the start time."
                dismissAfterAlert = false
                isShowingAlert = true
            } catch {
                alertMessage = "The event could not be saved."
                dismissAfterAlert = false
                isShowingAlert = true
            }
        }
    }

    private func delete() {
        guard let existingEvent, let onDelete else {
            return
        }

        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await onDelete(existingEvent)
                dismiss()
            } catch {
                alertMessage = "The event could not be deleted."
                dismissAfterAlert = false
                isShowingAlert = true
            }
        }
    }

    private var event: FamilyEvent {
        FamilyEvent(
            id: existingEvent?.id ?? UUID(),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            kidID: selectedParticipantIDs.first,
            participantIDs: Array(selectedParticipantIDs),
            startTime: startTime,
            endTime: endTime,
            location: optionalText(location),
            driver: optionalText(driver),
            source: existingEvent?.source ?? .manual,
            status: existingEvent?.status ?? .confirmed
        )
    }

    private func participantBinding(for memberID: KidID) -> Binding<Bool> {
        Binding(
            get: { selectedParticipantIDs.contains(memberID) },
            set: { isSelected in
                if isSelected {
                    selectedParticipantIDs.insert(memberID)
                } else {
                    selectedParticipantIDs.remove(memberID)
                }
            }
        )
    }

    private func optionalText(_ value: String) -> String? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}
