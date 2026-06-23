import XCTest
@testable import DDMCore

/// Unit tests for the DDMCore engine. Fully headless — no UI.
///
/// Fixtures are generated in-code (synthetic, never real profile data). When
/// richer real-world fixtures arrive, drop synthetic `.mobileconfig` files into
/// the repo's `fixtures/` directory and load them here — see
/// `loadFixture(named:)` at the bottom for the intended hook.
final class DDMCoreTests: XCTestCase {

    let migrator = Migrator()

    // MARK: Helpers — synthetic profile builders

    /// Wrap payloads in a minimal profile dictionary and serialize to XML plist.
    private func makeProfile(identifier: String, payloads: [[String: Any]]) -> Data {
        let root: [String: Any] = [
            "PayloadType": "Configuration",
            "PayloadVersion": 1,
            "PayloadIdentifier": identifier,
            "PayloadUUID": "00000000-0000-0000-0000-000000000001",
            "PayloadDisplayName": "Synthetic Test Profile",
            "PayloadContent": payloads,
        ]
        return try! PropertyListSerialization.data(
            fromPropertyList: root, format: .xml, options: 0)
    }

    // MARK: 2a — decode / passthrough

    func testUnsignedProfileIsDetectedAsRawPlist() {
        let data = makeProfile(identifier: "test.raw", payloads: [
            ["PayloadType": "com.apple.dock", "PayloadIdentifier": "d1"]
        ])
        let result = migrator.migrate(data: data, fileName: "raw.mobileconfig")
        XCTAssertNil(result.error)
        XCTAssertEqual(result.sourceFormat, .rawPlist)
    }

    func testGarbageInputFailsCleanlyNoCrash() {
        let data = Data([0x00, 0x01, 0x02, 0xFF, 0xFE])
        let result = migrator.migrate(data: data, fileName: "junk.mobileconfig")
        XCTAssertNotNil(result.error)
        XCTAssertEqual(result.status, .error)
    }

    func testEmptyInput() {
        let result = migrator.migrate(data: Data(), fileName: "empty.mobileconfig")
        XCTAssertEqual(result.status, .error)
    }

    // MARK: 2d — applicationaccess fan-out (the centerpiece)

    func testApplicationAccessFansOutAndResidualStaysLegacy() {
        let payload: [String: Any] = [
            "PayloadType": "com.apple.applicationaccess",
            "PayloadIdentifier": "aa1",
            "PayloadDisplayName": "Restrictions",
            // Intelligence
            "allowGenmoji": false,
            "allowImagePlayground": true,
            // Siri
            "allowAssistant": false,
            // Keyboard
            "allowDictation": false,
            // Residual (no declarative home) -> legacy
            "allowCamera": false,
        ]
        let data = makeProfile(identifier: "test.aa", payloads: [payload])
        let result = migrator.migrate(data: data, fileName: "aa.mobileconfig")

        XCTAssertNil(result.error)

        let domains = Set(result.payloads.flatMap { $0.targetDomains })
        XCTAssertTrue(domains.contains("com.apple.configuration.intelligence.settings"))
        XCTAssertTrue(domains.contains("com.apple.configuration.siri.settings"))
        XCTAssertTrue(domains.contains("com.apple.configuration.keyboard.settings"))
        XCTAssertTrue(domains.contains("com.apple.configuration.legacy"))

        // Three fan-out branches + one legacy residual.
        let fanned = result.payloads.filter { $0.classification == .fannedOut }
        XCTAssertEqual(fanned.count, 3)
        let legacy = result.payloads.filter { $0.classification == .legacyWrapped }
        XCTAssertEqual(legacy.count, 1)

        // The intelligence declaration carries both intelligence keys.
        let intel = fanned.first { $0.targetDomains == ["com.apple.configuration.intelligence.settings"] }
        XCTAssertNotNil(intel)
        if case let .object(body)? = intel?.producedDeclarations.first?.payload {
            XCTAssertEqual(body["allowGenmoji"], .bool(false))
            XCTAssertEqual(body["allowImagePlayground"], .bool(true))
        } else {
            XCTFail("intelligence declaration payload missing")
        }

        // The residual legacy wrap preserves allowCamera and nothing else routable.
        let residual = legacy.first
        XCTAssertNotNil(residual?.preservedSource?["allowCamera"])
        XCTAssertNil(residual?.preservedSource?["allowGenmoji"])

        XCTAssertEqual(result.status, .partial) // fan-out + a legacy wrap = partial
    }

