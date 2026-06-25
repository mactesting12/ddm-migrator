import XCTest
@testable import DDMCore

/// Tests the Fleet request builder without any network I/O.
final class FleetClientTests: XCTestCase {

    func testInitNormalizesURL() {
        let a = FleetClient(baseURLString: "fleet.example.com", token: "t")
        XCTAssertEqual(a?.endpoint.absoluteString,
                       "https://fleet.example.com/api/v1/fleet/configuration_profiles")
        let b = FleetClient(baseURLString: "https://fleet.example.com/", token: "t")
        XCTAssertEqual(b?.endpoint.absoluteString,
                       "https://fleet.example.com/api/v1/fleet/configuration_profiles")
        XCTAssertNil(FleetClient(baseURLString: "", token: "t"))
        XCTAssertNil(FleetClient(baseURLString: "x", token: ""))
    }

    func testUploadRequestShape() throws {
        let client = try XCTUnwrap(FleetClient(baseURLString: "https://fleet.example.com", token: "secret-token"))
        let req = client.makeUploadRequest(
            fileName: "siri.settings.abcd.ddm.json",
            data: Data("{\"Type\":\"x\"}".utf8),
            teamID: "3",
            teamFieldName: "team_id")

        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.url?.path, "/api/v1/fleet/configuration_profiles")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")
        let ctype = try XCTUnwrap(req.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertTrue(ctype.hasPrefix("multipart/form-data; boundary="))

        let body = String(data: try XCTUnwrap(req.httpBody), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("name=\"profile\"; filename=\"siri.settings.abcd.ddm.json\""))
        XCTAssertTrue(body.contains("name=\"team_id\""))
        XCTAssertTrue(body.contains("3"))
        XCTAssertTrue(body.contains("{\"Type\":\"x\"}"))
    }

    func testUploadRequestHonorsCustomTeamField() throws {
        let client = try XCTUnwrap(FleetClient(baseURLString: "fleet.local", token: "t"))
        let req = client.makeUploadRequest(fileName: "a.json", data: Data("x".utf8),
                                           teamID: "5", teamFieldName: "fleet_id")
        let body = String(data: try XCTUnwrap(req.httpBody), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("name=\"fleet_id\""))
    }
}
