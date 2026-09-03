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
            "RALLYROO_DATA_MODE": "remote",
            "RALLYROO_REMOTE_BASE_URL": "https://api.example.com"
        ])

        XCTAssertEqual(configuration.dataMode, .remote)
        XCTAssertEqual(configuration.remoteBaseURL?.absoluteString, "https://api.example.com")
    }

    func testLoadsBundledRemoteConfigurationWhenProcessEnvironmentIsEmpty() throws {
        let configuration = try AppConfiguration.load(
            environment: [:],
            bundledValues: [
                "RALLYROO_DATA_MODE": "remote",
                "RALLYROO_REMOTE_BASE_URL": "https://api.rallyroo.dev"
            ]
        )

        XCTAssertEqual(configuration.dataMode, .remote)
        XCTAssertEqual(configuration.remoteBaseURL?.absoluteString, "https://api.rallyroo.dev")
    }

    func testProcessEnvironmentOverridesBundledConfiguration() throws {
        let configuration = try AppConfiguration.load(
            environment: ["RALLYROO_DATA_MODE": "local"],
            bundledValues: [
                "RALLYROO_DATA_MODE": "remote",
                "RALLYROO_REMOTE_BASE_URL": "https://api.rallyroo.dev"
            ]
        )

        XCTAssertEqual(configuration.dataMode, .local)
        XCTAssertNil(configuration.remoteBaseURL)
    }

    func testRejectsRemoteModeWithoutABaseURL() {
        XCTAssertThrowsError(try AppConfiguration.load(environment: [
            "RALLYROO_DATA_MODE": "remote"
        ])) { error in
            XCTAssertEqual(error as? AppConfigurationError, .missingRemoteBaseURL)
        }
    }
}
