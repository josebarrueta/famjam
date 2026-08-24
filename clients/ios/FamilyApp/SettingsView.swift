import SwiftUI
import FamilyCore

struct SettingsView: View {
    let allowsSignOut: Bool
    let onSignOut: SignOutAction
    private let preferences = ConflictAlertPreferences()

    init(
        allowsSignOut: Bool = false,
        onSignOut: SignOutAction = SignOutAction({})
    ) {
        self.allowsSignOut = allowsSignOut
        self.onSignOut = onSignOut
    }
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
                    LabeledContent("Data", value: allowsSignOut ? "Synced" : "Stored on this device")
                }

                if allowsSignOut {
                    Section("Account") {
                        Button("Sign Out", role: .destructive) {
                            onSignOut.perform()
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                conflictAlertsEnabled = preferences.areConflictAlertsEnabled
            }
        }
    }
}
