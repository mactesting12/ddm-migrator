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

    private func capture(_ args: [String]) -> (code: Int32, out: String, err: String) {
        var out = "", err = ""
        let code = MigrateCLI.run(args, out: { out += $0 }, err: { err += $0 })
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
}
