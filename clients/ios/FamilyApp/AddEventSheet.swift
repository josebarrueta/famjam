import SwiftUI
import FamilyCore

struct AddEventSheet: View {
    let onSave: (FamilyEvent) async throws -> [EventConflict]

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var kidName = ""
    @State private var startTime = Date.now
    @State private var endTime = Date.now.addingTimeInterval(60 * 60)
    @State private var location = ""
    @State private var driver = ""
    @State private var isSaving = false
    @State private var alertMessage = ""
    @State private var dismissAfterAlert = false
    @State private var isShowingAlert = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Activity") {
                    TextField("Title", text: $title)
                    TextField("Kid (optional)", text: $kidName)
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
            .navigationTitle("Add Event")
            .toolbar {
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
                    alertMessage = "The event was saved, but it conflicts with another scheduled activity."
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

    private var event: FamilyEvent {
        FamilyEvent(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            kidID: optionalKidID,
            startTime: startTime,
            endTime: endTime,
            location: optionalText(location),
            driver: optionalText(driver),
            source: .manual,
            status: .confirmed
        )
    }

    private var optionalKidID: KidID? {
        guard let kidName = optionalText(kidName) else {
            return nil
        }
        return KidID(rawValue: kidName)
    }

    private func optionalText(_ value: String) -> String? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}
