import SwiftUI
import FamilyCore

@main
struct FamilyActivityCoordinatorApp: App {
    private let eventStore: any EventStore
    private let memberStore: any FamilyMemberStore
    private let notificationStore: any ConflictNotificationStore
    private let authentication: any Authentication
    private let allowsSignOut: Bool

    init() {
        let configuration: AppConfiguration
        do {
            configuration = try AppConfiguration.load()
        } catch {
            fatalError("Invalid FamJam configuration: \(error)")
        }

        allowsSignOut = configuration.dataMode == .remote
        switch configuration.dataMode {
        case .local:
            AppStorage.resetForUnifiedFamilyMembersIfNeeded()
            authentication = LocalAuthentication()
            eventStore = LocalEventStore(storageURL: AppStorage.eventsURL)
            memberStore = LocalFamilyMemberStore(storageURL: AppStorage.membersURL)
        case .remote:
            guard let baseURL = configuration.remoteBaseURL else {
                fatalError("Remote mode requires a base URL")
            }
            let transport = URLSessionHTTPTransport()
            let remoteAuthentication = RemoteAuthentication(baseURL: baseURL, transport: transport)
            let authenticatedTransport = AuthenticatedHTTPTransport(
                transport: transport,
                authentication: remoteAuthentication
            )
            authentication = remoteAuthentication
            eventStore = RemoteEventStore(baseURL: baseURL, transport: authenticatedTransport)
            memberStore = RemoteFamilyMemberStore(baseURL: baseURL, transport: authenticatedTransport)
        }
        notificationStore = LocalConflictNotificationStore(storageURL: AppStorage.notificationsURL)
    }

    var body: some Scene {
        WindowGroup {
            SessionGateView(authentication: authentication) { session, signOut in
                TabView {
                    WeeklyScheduleView(
                        eventStore: eventStore,
                        memberStore: memberStore,
                        notificationStore: notificationStore,
                        allowsEditing: session.role == .parent
                    )
                    .tabItem { Label("Schedule", systemImage: "calendar") }
                    if session.role == .parent {
                        FamilyMembersView(memberStore: memberStore, eventStore: eventStore)
                            .tabItem { Label("Family", systemImage: "person.2") }
                        NotificationsView(notificationStore: notificationStore)
                            .tabItem { Label("Alerts", systemImage: "bell") }
                    }
                    SettingsView(
                        allowsSignOut: allowsSignOut,
                        onSignOut: signOut
                    )
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                }
                .tint(AppTheme.coral)
            }
        }
    }
}

enum AppStorage {
    static var eventsURL: URL {
        storageDirectory
            .appendingPathComponent("events")
            .appendingPathExtension("json")
    }

    static var notificationsURL: URL {
        storageDirectory.appendingPathComponent("conflicts").appendingPathExtension("json")
    }

    static var membersURL: URL {
        storageDirectory
            .appendingPathComponent("members")
            .appendingPathExtension("json")
    }

    static func resetForUnifiedFamilyMembersIfNeeded() {
        let resetKey = "didResetForStringMemberIDs"
        guard !UserDefaults.standard.bool(forKey: resetKey) else { return }
        try? FileManager.default.removeItem(at: storageDirectory)
        UserDefaults.standard.set(true, forKey: resetKey)
    }

    private static var storageDirectory: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appending(path: "FamilyActivityCoordinator")
    }
}
