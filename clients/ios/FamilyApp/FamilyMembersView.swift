import SwiftUI
import FamilyCore

struct FamilyMembersView: View {
    @StateObject private var viewModel: FamilyMembersViewModel
    @State private var isAddingMember = false

    init(memberStore: any FamilyMemberStore) {
        _viewModel = StateObject(wrappedValue: FamilyMembersViewModel(memberStore: memberStore))
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
                            }
                        }
                    }
                }
            }
            .navigationTitle("Family")
            .toolbar {
                Button { isAddingMember = true } label: { Image(systemName: "plus") }
            }
            .task { await viewModel.load() }
            .sheet(isPresented: $isAddingMember) {
                FamilyMemberEditor { member in try await viewModel.save(member) }
            }
        }
    }
}

@MainActor
final class FamilyMembersViewModel: ObservableObject {
    @Published private(set) var members: [FamilyMember] = []
    private let memberStore: any FamilyMemberStore
    init(memberStore: any FamilyMemberStore) { self.memberStore = memberStore }
    func load() async { members = (try? await memberStore.members().sorted { $0.name < $1.name }) ?? [] }
    func save(_ member: FamilyMember) async throws { try await memberStore.save(member); await load() }
}

private struct FamilyMemberEditor: View {
    let onSave: (FamilyMember) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var role: FamilyMemberRole = .kid
    @State private var grade = ""
    @State private var color = "blue"
    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Picker("Role", selection: $role) {
                    Text("Parent").tag(FamilyMemberRole.parent)
                    Text("Kid").tag(FamilyMemberRole.kid)
                }
                if role == .kid { TextField("Grade or birth year", text: $grade) }
                TextField("Color", text: $color)
            }
            .navigationTitle("Add Family Member")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            try? await onSave(FamilyMember(id: KidID(rawValue: UUID().uuidString), name: name, role: role, gradeOrBirthYear: role == .kid ? grade : nil, colorTag: color))
                            dismiss()
                        }
                    }.disabled(name.isEmpty)
                }
            }
        }
    }
}
