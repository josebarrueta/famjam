import SwiftUI
import FamilyCore

struct FamilyMembersView: View {
    @StateObject private var viewModel: FamilyMembersViewModel
    @State private var isAddingMember = false
    @State private var editingMember: FamilyMember?

    init(memberStore: any FamilyMemberStore, eventStore: any EventStore) {
        _viewModel = StateObject(wrappedValue: FamilyMembersViewModel(
            memberStore: memberStore,
            deletionService: FamilyMemberDeletionService(memberStore: memberStore, eventStore: eventStore)
        ))
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(FamilyMemberRole.allCases, id: \.self) { role in
                    let members = viewModel.members.filter { $0.role == role }
                    if !members.isEmpty {
                        Section(role == .parent ? "Parents" : "Kids") {
                            ForEach(members) { member in
                                Text(member.name)
                                    .contentShape(Rectangle())
                                    .onTapGesture { editingMember = member }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Family")
            .toolbar { Button { isAddingMember = true } label: { Image(systemName: "plus") } }
            .task { await viewModel.load() }
            .sheet(isPresented: $isAddingMember) { FamilyMemberEditor(onSave: viewModel.save) }
            .sheet(item: $editingMember) { member in
                FamilyMemberEditor(member: member, onSave: viewModel.save, onDelete: viewModel.delete)
            }
        }
    }
}

@MainActor
final class FamilyMembersViewModel: ObservableObject {
    @Published private(set) var members: [FamilyMember] = []
    private let memberStore: any FamilyMemberStore
    private let deletionService: FamilyMemberDeletionService
    init(memberStore: any FamilyMemberStore, deletionService: FamilyMemberDeletionService) {
        self.memberStore = memberStore; self.deletionService = deletionService
    }
    func load() async { members = (try? await memberStore.members().sorted { $0.name < $1.name }) ?? [] }
    func save(_ member: FamilyMember) async throws { try await memberStore.save(member); await load() }
    func delete(_ member: FamilyMember) async throws { try await deletionService.delete(member); await load() }
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
                TextField("Color", text: $color)
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
