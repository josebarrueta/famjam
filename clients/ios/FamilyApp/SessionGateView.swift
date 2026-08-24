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
    }
}

@MainActor
final class SessionGateViewModel: ObservableObject {
    @Published private(set) var session: AuthSession?
    @Published private(set) var isLoading = true
    @Published private(set) var errorMessage: String?
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

    func signIn(email: String, password: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            session = try await authentication.signIn(
                credentials: SignInCredentials(email: email, password: password)
            )
            errorMessage = nil
        } catch {
            errorMessage = "We couldn't sign you in. Check your details and try again."
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
    @State private var email = ""
    @State private var password = ""

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
                VStack(spacing: 14) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                }
                .textFieldStyle(.roundedBorder)
                Button("Sign In") {
                    Task { await viewModel.signIn(email: email, password: password) }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.coral)
                .disabled(email.isEmpty || password.isEmpty)
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
