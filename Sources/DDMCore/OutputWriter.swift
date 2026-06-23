import Foundation

/// Stage 2f — write engine output to disk.
///
/// Layout under the chosen output folder:
///
///   <output>/
///     migration-report.md
///     migration-report.json
///     <profile-base-name>/
///       siri.settings.a1b2c3d4.ddm.json
///       intelligence.settings.5e6f7a8b.ddm.json
///       legacy.9c0d1e2f.ddm.json
///       legacy.9c0d1e2f.preserved.plist   (verbatim original payload)
///
/// Everything is grouped per source profile so a batch stays organized.
public enum OutputWriter {

    public struct WriteSummary: Sendable {
        public let outputDirectory: URL
        public let filesWritten: [URL]
        public let reportMarkdownURL: URL
        public let reportJSONURL: URL
        public let deploymentGuideURL: URL
        public let fleetGitOpsURL: URL?
    }

    public enum WriteError: Error, LocalizedError {
        case couldNotCreateDirectory(String)
        public var errorDescription: String? {
            switch self {
            case .couldNotCreateDirectory(let p): return "Could not create directory: \(p)"
            }
        }
    }

    @discardableResult
    public static func write(report: MigrationReport,
                             to outputDirectory: URL,
                             writePreservedPlists: Bool = true,
                             writePayloadOnlyFiles: Bool = true,
                             writeFleetGitOps: Bool = true) throws -> WriteSummary {
        let fm = FileManager.default
        try ensureDirectory(outputDirectory, fm: fm)

        var written: [URL] = []
        var fleetEntries: [FleetGitOps.Entry] = []

        for profile in report.results {
            guard profile.error == nil, !profile.payloads.isEmpty else { continue }
            let folderName = sanitize(baseName(of: profile.fileName))
            let profileDir = outputDirectory.appendingPathComponent(folderName, isDirectory: true)
            try ensureDirectory(profileDir, fm: fm)

            for p in profile.payloads {
                for decl in p.producedDeclarations {
                    let fileURL = uniqueURL(in: profileDir, fileName: decl.suggestedFileName(), fm: fm)
                    try decl.jsonData().write(to: fileURL, options: .atomic)
                    written.append(fileURL)
                    fleetEntries.append(FleetGitOps.Entry(
                        sourceFile: profile.fileName,
                        relativePath: "./\(folderName)/\(fileURL.lastPathComponent)",
                        classification: p.classification))

                    // Payload-only companion for paste-based MDMs (e.g. Jamf Pro
                    // Blueprints, which wants the Payload object, not the envelope).
                    if writePayloadOnlyFiles {
                        let payloadURL = fileURL
                            .deletingPathExtension()        // drop .json
                            .deletingPathExtension()        // drop .ddm
                            .appendingPathExtension("payload.json")
                        if let data = try? decl.payload.prettyPrintedData() {
                            try? data.write(to: payloadURL, options: .atomic)
                            written.append(payloadURL)
                        }
                    }

                    // Companion file preserving the original payload verbatim.
                    if writePreservedPlists, let preserved = p.preservedSource {
                        let preservedURL = fileURL
                            .deletingPathExtension()        // drop .json
                            .deletingPathExtension()        // drop .ddm
                            .appendingPathExtension("preserved.plist")
                        if let data = try? preservedPlistData(preserved) {
                            try? data.write(to: preservedURL, options: .atomic)
                            written.append(preservedURL)
                        }
                    }
                }
            }
        }

        // Reports at the top level.
        let mdURL = outputDirectory.appendingPathComponent("migration-report.md")
        try Data(report.markdown().utf8).write(to: mdURL, options: .atomic)
        written.append(mdURL)

        let jsonURL = outputDirectory.appendingPathComponent("migration-report.json")
        try report.jsonData().write(to: jsonURL, options: .atomic)
        written.append(jsonURL)

        // Vendor-agnostic deployment guide.
        let deployURL = outputDirectory.appendingPathComponent("DEPLOYMENT.md")
        try Data(DeploymentGuide.markdown(report: report).utf8).write(to: deployURL, options: .atomic)
        written.append(deployURL)

        // Fleet GitOps snippet (files-only; references the .ddm.json declarations).
        var fleetURL: URL?
        if writeFleetGitOps {
            let url = outputDirectory.appendingPathComponent("fleet-gitops.yml")
            try Data(FleetGitOps.yaml(entries: fleetEntries).utf8).write(to: url, options: .atomic)
            written.append(url)
            fleetURL = url
        }

        return WriteSummary(outputDirectory: outputDirectory,
                            filesWritten: written,
                            reportMarkdownURL: mdURL,
                            reportJSONURL: jsonURL,
                            deploymentGuideURL: deployURL,
                            fleetGitOpsURL: fleetURL)
    }

    // MARK: helpers

    private static func ensureDirectory(_ url: URL, fm: FileManager) throws {
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue { return }
        do {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw WriteError.couldNotCreateDirectory(url.path)
        }
    }

    private static func preservedPlistData(_ value: JSONValue) throws -> Data {
        try PropertyListSerialization.data(
            fromPropertyList: value.foundationObject(),
            format: .xml, options: 0)
    }

    static func baseName(of fileName: String) -> String {
        var name = fileName
        for ext in [".mobileconfig", ".plist", ".xml"] {
            if name.lowercased().hasSuffix(ext) {
                name = String(name.dropLast(ext.count))
                break
            }
        }
        return name.isEmpty ? "profile" : name
    }

    static func sanitize(_ name: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        return name.components(separatedBy: bad).joined(separator: "_")
    }

    /// Avoid clobbering when two declarations suggest the same file name.
    private static func uniqueURL(in dir: URL, fileName: String, fm: FileManager) -> URL {
        let candidate = dir.appendingPathComponent(fileName)
        if !fm.fileExists(atPath: candidate.path) { return candidate }
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var i = 2
        while true {
            let next = dir.appendingPathComponent("\(base)-\(i).\(ext)")
            if !fm.fileExists(atPath: next.path) { return next }
            i += 1
        }
    }
}
