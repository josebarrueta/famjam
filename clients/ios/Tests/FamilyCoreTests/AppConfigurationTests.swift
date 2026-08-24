import XCTest
@testable import FamilyCore

final class AppConfigurationTests: XCTestCase {
    func testDefaultsToLocalDataMode() throws {
        let configuration = try AppConfiguration.load(environment: [:])

        XCTAssertEqual(configuration.dataMode, .local)
        XCTAssertNil(configuration.remoteBaseURL)
    }

    func testLoadsRemoteDataModeWithABaseURL() throws {
        let configuration = try AppConfiguration.load(environment: [
            "FAMJAM_DATA_MODE": "remote",
            "FAMJAM_REMOTE_BASE_URL": "https://api.example.com"
        ])

        XCTAssertEqual(configuration.dataMode, .remote)
        XCTAssertEqual(configuration.remoteBaseURL?.absoluteString, "https://api.example.com")
    }

    func testRejectsRemoteModeWithoutABaseURL() {
        XCTAssertThrowsError(try AppConfiguration.load(environment: [
            "FAMJAM_DATA_MODE": "remote"
        ])) { error in
            XCTAssertEqual(error as? AppConfigurationError, .missingRemoteBaseURL)
        }
    }
}
