import SwiftUI
import FamilyCore

struct SettingsView: View {
    let allowsSignOut: Bool
    let onSignOut: SignOutAction
    private let calendarSourceStore: (any CalendarSourceStore)?
    private let memberStore: (any FamilyMemberStore)?
    private let preferences = ConflictAlertPreferences()

    init(
        allowsSignOut: Bool = false,
        calendarSourceStore: (any CalendarSourceStore)? = nil,
        memberStore: (any FamilyMemberStore)? = nil,
        onSignOut: SignOutAction = SignOutAction({})
    ) {
        self.allowsSignOut = allowsSignOut
        self.calendarSourceStore = calendarSourceStore
        self.memberStore = memberStore
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

                if let calendarSourceStore, let memberStore {
                    Section("Calendars") {
                        NavigationLink("Connected calendars") {
                            CalendarSourcesView(
                                store: calendarSourceStore,
                                memberStore: memberStore
                            )
                        }
                        Text("Add TeamSnap, school, sports, or other iCalendar subscription links.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("About") {
                    LabeledContent("App", value: "Rallyroo")
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

private struct CalendarSourcesView: View {
    let store: any CalendarSourceStore
    let memberStore: any FamilyMemberStore
    @State private var sources: [CalendarSourceConnection] = []
    @State private var members: [FamilyMember] = []
    @State private var isAdding = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }
            ForEach(sources) { source in
                VStack(alignment: .leading, spacing: 5) {
                    Text(source.name).font(.headline)
                    Text(participantNames(for: source))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Label(statusText(source), systemImage: statusIcon(source.status))
                        .font(.caption)
                        .foregroundStyle(source.status == .error ? .red : .secondary)
                }
                .swipeActions(edge: .leading) {
                    Button("Sync") { Task { await synchronize(source) } }
                        .tint(AppTheme.purple)
                }
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        Task { await delete(source) }
                    }
                }
            }
        }
        .navigationTitle("Calendars")
        .toolbar {
            Button { isAdding = true } label: { Image(systemName: "plus") }
                .disabled(members.isEmpty)
        }
        .task { await load() }
        .sheet(isPresented: $isAdding) {
            AddCalendarSourceView(members: members) { name, url, participantIDs in
                let source = try await store.create(
                    name: name,
                    url: url,
                    participantIDs: participantIDs
                )
                _ = try? await store.synchronize(source)
                await load()
                NotificationCenter.default.post(name: .familyDataDidChange, object: nil)
            }
        }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            async let loadedSources = store.sources()
            async let loadedMembers = memberStore.members()
            sources = try await loadedSources
            members = try await loadedMembers
            errorMessage = nil
        } catch {
            errorMessage = "Calendar connections could not be loaded."
        }
    }

    private func synchronize(_ source: CalendarSourceConnection) async {
        do {
            _ = try await store.synchronize(source)
            await load()
            NotificationCenter.default.post(name: .familyDataDidChange, object: nil)
        } catch {
            await load()
            errorMessage = "The calendar could not be synchronized."
        }
    }

    private func delete(_ source: CalendarSourceConnection) async {
        do {
            try await store.delete(source)
            await load()
            NotificationCenter.default.post(name: .familyDataDidChange, object: nil)
        } catch {
            errorMessage = "The calendar could not be removed."
        }
    }

    private func participantNames(for source: CalendarSourceConnection) -> String {
        members.filter { source.participantIDs.contains($0.id) }
            .map(\.name)
            .joined(separator: " • ")
    }

    private func statusText(_ source: CalendarSourceConnection) -> String {
        switch source.status {
        case .pending: "Waiting for first sync"
        case .ready: source.lastSyncedAt.map { "Updated \($0.formatted(.relative(presentation: .named)))" } ?? "Ready"
        case .error: "Sync failed — previous events preserved"
        }
    }

    private func statusIcon(_ status: CalendarSourceStatus) -> String {
        switch status {
        case .pending: "clock"
        case .ready: "checkmark.circle"
        case .error: "exclamationmark.triangle"
        }
    }
}

private struct AddCalendarSourceView: View {
    let members: [FamilyMember]
    let onAdd: (String, URL, [KidID]) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var urlText = ""
    @State private var participantIDs = Set<KidID>()
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Calendar") {
                    TextField("Name, such as Emma TeamSnap", text: $name)
                    TextField("Calendar subscription link", text: $urlText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
                Section("Family members") {
                    ForEach(members) { member in
                        Toggle(member.name, isOn: Binding(
                            get: { participantIDs.contains(member.id) },
                            set: { selected in
                                if selected { participantIDs.insert(member.id) }
                                else { participantIDs.remove(member.id) }
                            }
                        ))
                    }
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Add Calendar")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { add() }
                        .disabled(validatedURL == nil || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || participantIDs.isEmpty || isSaving)
                }
            }
        }
    }

    private var validatedURL: URL? {
        let value = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: value) else { return nil }
        if components.scheme?.lowercased() == "webcal" {
            components.scheme = "https"
        }
        guard components.scheme?.lowercased() == "https",
              components.host != nil else { return nil }
        return components.url
    }

    private func add() {
        guard let validatedURL else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await onAdd(
                    name.trimmingCharacters(in: .whitespacesAndNewlines),
                    validatedURL,
                    Array(participantIDs)
                )
                dismiss()
            } catch {
                errorMessage = "The calendar could not be added. Check the subscription link and try again."
            }
        }
    }
}
