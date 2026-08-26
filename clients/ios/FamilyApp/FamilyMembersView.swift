import SwiftUI
import FamilyCore

struct FamilyMembersView: View {
    @StateObject private var viewModel: FamilyMembersViewModel
    @State private var isAddingMember = false
    @State private var editingMember: FamilyMember?
    @State private var quickActivity: QuickActivitySelection?
    private let locationSearch: any LocationSearch

    init(
        memberStore: any FamilyMemberStore,
        eventStore: any EventStore,
        locationSearch: any LocationSearch = EmptyLocationSearch(),
        invitationStore: (any FamilyInvitationStore)? = nil
    ) {
        self.locationSearch = locationSearch
        _viewModel = StateObject(wrappedValue: FamilyMembersViewModel(
            memberStore: memberStore,
            eventStore: eventStore,
            invitationStore: invitationStore,
            deletionService: FamilyMemberDeletionService(memberStore: memberStore, eventStore: eventStore)
        ))
    }

    var body: some View {
        NavigationStack {
            List {
                FamJamHeader(title: "Your home team", subtitle: "Parents and kids, all in one place.")
                    .listRowBackground(Color.clear)
                if !viewModel.pendingInvitations.isEmpty {
                    Section("Pending invitations") {
                        ForEach(viewModel.pendingInvitations) { invitation in
                            HStack(spacing: 12) {
                                Image(systemName: invitation.role == .parent ? "person.fill.badge.plus" : "face.smiling.fill")
                                    .foregroundStyle(AppTheme.purple)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(invitation.role == .parent ? "Parent invitation" : "Kid invitation")
                                        .font(.headline)
                                    Text("Expires \(invitation.expiresAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Menu {
                                    Button {
                                        Task { await viewModel.resend(invitation) }
                                    } label: {
                                        Label("Create new link & Share", systemImage: "paperplane")
                                    }
                                    Button(role: .destructive) {
                                        Task { await viewModel.cancel(invitation) }
                                    } label: {
                                        Label("Cancel invitation", systemImage: "trash")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                }
                            }
                        }
                    }
                }
                ForEach(FamilyMemberRole.allCases, id: \.self) { role in
                    let members = viewModel.members.filter { $0.role == role }
                    if !members.isEmpty {
                        Section(role == .parent ? "Parents" : "Kids") {
                            ForEach(members) { member in
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack(spacing: 12) {
                                        ZStack {
                                            Circle()
                                                .fill(Color(familyColorTag: member.colorTag).opacity(0.2))
                                                .frame(width: 42, height: 42)
                                            Image(systemName: member.role == .parent ? "person.fill" : "face.smiling.fill")
                                                .foregroundStyle(Color(familyColorTag: member.colorTag))
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(member.name)
                                                .font(.headline)
                                            if let grade = member.gradeOrBirthYear, !grade.isEmpty {
                                                Text(grade)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture { editingMember = member }

                                    if member.role == .kid {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 10) {
                                                ForEach(ActivityPreset.allCases) { preset in
                                                    Button {
                                                        quickActivity = QuickActivitySelection(
                                                            prefill: preset.prefill(for: member.id)
                                                        )
                                                    } label: {
                                                        Label(preset.title, systemImage: preset.systemImage)
                                                    }
                                                    .buttonStyle(.bordered)
                                                    .tint(Color(familyColorTag: member.colorTag))
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Family")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if viewModel.canInvite {
                        Menu {
                            Button("Invite a parent") { Task { await viewModel.invite(role: .parent) } }
                            Button("Invite a kid") { Task { await viewModel.invite(role: .kid) } }
                        } label: {
                            Image(systemName: "person.badge.plus")
                        }
                    }
                    Button { isAddingMember = true } label: { Image(systemName: "plus") }
                }
            }
            .task { await viewModel.load() }
            .onReceive(NotificationCenter.default.publisher(for: .familyDataDidChange)) { _ in
                Task { await viewModel.load() }
            }
            .sheet(isPresented: $isAddingMember) { FamilyMemberEditor(onSave: viewModel.save) }
            .sheet(item: $editingMember) { member in
                FamilyMemberEditor(member: member, onSave: viewModel.save, onDelete: viewModel.delete)
            }
            .sheet(item: $viewModel.invitation) { invitation in
                InvitationSheet(invitation: invitation)
            }
            .sheet(item: $quickActivity) { selection in
                AddEventSheet(
                    prefill: selection.prefill,
                    members: viewModel.members,
                    locationSearch: locationSearch,
                    onSave: viewModel.saveEvent
                )
            }
        }
    }
}

@MainActor
final class FamilyMembersViewModel: ObservableObject {
    @Published private(set) var members: [FamilyMember] = []
    @Published private(set) var pendingInvitations: [PendingFamilyInvitation] = []
    @Published var invitation: FamilyInvitation?
    private let memberStore: any FamilyMemberStore
    private let eventStore: any EventStore
    private let invitationStore: (any FamilyInvitationStore)?
    private let deletionService: FamilyMemberDeletionService
    init(
        memberStore: any FamilyMemberStore,
        eventStore: any EventStore,
        invitationStore: (any FamilyInvitationStore)?,
        deletionService: FamilyMemberDeletionService
    ) {
        self.memberStore = memberStore
        self.eventStore = eventStore
        self.invitationStore = invitationStore
        self.deletionService = deletionService
    }
    func load() async {
        members = (try? await memberStore.members().sorted { $0.name < $1.name }) ?? []
        pendingInvitations = (try? await invitationStore?.pending()) ?? []
    }
    func save(_ member: FamilyMember) async throws { try await memberStore.save(member); await load() }
    func delete(_ member: FamilyMember) async throws { try await deletionService.delete(member); await load() }
    var canInvite: Bool { invitationStore != nil }
    func saveEvent(_ event: FamilyEvent) async throws -> [EventConflict] { try await eventStore.save(event) }
    func invite(role: FamilyMemberRole) async {
        invitation = try? await invitationStore?.create(role: role)
        await load()
    }
    func resend(_ pendingInvitation: PendingFamilyInvitation) async {
        invitation = try? await invitationStore?.resend(id: pendingInvitation.id)
        await load()
    }
    func cancel(_ invitation: PendingFamilyInvitation) async {
        try? await invitationStore?.cancel(id: invitation.id)
        await load()
    }
}

private struct InvitationSheet: View {
    let invitation: FamilyInvitation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "person.2.badge.plus")
                    .font(.system(size: 54))
                    .foregroundStyle(AppTheme.purple)
                Text("Invite a \(invitation.role.rawValue)")
                    .font(.title.bold())
                Text(invitation.code)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                Text("Send this secure link by Mail or Messages. The recipient will join your family after signing in with Google.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                ShareLink(
                    item: invitation.shareURL,
                    subject: Text("Join my family on FamJam"),
                    message: Text("Tap this secure link to join my family on FamJam. The link expires in seven days and can only be used once.")
                ) {
                    Label("Send invitation link", systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                Text("Expires \(invitation.expiresAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .navigationTitle("Family Invitation")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}

private struct QuickActivitySelection: Identifiable {
    let id = UUID()
    let prefill: ActivityEventPrefill
}

private struct FamilyMemberEditor: View {
    let onSave: (FamilyMember) async throws -> Void
    let onDelete: ((FamilyMember) async throws -> Void)?
    let existingMember: FamilyMember?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var role: FamilyMemberRole
    @State private var grade: String
    @State private var color: String
    @State private var errorMessage: String?
    @State private var confirmDelete = false

    init(member: FamilyMember? = nil, onSave: @escaping (FamilyMember) async throws -> Void, onDelete: ((FamilyMember) async throws -> Void)? = nil) {
        existingMember = member; self.onSave = onSave; self.onDelete = onDelete
        _name = State(initialValue: member?.name ?? "")
        _role = State(initialValue: member?.role ?? .kid)
        _grade = State(initialValue: member?.gradeOrBirthYear ?? "")
        _color = State(initialValue: member?.colorTag ?? "blue")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Picker("Role", selection: $role) { Text("Parent").tag(FamilyMemberRole.parent); Text("Kid").tag(FamilyMemberRole.kid) }
                if role == .kid { TextField("Grade or birth year", text: $grade) }
                Picker("Color", selection: $color) {
                    ForEach(["red", "orange", "yellow", "green", "blue", "purple", "pink"], id: \.self) { colorTag in
                        HStack {
                            Circle()
                                .fill(Color(familyColorTag: colorTag))
                                .frame(width: 14, height: 14)
                            Text(colorTag.capitalized)
                        }
                        .tag(colorTag)
                    }
                }
            }
            .navigationTitle(existingMember == nil ? "Add Family Member" : "Edit Family Member")
            .toolbar {
                if existingMember != nil { ToolbarItem(placement: .topBarLeading) { Button("Delete", role: .destructive) { confirmDelete = true } } }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(name.isEmpty) }
            }
            .confirmationDialog("Delete this family member?", isPresented: $confirmDelete) { Button("Delete", role: .destructive) { delete() } }
            .alert("Family member", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        }
    }

    private func save() { Task { do { try await onSave(FamilyMember(id: existingMember?.id ?? KidID(rawValue: UUID().uuidString), name: name, role: role, gradeOrBirthYear: role == .kid ? grade : nil, colorTag: color)); dismiss() } catch { errorMessage = "Could not save this family member." } } }
    private func delete() { guard let existingMember, let onDelete else { return }; Task { do { try await onDelete(existingMember); dismiss() } catch FamilyMemberDeletionError.hasScheduledEvents { errorMessage = "Remove this member from scheduled events before deleting." } catch { errorMessage = "Could not delete this family member." } } }
}
