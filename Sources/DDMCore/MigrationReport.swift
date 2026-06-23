import Foundation

/// Stage 2f / 3c — the migration report. A first-class deliverable: it's what
/// gives an admin confidence that nothing was silently changed or dropped.
public struct MigrationReport: Sendable {
    public let results: [ProfileResult]
    public let generatedAtISO8601: String

    public init(results: [ProfileResult], generatedAtISO8601: String) {
        self.results = results
        self.generatedAtISO8601 = generatedAtISO8601
    }

    // MARK: Aggregates

    public var totalProfiles: Int { results.count }
    public var profilesWithErrors: Int { results.filter { $0.status == .error }.count }
    public var totalSourcePayloads: Int { results.reduce(0) { $0 + $1.sourcePayloadCount } }
    public var totalDeclarations: Int { results.reduce(0) { $0 + $1.declarationCount } }

    public var allPayloads: [PayloadResult] { results.flatMap { $0.payloads } }
    public var migratedCount: Int { allPayloads.filter { $0.classification == .migrated }.count }
    public var fannedOutCount: Int { allPayloads.filter { $0.classification == .fannedOut }.count }
    public var legacyCount: Int { allPayloads.filter { $0.classification == .legacyWrapped }.count }
    public var flaggedCount: Int { allPayloads.filter { $0.classification == .flagged }.count }

    // MARK: Markdown

    public func markdown() -> String {
        var md = ""
        md += "# DDM Migrator — Migration Report\n\n"
        md += "_Generated \(generatedAtISO8601)_\n\n"
        md += "Built clean-room from public Apple Developer documentation. "
        md += "Input is files; output is files. This tool does **not** push to any MDM "
        md += "or verify that declarations land on devices.\n\n"

        md += "## Summary\n\n"
        md += "| Metric | Count |\n|---|---:|\n"
        md += "| Profiles processed | \(totalProfiles) |\n"
        md += "| Profiles with errors | \(profilesWithErrors) |\n"
        md += "| Source payloads | \(totalSourcePayloads) |\n"
        md += "| Declarations produced | \(totalDeclarations) |\n"
        md += "| — payloads migrated 1:1 | \(migratedCount) |\n"
        md += "| — payloads fanned out | \(fannedOutCount) |\n"
        md += "| — payloads legacy-wrapped | \(legacyCount) |\n"
        md += "| — payloads flagged for review | \(flaggedCount) |\n\n"

        for result in results {
            md += "## \(result.status.symbol) `\(result.fileName)`\n\n"
            if let error = result.error {
                md += "> ⛔️ **Error:** \(error)\n\n"
                continue
            }
            md += "- Source format: **\(result.sourceFormat?.rawValue ?? "unknown")**\n"
            if let id = result.profileIdentifier { md += "- Profile identifier: `\(id)`\n" }
            if let name = result.profileDisplayName { md += "- Display name: \(name)\n" }
            md += "- Source payloads: \(result.sourcePayloadCount) · Declarations produced: \(result.declarationCount)\n\n"

            md += "| # | Source PayloadType | Disposition | Target / Reason |\n"
            md += "|---:|---|---|---|\n"
            for p in result.payloads.sorted(by: payloadOrder) {
                let target = p.targetDomains.isEmpty ? "—" : p.targetDomains.map { "`\($0)`" }.joined(separator: ", ")
                let detail = "\(target)<br/>\(p.reason)"
                md += "| \(p.sourceIndex) | `\(p.sourceType)` | \(p.classification.symbol) \(p.classification.rawValue) | \(detail) |\n"
            }
            md += "\n"
        }

        // Edge cases called out explicitly at the end.
        let flagged = allPayloads.filter { $0.classification == .flagged }
        if !flagged.isEmpty {
            md += "## ⚠️ Flagged for manual review\n\n"
            for p in flagged {
                md += "- `\(p.sourceType)` (payload #\(p.sourceIndex)): \(p.reason)\n"
            }
            md += "\n"
        }

        return md
    }

    /// A machine-readable JSON form of the report.
    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let payload = ReportJSON(
            generatedAt: generatedAtISO8601,
            summary: .init(totalProfiles: totalProfiles,
                           profilesWithErrors: profilesWithErrors,
                           totalSourcePayloads: totalSourcePayloads,
                           totalDeclarations: totalDeclarations,
                           migrated: migratedCount,
                           fannedOut: fannedOutCount,
                           legacyWrapped: legacyCount,
                           flagged: flaggedCount),
            profiles: results)
        return try encoder.encode(payload)
    }

    private func payloadOrder(_ a: PayloadResult, _ b: PayloadResult) -> Bool {
        if a.sourceIndex != b.sourceIndex { return a.sourceIndex < b.sourceIndex }
        return a.targetDomains.joined() < b.targetDomains.joined()
    }

    private struct ReportJSON: Encodable {
        let generatedAt: String
        let summary: Summary
        let profiles: [ProfileResult]
        struct Summary: Encodable {
            let totalProfiles: Int
            let profilesWithErrors: Int
            let totalSourcePayloads: Int
            let totalDeclarations: Int
            let migrated: Int
            let fannedOut: Int
            let legacyWrapped: Int
            let flagged: Int
        }
    }
}
