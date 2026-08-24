import SwiftUI
import FamilyCore

struct SettingsView: View {
    private let preferences = ConflictAlertPreferences()
    @State private var conflictAlertsEnabled = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Notifications") {
                    Toggle("Save conflict alerts", isOn: $conflictAlertsEnabled)
                        .onChange(of: conflictAlertsEnabled) { newValue in
                            preferences.areConflictAlertsEnabled = newValue
                        }
                    Text("Immediate conflict warnings still appear while adding an event.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("About") {
                    LabeledContent("App", value: "FamJam")
                    LabeledContent("Data", value: "Stored on this device")
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                conflictAlertsEnabled = preferences.areConflictAlertsEnabled
            }
        }
    }
}
