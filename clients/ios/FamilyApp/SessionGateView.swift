import SwiftUI
import FamilyCore

struct SessionGateView<Content: View>: View {
    @StateObject private var viewModel: SessionGateViewModel
    private let content: (AuthSession, SignOutAction) -> Content

    init(
        authentication: any Authentication,
        @ViewBuilder content: @escaping (AuthSession, SignOutAction) -> Content
    ) {
        _viewModel = StateObject(wrappedValue: SessionGateViewModel(authentication: authentication))
        self.content = content
    }

    var body: some View {
        Group {
            if let session = viewModel.session {
                content(session, SignOutAction {
                    Task { await viewModel.signOut() }
                })
            } else if viewModel.isLoading {
                ProgressView("Getting the family together…")
                    .tint(AppTheme.coral)
            } else {
                SignInView(viewModel: viewModel)
            }
        }
        .task { await viewModel.restoreSession() }
        .onOpenURL { viewModel.acceptInvitationURL($0) }
    }
}

@MainActor
final class SessionGateViewModel: ObservableObject {
    @Published private(set) var session: AuthSession?
    @Published private(set) var isLoading = true
    @Published private(set) var errorMessage: String?
    @Published var invitationCode = ""
    private let authentication: any Authentication

    init(authentication: any Authentication) {
        self.authentication = authentication
    }

    func restoreSession() async {
        session = try? await authentication.currentSession()
        isLoading = false
    }

    func signOut() async {
        do {
            try await authentication.signOut()
            session = nil
        } catch {
            errorMessage = "We couldn't sign you out. Please try again."
        }
    }

    func acceptInvitationURL(_ url: URL) {
        guard url.scheme == "famjam", url.host == "invite",
              let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value else { return }
        invitationCode = code
    }

    func clearInvitation() {
        invitationCode = ""
        errorMessage = nil
    }

    func signIn(invitationCode: String?) async {
        isLoading = true
        defer { isLoading = false }
        do {
            session = try await authentication.signIn(invitationCode: invitationCode)
            errorMessage = nil
        } catch {
            errorMessage = invitationCode == nil
                ? "We couldn't sign you in with Google. Please try again."
                : "This invitation may have expired or already been used. Ask a parent to resend it."
        }
    }
}

struct SignOutAction {
    let perform: () -> Void

    init(_ perform: @escaping () -> Void) {
        self.perform = perform
    }
}

private struct SignInView: View {
    @ObservedObject var viewModel: SessionGateViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image("FamilyHero")
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 28))
                VStack(spacing: 6) {
                    Text("Welcome to FamJam")
                        .font(.largeTitle.bold())
                        .foregroundStyle(AppTheme.purple)
                    Text("Sign in to rally your family's week.")
                        .foregroundStyle(.secondary)
                }
                let code = viewModel.invitationCode.trimmingCharacters(in: .whitespacesAndNewlines)
                if code.isEmpty {
                    TextField("Invitation code (optional)", text: $viewModel.invitationCode)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Family invitation ready", systemImage: "person.2.badge.plus")
                            .font(.headline)
                            .foregroundStyle(AppTheme.purple)
                        Text("Continue with Google to securely join the family that invited you.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Use a different invitation") { viewModel.clearInvitation() }
                            .font(.footnote)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(AppTheme.purple.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                }
                Button {
                    Task { await viewModel.signIn(invitationCode: code.isEmpty ? nil : code) }
                } label: {
                    Label(
                        code.isEmpty ? "Continue with Google" : "Accept invitation with Google",
                        systemImage: "person.crop.circle.badge.checkmark"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.coral)
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
                Spacer()
            }
            .padding(24)
            .background(AppTheme.background.ignoresSafeArea())
        }
    }
}
