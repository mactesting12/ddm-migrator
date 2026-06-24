import Foundation

/// Headless command-line runner over the engine. Lives in DDMCore so it can be
/// unit-tested; the `ddm-migrate` executable is a one-line `main.swift` that
/// calls `MigrateCLI.run`.
///
/// Output is injected via `out`/`err` closures so tests can capture it instead
/// of writing to the terminal.
public enum MigrateCLI {

    public static let version = "1.0.0"

    /// Run the CLI. Returns the process exit code.
    /// - 0: success
    /// - 1: `--strict` and at least one profile failed
    /// - 2: usage error / nothing to do / write failure
    public static func run(_ args: [String],
                           out: (String) -> Void = { FileHandle.standardOutput.write(Data($0.utf8)) },
                           err: (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) }) -> Int32 {
        var inputs: [String] = []
        var outputDir: String?
        var quiet = false
        var strict = false
        var writePayloadOnly = true
        var writePreserved = true
        var writeFleet = true

        var i = 0
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "-h", "--help":
                out(usage)
                return 0
            case "--version":
                out("ddm-migrate \(version)\n")
                return 0
            case "-o", "--output":
                i += 1
                guard i < args.count else { err("error: \(arg) requires a directory\n"); return 2 }
                outputDir = args[i]
            case "-q", "--quiet": quiet = true
            case "--strict": strict = true
            case "--no-payload-only": writePayloadOnly = false
            case "--no-preserved": writePreserved = false
            case "--no-fleet": writeFleet = false
            default:
                if arg.hasPrefix("-") {
                    err("error: unknown option '\(arg)'\n\n\(usage)")
                    return 2
                }
                inputs.append(arg)
            }
            i += 1
        }

        guard !inputs.isEmpty else {
            err("error: no input files or folders given\n\n\(usage)")
            return 2
        }
        guard let outputDir else {
            err("error: an output directory is required (-o <dir>)\n\n\(usage)")
            return 2
        }

        let files = expandToProfileFiles(inputs.map { URL(fileURLWithPath: $0) })
        guard !files.isEmpty else {
            err("error: no .mobileconfig files found in the given inputs\n")
            return 2
        }

        let migrator = Migrator()
        let results = files.map { migrator.migrate(fileURL: $0) }
        let report = MigrationReport(results: results, generatedAtISO8601: timestamp())

        let summary: OutputWriter.WriteSummary
        do {
            summary = try OutputWriter.write(
                report: report,
                to: URL(fileURLWithPath: outputDir),
                writePreservedPlists: writePreserved,
                writePayloadOnlyFiles: writePayloadOnly,
                writeFleetGitOps: writeFleet)
        } catch {
            err("error: could not write output: \(error.localizedDescription)\n")
            return 2
        }

        if !quiet {
            out(renderSummary(report: report, summary: summary))
        }

        let errored = results.filter { $0.status == .error }.count
        if strict && errored > 0 { return 1 }
        return 0
    }

    // MARK: rendering

    private static func renderSummary(report: MigrationReport,
                                      summary: OutputWriter.WriteSummary) -> String {
        var s = "DDM Migrator \(version) — processed \(report.totalProfiles) profile(s)\n\n"
        for r in report.results.sorted(by: { $0.fileName < $1.fileName }) {
            let status = "\(r.status.symbol) \(r.status.rawValue)".padding(toLength: 16, withPad: " ", startingAt: 0)
            if let e = r.error {
                s += "  \(status) \(r.fileName) — \(e)\n"
            } else {
                s += "  \(status) \(r.fileName) — \(r.sourcePayloadCount) payload(s) → \(r.declarationCount) declaration(s)\n"
            }
        }
        s += "\nTotals: "
        s += "\(report.migratedCount) migrated, \(report.fannedOutCount) fanned out, "
        s += "\(report.legacyCount) legacy-wrapped, \(report.flaggedCount) flagged"
        if report.profilesWithErrors > 0 { s += ", \(report.profilesWithErrors) file error(s)" }
        s += "\n"
        s += "Wrote \(summary.filesWritten.count) file(s) to \(summary.outputDirectory.path)\n"
        s += "  report: \(summary.reportMarkdownURL.lastPathComponent)\n"
        s += "  deploy: \(summary.deploymentGuideURL.lastPathComponent)\n"
        if let fleet = summary.fleetGitOpsURL {
            s += "  fleet:  \(fleet.lastPathComponent)\n"
        }
        return s
    }

    // MARK: helpers

    static func expandToProfileFiles(_ urls: [URL]) -> [URL] {
        let fm = FileManager.default
        var out: [URL] = []
        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                if let en = fm.enumerator(at: url, includingPropertiesForKeys: nil) {
                    for case let f as URL in en where f.pathExtension.lowercased() == "mobileconfig" {
                        out.append(f)
                    }
                }
            } else if url.pathExtension.lowercased() == "mobileconfig" {
                out.append(url)
            }
        }
        return out.sorted { $0.path < $1.path }
    }

    private static func timestamp() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: Date())
    }

    static let usage = """
    ddm-migrate — migrate legacy .mobileconfig profiles to DDM declarations

    USAGE:
      ddm-migrate <inputs...> -o <output-dir> [options]

    ARGUMENTS:
      <inputs...>            One or more .mobileconfig files or folders to scan.

    OPTIONS:
      -o, --output <dir>     Output directory for declarations + reports (required).
      -q, --quiet            Suppress the per-file summary.
          --strict           Exit non-zero if any input fails to parse.
          --no-payload-only  Don't write .payload.json companions (Jamf paste).
          --no-preserved     Don't write .preserved.plist companions (legacy).
          --no-fleet         Don't write the fleet-gitops.yml snippet.
      -h, --help             Show this help.
          --version          Show the version.

    EXAMPLES:
      ddm-migrate profiles/ -o out/
      ddm-migrate a.mobileconfig b.mobileconfig -o out/ --strict

    """
}
