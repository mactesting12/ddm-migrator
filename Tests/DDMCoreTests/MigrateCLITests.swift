import XCTest
@testable import DDMCore

/// Tests for the headless CLI runner. Output is captured via closures, so these
/// stay fully in-process — no subprocess, no terminal.
final class MigrateCLITests: XCTestCase {

    private func fixturesDir() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("fixtures")
    }

    private func capture(_ args: [String],
                         env: [String: String] = [:]) -> (code: Int32, out: String, err: String) {
        var out = "", err = ""
        let code = MigrateCLI.run(args, environment: env, out: { out += $0 }, err: { err += $0 })
        return (code, out, err)
    }

    func testHelpAndVersion() {
        XCTAssertEqual(capture(["--help"]).code, 0)
        XCTAssertTrue(capture(["--help"]).out.contains("USAGE"))
        let v = capture(["--version"])
        XCTAssertEqual(v.code, 0)
        XCTAssertTrue(v.out.contains(MigrateCLI.version))
    }

    func testNoInputsIsUsageError() {
        let r = capture([])
        XCTAssertEqual(r.code, 2)
        XCTAssertTrue(r.err.contains("no input"))
    }

    func testMissingOutputIsUsageError() {
        let r = capture([fixturesDir().appendingPathComponent("legacy-only.mobileconfig").path])
        XCTAssertEqual(r.code, 2)
        XCTAssertTrue(r.err.contains("output directory"))
    }

    func testMigratesFolderAndWritesOutput() throws {
        let outDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ddm-cli-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outDir) }

        let r = capture([fixturesDir().path, "-o", outDir.path])
        XCTAssertEqual(r.code, 0)
        XCTAssertTrue(r.out.contains("processed"))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: outDir.appendingPathComponent("migration-report.md").path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: outDir.appendingPathComponent("fleet-gitops.yml").path))
    }

    func testStrictExitsNonZeroOnBadProfile() throws {
        let outDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ddm-cli-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outDir) }

        // not-a-profile.mobileconfig is intentionally invalid.
        let bad = fixturesDir().appendingPathComponent("not-a-profile.mobileconfig").path
        XCTAssertEqual(capture([bad, "-o", outDir.path, "--strict"]).code, 1)
        // Without --strict, the same input is a clean run (error surfaced, not fatal).
        XCTAssertEqual(capture([bad, "-o", outDir.path]).code, 0)
    }

    // MARK: Fleet push

    private func tmpOut() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ddm-cli-\(UUID().uuidString)")
    }

    func testFleetDryRunMakesNoCallsAndNeedsNoToken() throws {
        let outDir = tmpOut(); defer { try? FileManager.default.removeItem(at: outDir) }
        let r = capture([fixturesDir().appendingPathComponent("all-fanout-domains.mobileconfig").path,
                         "-o", outDir.path,
                         "--fleet-dry-run", "--fleet-url", "https://fleet.example.com", "--fleet-team", "3"])
        XCTAssertEqual(r.code, 0)
        XCTAssertTrue(r.out.contains("DRY RUN"))
        XCTAssertTrue(r.out.contains("team_id=3"))
        // Four fanned-out declarations would be uploaded.
        XCTAssertTrue(r.out.contains(".ddm.json"))
    }

    func testFleetPushWithoutTokenIsConfigError() throws {
        let outDir = tmpOut(); defer { try? FileManager.default.removeItem(at: outDir) }
        let r = capture([fixturesDir().appendingPathComponent("all-fanout-domains.mobileconfig").path,
                         "-o", outDir.path, "--push-fleet", "--fleet-url", "https://fleet.example.com"],
                        env: [:])
        XCTAssertEqual(r.code, 2)
        XCTAssertTrue(r.err.contains("FLEET_API_TOKEN"))
    }

    func testFleetPushWithoutURLIsConfigError() throws {
        let outDir = tmpOut(); defer { try? FileManager.default.removeItem(at: outDir) }
        let r = capture([fixturesDir().appendingPathComponent("all-fanout-domains.mobileconfig").path,
                         "-o", outDir.path, "--push-fleet"],
                        env: ["FLEET_API_TOKEN": "tok"])
        XCTAssertEqual(r.code, 2)
        XCTAssertTrue(r.err.contains("fleet-url"))
    }

    func testJamfDryRunNeedsNoCreds() throws {
        let outDir = tmpOut(); defer { try? FileManager.default.removeItem(at: outDir) }
        let r = capture([fixturesDir().appendingPathComponent("all-fanout-domains.mobileconfig").path,
                         "-o", outDir.path, "--jamf-dry-run", "--jamf-device-group", "g1"])
        XCTAssertEqual(r.code, 0)
        XCTAssertTrue(r.out.contains("DRY RUN"))
        XCTAssertTrue(r.out.contains("com.jamf.ddm.custom-declarations"))
    }

    func testJamfPushWithoutAnyCredentialsIsConfigError() throws {
        let outDir = tmpOut(); defer { try? FileManager.default.removeItem(at: outDir) }
        let r = capture([fixturesDir().appendingPathComponent("all-fanout-domains.mobileconfig").path,
                         "-o", outDir.path, "--push-jamf",
                         "--jamf-url", "https://us.apigw.jamf.com", "--jamf-tenant", "t1"],
                        env: [:])
        XCTAssertEqual(r.code, 2)
        XCTAssertTrue(r.err.contains("JAMF_CLIENT_ID"))
    }

    func testFleetDryRunSkipsLegacyByDefault() throws {
        let outDir = tmpOut(); defer { try? FileManager.default.removeItem(at: outDir) }
        // legacy-only produces only legacy-wrapped declarations → skipped by default.
        let r = capture([fixturesDir().appendingPathComponent("legacy-only.mobileconfig").path,
                         "-o", outDir.path, "--fleet-dry-run", "--fleet-url", "https://fleet.example.com"])
        XCTAssertEqual(r.code, 0)
        XCTAssertTrue(r.out.contains("skipping"))
        XCTAssertTrue(r.out.contains("nothing to push"))
    }
}
