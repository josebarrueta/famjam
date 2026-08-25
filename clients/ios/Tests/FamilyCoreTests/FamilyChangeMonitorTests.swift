import Foundation
import XCTest
@testable import FamilyCore

final class FamilyChangeMonitorTests: XCTestCase {
    func testReportsOnlyWhenTheServerVersionAdvances() async throws {
        let transport = ChangeHTTPTransport(versions: [1, 1, 2])
        let monitor = RemoteFamilyChangeMonitor(
            baseURL: URL(string: "https://api.example.com")!,
            transport: transport
        )

        let initial = try await monitor.hasChanges()
        let unchanged = try await monitor.hasChanges()
        let changed = try await monitor.hasChanges()
        XCTAssertFalse(initial)
        XCTAssertFalse(unchanged)
        XCTAssertTrue(changed)
        let paths = await transport.requestPaths()
        XCTAssertEqual(paths, [
            "/v1/changes", "/v1/changes", "/v1/changes",
        ])
    }
}

private actor ChangeHTTPTransport: HTTPTransport {
    private var versions: [Int]
    private var paths: [String] = []
    init(versions: [Int]) { self.versions = versions }
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        paths.append(request.url.path)
        return HTTPResponse(
            statusCode: 200,
            body: try JSONEncoder().encode(["version": versions.removeFirst()])
        )
    }
    func requestPaths() -> [String] { paths }
}
