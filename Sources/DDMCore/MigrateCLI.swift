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
                           environment: [String: String] = ProcessInfo.processInfo.environment,
                           out: (String) -> Void = { FileHandle.standardOutput.write(Data($0.utf8)) },
                           err: (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) }) -> Int32 {
        var inputs: [String] = []
        var outputDir: String?
        var quiet = false
        var strict = false
        var writePayloadOnly = true
        var writePreserved = true
        var writeFleet = true
        // Fleet push (opt-in).
        var pushFleet = false
        var fleetURL: String?
        var fleetTeam: String?
        var fleetTeamField = "team_id"
        var fleetDryRun = false
        var fleetIncludeLegacy = false

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
            case "--push-fleet": pushFleet = true
            case "--fleet-url":
                i += 1
                guard i < args.count else { err("error: \(arg) requires a URL\n"); return 2 }
                fleetURL = args[i]
            case "--fleet-team":
                i += 1
                guard i < args.count else { err("error: \(arg) requires an id\n"); return 2 }
                fleetTeam = args[i]
            case "--fleet-team-field":
                i += 1
                guard i < args.count else { err("error: \(arg) requires a field name\n"); return 2 }
                fleetTeamField = args[i]
            case "--fleet-dry-run": fleetDryRun = true; pushFleet = true
            case "--fleet-include-legacy": fleetIncludeLegacy = true
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

        var pushFailed = false
        if pushFleet {
            let code = pushToFleet(report: report,
                                   urlString: fleetURL,
                                   team: fleetTeam,
                                   teamField: fleetTeamField,
                                   includeLegacy: fleetIncludeLegacy,
                                   dryRun: fleetDryRun,
                                   environment: environment,
                                   out: out, err: err)
            if code != 0 {
                if code == 2 { return 2 }   // configuration error — fatal
                pushFailed = true
            }
        }

        let errored = results.filter { $0.status == .error }.count
        if pushFailed { return 1 }
        if strict && errored > 0 { return 1 }
        return 0
    }

    /// Push produced declarations to Fleet. Returns 0 (ok), 1 (some uploads
    /// failed), or 2 (configuration error — missing URL/token).
    private static func pushToFleet(report: MigrationReport,
                                    urlString: String?,
                                    team: String?,
                                    teamField: String,
                                    includeLegacy: Bool,
                                    dryRun: Bool,
                                    environment: [String: String],
                                    out: (String) -> Void,
                                    err: (String) -> Void) -> Int32 {
        // Which declarations to push: skip legacy wraps by default (their
        // ProfileURL is a placeholder and not deployable as-is).
        struct Item { let fileName: String; let type: String; let data: Data }
        var items: [Item] = []
        for profile in report.results {
            for p in profile.payloads where !p.producedDeclarations.isEmpty {
                if p.classification == .legacyWrapped && !includeLegacy { continue }
                for decl in p.producedDeclarations {
                    guard let data = try? decl.jsonData() else { continue }
                    items.append(Item(fileName: decl.suggestedFileName(), type: decl.type, data: data))
                }
            }
        }

        guard let urlString, !urlString.isEmpty else {
            err("error: --push-fleet requires --fleet-url <https://your-fleet>\n")
            return 2
        }

        out("\nFleet push → \(normalizedHost(urlString))/api/v1/fleet/configuration_profiles\n")
        if team != nil { out("  target \(teamField)=\(team!)\n") }
        let skipped = report.allPayloads.filter { $0.classification == .legacyWrapped }.count
        if skipped > 0 && !includeLegacy {
            out("  (skipping \(skipped) legacy-wrapped declaration(s); pass --fleet-include-legacy to send them)\n")
        }

        if items.isEmpty {
            out("  nothing to push.\n")
            return 0
        }

        if dryRun {
            out("  DRY RUN — would upload \(items.count) declaration(s):\n")
            for it in items { out("    • \(it.fileName)  [\(it.type)]\n") }
            return 0
        }

        guard let token = environment["FLEET_API_TOKEN"], !token.isEmpty else {
            err("error: set FLEET_API_TOKEN in the environment to push to Fleet\n")
            return 2
        }
        guard let client = FleetClient(baseURLString: urlString, token: token) else {
            err("error: invalid --fleet-url\n")
            return 2
        }

        var failures = 0
        for it in items {
            let r = client.upload(fileName: it.fileName, data: it.data,
                                  teamID: team, teamFieldName: teamField)
            if r.success {
                out("  ✅ \(it.fileName) → \(r.profileUUID ?? "uploaded")\n")
            } else if r.exists {
                out("  ↩︎ \(it.fileName) — already exists (409), skipped\n")
            } else {
                failures += 1
                let detail = r.message ?? "HTTP \(r.statusCode)"
                out("  ⛔️ \(it.fileName) — \(detail) (HTTP \(r.statusCode))\n")
            }
        }
        out("Fleet push: \(items.count - failures)/\(items.count) succeeded\n")
        return failures > 0 ? 1 : 0
    }

    private static func normalizedHost(_ s: String) -> String {
        var h = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if !h.contains("://") { h = "https://" + h }
        while h.hasSuffix("/") { h.removeLast() }
        return h
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

    FLEET PUSH (opt-in — the only feature that talks to an MDM):
          --push-fleet            Upload produced declarations to Fleet.
          --fleet-url <url>       Fleet server URL (required with --push-fleet).
          --fleet-team <id>       Team/"fleet" id to scope to (default: Unassigned).
          --fleet-team-field <n>  Form field for the id (default: team_id;
                                  newer Fleet builds use fleet_id).
          --fleet-dry-run         Show what would be uploaded; make no calls.
          --fleet-include-legacy  Also push legacy-wrapped declarations
                                  (their ProfileURL is a placeholder — off by default).
      The API token is read from the FLEET_API_TOKEN environment variable
      (never a flag, never logged).

    EXAMPLES:
      ddm-migrate profiles/ -o out/
      ddm-migrate a.mobileconfig b.mobileconfig -o out/ --strict
      FLEET_API_TOKEN=… ddm-migrate profiles/ -o out/ \\
        --push-fleet --fleet-url https://fleet.example.com --fleet-team 3

    """
}
