import XCTest
@testable import DDMCore

/// Tests the Jamf blueprint builder and request builder — no network I/O.
final class JamfBlueprintTests: XCTestCase {

    private func makeProfile(_ payloads: [[String: Any]], id: String = "t") -> Data {
        let root: [String: Any] = [
            "PayloadType": "Configuration", "PayloadVersion": 1,
            "PayloadIdentifier": id, "PayloadUUID": "u",
            "PayloadContent": payloads,
        ]
        return try! PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)
    }

    private func report(_ data: Data) -> MigrationReport {
        MigrationReport(results: [Migrator().migrate(data: data, fileName: "t.mobileconfig")],
                        generatedAtISO8601: "2026-06-25T00:00:00Z")
    }

    func testBuildsCustomDeclarationsComponent() throws {
        let data = makeProfile([[
            "PayloadType": "com.apple.applicationaccess",
            "allowAssistant": false, "allowGenmoji": false,
        ]])
        let result = JamfBlueprint.build(report: report(data), name: "BP",
                                         description: "d", deviceGroups: ["g1"])
        XCTAssertEqual(result.customDeclarationCount, 2) // siri + intelligence
        XCTAssertEqual(result.legacyProfileCount, 0)

        let body = result.body
        XCTAssertEqual(body["name"], .string("BP"))
        XCTAssertEqual(body["scope"]?["deviceGroups"], .array([.string("g1")]))

        // Drill into steps[0].components[0]
        let comp = body["steps"]?.arrayValue?.first?["components"]?.arrayValue?.first
        XCTAssertEqual(comp?["identifier"], .string("com.jamf.ddm.custom-declarations"))
        let decls = try XCTUnwrap(comp?["configuration"]?["declarations"]?.arrayValue)
        XCTAssertEqual(decls.count, 2)
        // Each entry has the required wire fields.
        for d in decls {
            XCTAssertNotNil(d["type"])
            XCTAssertEqual(d["channelType"], .string("SYSTEM"))
            XCTAssertEqual(d["kind"], .string("CONFIGURATION"))
            XCTAssertNotNil(d["payload"])
            XCTAssertNotNil(d["payloadKey"])
        }
    }

    func testLegacyExcludedByDefaultIncludedOnFlag() throws {
        let data = makeProfile([["PayloadType": "com.apple.dock", "tilesize": 64]])
        let without = JamfBlueprint.build(report: report(data), name: "BP",
                                          description: nil, deviceGroups: [])
        XCTAssertEqual(without.legacyProfileCount, 0)
        XCTAssertEqual(without.customDeclarationCount, 0)

        let with = JamfBlueprint.build(report: report(data), name: "BP",
                                       description: nil, deviceGroups: [], includeLegacy: true)
        XCTAssertEqual(with.legacyProfileCount, 1)
        let comp = with.body["steps"]?.arrayValue?.first?["components"]?.arrayValue?.first
        XCTAssertEqual(comp?["identifier"], .string("com.jamf.ddm-configuration-profile"))
        let content = try XCTUnwrap(comp?["configuration"]?["payloadContent"]?.arrayValue)
        XCTAssertEqual(content.first?["payloadType"], .string("com.apple.dock"))
        XCTAssertEqual(content.first?["tilesize"], .int(64))
        // Meta keys stripped.
        XCTAssertNil(content.first?["PayloadUUID"])
    }

    func testMCXLegacyIsSkippedWithNote() {
        let data = makeProfile([[
            "PayloadType": "com.apple.ManagedClient.preferences",
            "PayloadContent": ["com.x": ["Forced": [["mcx_preference_settings": ["k": 1]]]]],
        ]])
        let result = JamfBlueprint.build(report: report(data), name: "BP",
                                         description: nil, deviceGroups: [], includeLegacy: true)
        XCTAssertEqual(result.legacyProfileCount, 0)
        XCTAssertFalse(result.skipped.isEmpty)
    }

    func testClientRequestShape() throws {
        let client = try XCTUnwrap(JamfClient(
            baseURLString: "us.apigw.jamf.com", tenantID: "123", token: "jamf-token"))
        XCTAssertEqual(client.endpoint.absoluteString,
                       "https://us.apigw.jamf.com/api/blueprints/v1/tenant/123/blueprints")
        let req = client.makeCreateRequest(body: Data("{}".utf8))
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer jamf-token")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertNil(JamfClient(baseURLString: "x", tenantID: "", token: "t"))
    }
}