    func testApplicationAccessWithOnlyFannedKeysIsMigrated() {
        let payload: [String: Any] = [
            "PayloadType": "com.apple.applicationaccess",
            "allowAssistant": false,
        ]
        let data = makeProfile(identifier: "test.aa2", payloads: [payload])
        let result = migrator.migrate(data: data, fileName: "aa2.mobileconfig")
        XCTAssertEqual(result.status, .migrated) // no legacy residual
        XCTAssertEqual(result.declarationCount, 1)
    }

    // MARK: 2c — MCX unwrap

    func testMCXForcedUnwrap() {
        let mcx: [String: Any] = [
            "PayloadType": "com.apple.ManagedClient.preferences",
            "PayloadDisplayName": "Managed Prefs",
            "PayloadContent": [
                "com.example.app": [
                    "Forced": [
                        ["mcx_preference_settings": ["SomeKey": true, "Count": 3]]
                    ]
                ]
            ]
        ]
        let data = makeProfile(identifier: "test.mcx", payloads: [mcx])
        let result = migrator.migrate(data: data, fileName: "mcx.mobileconfig")
        XCTAssertNil(result.error)

        let p = result.payloads.first
        XCTAssertEqual(p?.classification, .legacyWrapped)
        XCTAssertTrue(p?.reason.contains("com.example.app") ?? false)
        // Preserved settings carried through.
        XCTAssertEqual(p?.preservedSource?["PreferenceDomain"], .string("com.example.app"))
        XCTAssertNotNil(p?.preservedSource?["Settings"]?["SomeKey"])
    }

    func testMCXSetOnceIsFlaggedNotDropped() {
        let mcx: [String: Any] = [
            "PayloadType": "com.apple.ManagedClient.preferences",
            "PayloadContent": [
                "com.example.setonce": [
                    "Set-Once": [
                        ["mcx_preference_settings": ["X": 1]]
                    ]
                ]
            ]
        ]
        let data = makeProfile(identifier: "test.mcx2", payloads: [mcx])
        let result = migrator.migrate(data: data, fileName: "mcx2.mobileconfig")
        let p = result.payloads.first
        XCTAssertEqual(p?.classification, .flagged)
        XCTAssertTrue(p?.reason.contains("Set-Once") ?? p?.reason.contains("Forced") ?? false)
    }

    func testMCXMultipleDomains() {
        let mcx: [String: Any] = [
            "PayloadType": "com.apple.ManagedClient.preferences",
            "PayloadContent": [
                "com.a": ["Forced": [["mcx_preference_settings": ["k": 1]]]],
                "com.b": ["Forced": [["mcx_preference_settings": ["k": 2]]]],
            ]
        ]
        let data = makeProfile(identifier: "test.mcx3", payloads: [mcx])
        let result = migrator.migrate(data: data, fileName: "mcx3.mobileconfig")
        XCTAssertEqual(result.payloads.filter { $0.classification == .legacyWrapped }.count, 2)
    }

    // MARK: 2e — legacy wrap

    func testUnknownPayloadIsLegacyWrappedNotDropped() {
        let payload: [String: Any] = [
            "PayloadType": "com.apple.dock",
            "PayloadDisplayName": "Dock",
            "tilesize": 48,
        ]
        let data = makeProfile(identifier: "test.dock", payloads: [payload])
        let result = migrator.migrate(data: data, fileName: "dock.mobileconfig")
        let p = result.payloads.first
        XCTAssertEqual(p?.classification, .legacyWrapped)
        XCTAssertEqual(p?.targetDomains, ["com.apple.configuration.legacy"])
        // Original content preserved verbatim.
        XCTAssertEqual(p?.preservedSource?["tilesize"], .int(48))
        XCTAssertEqual(result.status, .legacyWrap)
        // Legacy declaration is standards-shaped with a loud placeholder URL.
        if case let .object(body)? = p?.producedDeclarations.first?.payload {
            XCTAssertNotNil(body["ProfileAssetReference"])
            XCTAssertEqual(body["ProfileURL"], .string(LegacyWrap.profileURLPlaceholder))
        } else {
            XCTFail("legacy declaration payload missing")
        }
    }

    func testKnownLegacyHasSpecificReason() {
        let payload: [String: Any] = [
            "PayloadType": "com.apple.wifi.managed",
            "SSID_STR": "SyntheticNet",
        ]
        let data = makeProfile(identifier: "test.wifi", payloads: [payload])
        let result = migrator.migrate(data: data, fileName: "wifi.mobileconfig")
        XCTAssertTrue(result.payloads.first?.reason.contains("Wi-Fi") ?? false)
    }

    // MARK: determinism & serialization

