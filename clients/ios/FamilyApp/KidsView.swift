import SwiftUI
import FamilyCore

struct KidsView: View {
    @StateObject private var viewModel: KidsViewModel
    @State private var isAddingKid = false

    init(kidStore: any KidStore) {
        _viewModel = StateObject(wrappedValue: KidsViewModel(kidStore: kidStore))
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
            }
            .overlay {
                if viewModel.kids.isEmpty {
                    Label("No kids yet", systemImage: "person.2")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Kids")
            .toolbar {
                Button {
                    isAddingKid = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            .task { await viewModel.loadKids() }
            .sheet(isPresented: $isAddingKid) {
                KidEditorSheet { kid in
                    try await viewModel.save(kid)
                }
            }
        }
    }
}

@MainActor
final class KidsViewModel: ObservableObject {
    @Published private(set) var kids: [Kid] = []
    private let kidStore: any KidStore

    init(kidStore: any KidStore) {
        self.kidStore = kidStore
    }

    func loadKids() async {
        kids = (try? await kidStore.kids().sorted { $0.name < $1.name }) ?? []
    }

    func save(_ kid: Kid) async throws {
        try await kidStore.save(kid)
        await loadKids()
    }
}

private struct KidEditorSheet: View {
    let onSave: (Kid) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var gradeOrBirthYear = ""
    @State private var colorTag = "blue"
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Grade or birth year", text: $gradeOrBirthYear)
                TextField("Color", text: $colorTag)
            }
            .navigationTitle("Add Kid")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            do {
                                try await onSave(
                                    Kid(
                                    id: KidID(rawValue: UUID().uuidString),
                                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                    gradeOrBirthYear: gradeOrBirthYear.trimmingCharacters(in: .whitespacesAndNewlines),
                                    colorTag: colorTag.trimmingCharacters(in: .whitespacesAndNewlines)
                                    )
                                )
                                dismiss()
                            } catch {
                                errorMessage = "The kid could not be saved."
                            }
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
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
}
