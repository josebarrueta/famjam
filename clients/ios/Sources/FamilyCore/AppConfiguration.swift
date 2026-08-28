import Foundation

public enum DataMode: String, Equatable, Sendable {
    case local
    case remote
}

public enum AppConfigurationError: Error, Equatable, Sendable {
    case unsupportedDataMode(String)
    case missingRemoteBaseURL
    case invalidRemoteBaseURL
}

public struct AppConfiguration: Equatable, Sendable {
    public let dataMode: DataMode
    public let remoteBaseURL: URL?

    public static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> AppConfiguration {
        let rawMode = environment["RALLYROO_DATA_MODE"] ?? DataMode.local.rawValue
        guard let dataMode = DataMode(rawValue: rawMode.lowercased()) else {
            throw AppConfigurationError.unsupportedDataMode(rawMode)
        }

        guard dataMode == .remote else {
            return AppConfiguration(dataMode: .local, remoteBaseURL: nil)
        }
        guard let rawURL = environment["RALLYROO_REMOTE_BASE_URL"] else {
            throw AppConfigurationError.missingRemoteBaseURL
        }
        guard let url = URL(string: rawURL), url.scheme != nil, url.host != nil else {
            throw AppConfigurationError.invalidRemoteBaseURL
        }
        return AppConfiguration(dataMode: .remote, remoteBaseURL: url)
    }
}