    func testIdentifiersAreDeterministic() {
        let payload: [String: Any] = ["PayloadType": "com.apple.applicationaccess", "allowAssistant": false]
        let data = makeProfile(identifier: "test.det", payloads: [payload])
        let a = migrator.migrate(data: data, fileName: "det.mobileconfig")
        let b = migrator.migrate(data: data, fileName: "det.mobileconfig")
        let idA = a.payloads.first?.producedDeclarations.first?.identifier
        let idB = b.payloads.first?.producedDeclarations.first?.identifier
        XCTAssertNotNil(idA)
        XCTAssertEqual(idA, idB)
    }

    func testJSONValuePreservesIntBoolDistinction() {
        let json = JSONValue.object(["i": .int(42), "b": .bool(true), "d": .double(1.5)])
        let str = json.prettyPrintedString()
        XCTAssertTrue(str.contains("\"i\" : 42"))
        XCTAssertTrue(str.contains("\"b\" : true"))
        XCTAssertFalse(str.contains("42.0"))
    }

    // MARK: report

    func testReportAggregatesCountsAndMarkdown() {
        let aa: [String: Any] = [
            "PayloadType": "com.apple.applicationaccess",
            "allowGenmoji": false, "allowCamera": false,
        ]
        let dock: [String: Any] = ["PayloadType": "com.apple.dock", "tilesize": 48]
        let data = makeProfile(identifier: "test.report", payloads: [aa, dock])
        let result = migrator.migrate(data: data, fileName: "report.mobileconfig")

        let report = MigrationReport(results: [result], generatedAtISO8601: "2026-06-23T00:00:00Z")
        XCTAssertEqual(report.totalProfiles, 1)
        XCTAssertEqual(report.fannedOutCount, 1)         // intelligence branch
        XCTAssertGreaterThanOrEqual(report.legacyCount, 2) // residual + dock

        let md = report.markdown()
        XCTAssertTrue(md.contains("Migration Report"))
        XCTAssertTrue(md.contains("report.mobileconfig"))
        XCTAssertTrue(md.contains("com.apple.applicationaccess"))

        XCTAssertNoThrow(try report.jsonData())
    }

    // MARK: fixture hook (for future real-world synthetic fixtures)

    /// Loads a `.mobileconfig` from the repo `fixtures/` dir if present. Returns
    /// nil when not found so the suite stays green before fixtures are added.
    /// Drop synthetic fixtures into `fixtures/` and reference them by name.
    private func loadFixture(named name: String) -> Data? {
        // #filePath -> .../Tests/DDMCoreTests/DDMCoreTests.swift
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile.deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let fixture = repoRoot.appendingPathComponent("fixtures").appendingPathComponent(name)
        return try? Data(contentsOf: fixture)
    }

    func testSyntheticFixturesIfPresent() throws {
        guard let data = loadFixture(named: "applicationaccess-mixed.mobileconfig") else {
            throw XCTSkip("No fixture file present; in-code fixtures cover this path.")
        }
        let result = migrator.migrate(data: data, fileName: "applicationaccess-mixed.mobileconfig")
        XCTAssertNil(result.error)
    }

    func testFixtureAllFanOutDomainsProducesFourDomains() throws {
        guard let data = loadFixture(named: "all-fanout-domains.mobileconfig") else {
            throw XCTSkip("fixture missing")
        }
        let result = migrator.migrate(data: data, fileName: "all-fanout-domains.mobileconfig")
        let domains = Set(result.payloads.flatMap { $0.targetDomains })
        XCTAssertEqual(domains, [
            "com.apple.configuration.intelligence.settings",
            "com.apple.configuration.external-intelligence.settings",
            "com.apple.configuration.siri.settings",
            "com.apple.configuration.keyboard.settings",
        ])
        XCTAssertEqual(result.declarationCount, 4)
        XCTAssertEqual(result.status, .migrated) // no residual legacy
    }

    func testFixtureMCXSetOnceIsFlagged() throws {
        guard let data = loadFixture(named: "mcx-set-once.mobileconfig") else {
            throw XCTSkip("fixture missing")
        }
        let result = migrator.migrate(data: data, fileName: "mcx-set-once.mobileconfig")
        XCTAssertEqual(result.payloads.first?.classification, .flagged)
        XCTAssertEqual(result.status, .partial)
    }

    func testFixtureNotAProfileIsError() throws {
        guard let data = loadFixture(named: "not-a-profile.mobileconfig") else {
            throw XCTSkip("fixture missing")
        }
        let result = migrator.migrate(data: data, fileName: "not-a-profile.mobileconfig")
        XCTAssertEqual(result.status, .error)
        XCTAssertNotNil(result.error)
    }
}
