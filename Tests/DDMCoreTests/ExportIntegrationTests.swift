import XCTest
@testable import DDMCore

/// End-to-end: run the committed synthetic fixtures through the engine and the
/// OutputWriter, asserting that real declaration files and a report are written.
final class ExportIntegrationTests: XCTestCase {

    private func fixturesDir() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("fixtures")
    }

    func testFixturesExportEndToEnd() throws {
        let fixtures = fixturesDir()
        let names = ["applicationaccess-mixed.mobileconfig",
                     "mcx-managed-prefs.mobileconfig",
                     "legacy-only.mobileconfig"]
        let migrator = Migrator()
        let results = names.map { migrator.migrate(fileURL: fixtures.appendingPathComponent($0)) }

        for r in results { XCTAssertNil(r.error, "\(r.fileName): \(r.error ?? "")") }

        let outDir: URL
        if let env = ProcessInfo.processInfo.environment["DDM_EXPORT_DIR"] {
            outDir = URL(fileURLWithPath: env)
        } else {
            outDir = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("ddm-export-\(UUID().uuidString)")
        }

        let report = MigrationReport(results: results, generatedAtISO8601: "2026-06-23T00:00:00Z")
        let summary = try OutputWriter.write(report: report, to: outDir)

        XCTAssertTrue(FileManager.default.fileExists(atPath: summary.reportMarkdownURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: summary.reportJSONURL.path))
        XCTAssertGreaterThan(summary.filesWritten.count, 5)

        // Vendor-agnostic deployment guide is written and covers the vendors.
        XCTAssertTrue(FileManager.default.fileExists(atPath: summary.deploymentGuideURL.path))
        let guide = (try? String(contentsOf: summary.deploymentGuideURL, encoding: .utf8)) ?? ""
        for vendor in ["FleetDM", "Jamf Pro", "Kandji", "Addigy", "Mosyle", "Intune"] {
            XCTAssertTrue(guide.contains(vendor), "DEPLOYMENT.md missing \(vendor)")
        }

        // Payload-only companions exist for paste-based MDMs (e.g. Jamf).
        XCTAssertTrue(summary.filesWritten.contains { $0.lastPathComponent.hasSuffix(".payload.json") })

        // Fleet GitOps snippet is written and references the declarations.
        let fleetURL = try XCTUnwrap(summary.fleetGitOpsURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fleetURL.path))
        let fleet = (try? String(contentsOf: fleetURL, encoding: .utf8)) ?? ""
        XCTAssertTrue(fleet.contains("configuration_profiles"))
        XCTAssertTrue(fleet.contains(".ddm.json"))

        if ProcessInfo.processInfo.environment["DDM_EXPORT_DIR"] == nil {
            try? FileManager.default.removeItem(at: outDir)
        }
    }

    /// Validates the native CMS/PKCS7 decode path (stage 2a) against a genuinely
    /// CMS-signed profile. Gated on an env var so CI (which has no signed blob)
    /// stays green; run locally with DDM_SIGNED_FIXTURE pointing at a signed
    /// `.mobileconfig`.
    func testCMSSignedProfileIsDecodedNatively() throws {
        guard let path = ProcessInfo.processInfo.environment["DDM_SIGNED_FIXTURE"] else {
            throw XCTSkip("Set DDM_SIGNED_FIXTURE to a CMS-signed .mobileconfig to run.")
        }
        let result = Migrator().migrate(fileURL: URL(fileURLWithPath: path))
        XCTAssertNil(result.error, result.error ?? "")
        XCTAssertEqual(result.sourceFormat, .cmsSigned)
        XCTAssertFalse(result.payloads.isEmpty)
    }
}
