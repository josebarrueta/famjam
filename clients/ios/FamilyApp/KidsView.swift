import SwiftUI
import FamilyCore

struct KidsView: View {
    @StateObject private var viewModel: KidsViewModel
    @State private var isAddingKid = false
    @State private var editingKid: Kid?

    init(kidStore: any KidStore, eventStore: any EventStore) {
        _viewModel = StateObject(
            wrappedValue: KidsViewModel(
                kidStore: kidStore,
                deletionService: KidDeletionService(kidStore: kidStore, eventStore: eventStore)
            )
        )
    }

    var body: some View {
        NavigationStack {
            List(viewModel.kids) { kid in
                VStack(alignment: .leading) {
                    Text(kid.name)
                    Text(kid.gradeOrBirthYear)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture { editingKid = kid }
            }
            .overlay {
                if viewModel.kids.isEmpty {
                    Label("No kids yet", systemImage: "person.2")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Kids")
            .toolbar {
                Button { isAddingKid = true } label: {
                    Image(systemName: "plus")
                }
            }
            .task { await viewModel.loadKids() }
            .sheet(isPresented: $isAddingKid) {
                KidEditorSheet(onSave: viewModel.save)
            }
            .sheet(item: $editingKid) { kid in
                KidEditorSheet(
                    kid: kid,
                    onSave: viewModel.save,
                    onDelete: viewModel.delete
                )
            }
        }
    }
}

@MainActor
final class KidsViewModel: ObservableObject {
    @Published private(set) var kids: [Kid] = []
    private let kidStore: any KidStore
    private let deletionService: KidDeletionService

    init(kidStore: any KidStore, deletionService: KidDeletionService) {
        self.kidStore = kidStore
        self.deletionService = deletionService
    }

    func loadKids() async {
        kids = (try? await kidStore.kids().sorted { $0.name < $1.name }) ?? []
    }

    func save(_ kid: Kid) async throws {
        try await kidStore.save(kid)
        await loadKids()
    }

    func delete(_ kid: Kid) async throws {
        try await deletionService.delete(kid)
        await loadKids()
    }
}

private struct KidEditorSheet: View {
    let onSave: (Kid) async throws -> Void
    let onDelete: ((Kid) async throws -> Void)?
    private let existingKid: Kid?

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var gradeOrBirthYear: String
    @State private var colorTag: String
    @State private var errorMessage: String?
    @State private var showDeleteConfirmation = false

    init(
        kid: Kid? = nil,
        onSave: @escaping (Kid) async throws -> Void,
        onDelete: ((Kid) async throws -> Void)? = nil
    ) {
        existingKid = kid
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: kid?.name ?? "")
        _gradeOrBirthYear = State(initialValue: kid?.gradeOrBirthYear ?? "")
        _colorTag = State(initialValue: kid?.colorTag ?? "blue")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Grade or birth year", text: $gradeOrBirthYear)
                TextField("Color", text: $colorTag)
            }
            .navigationTitle(existingKid == nil ? "Add Kid" : "Edit Kid")
            .toolbar {
                if existingKid != nil, onDelete != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Delete", role: .destructive) { showDeleteConfirmation = true }
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .confirmationDialog("Delete this kid?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) { delete() }
            } message: {
                Text("Kids with scheduled events cannot be deleted.")
            }
            .alert("Could not save", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func save() {
        Task {
            do {
                try await onSave(Kid(
                    id: existingKid?.id ?? KidID(rawValue: UUID().uuidString),
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    gradeOrBirthYear: gradeOrBirthYear.trimmingCharacters(in: .whitespacesAndNewlines),
                    colorTag: colorTag.trimmingCharacters(in: .whitespacesAndNewlines)
                ))
                dismiss()
            } catch {
                errorMessage = "The kid could not be saved."
            }
        }
    }

    private func delete() {
        guard let existingKid, let onDelete else { return }
        Task {
            do {
                try await onDelete(existingKid)
                dismiss()
            } catch KidDeletionError.kidHasScheduledEvents {
                errorMessage = "Remove or reassign this kid's scheduled events before deleting them."
            } catch {
                errorMessage = "The kid could not be deleted."
            }
        }
    }
}
