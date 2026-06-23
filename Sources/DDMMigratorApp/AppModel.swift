import Foundation
import SwiftUI
import DDMCore

/// View model: owns the list of processed profiles and drives the UI. All
/// engine work runs off the main actor; results are published back on it.
@MainActor
final class AppModel: ObservableObject {
    @Published var profiles: [ProfileResult] = []
    @Published var isProcessing = false
    @Published var lastExportSummaryPath: String?
    @Published var exportError: String?

    private let migrator = Migrator()

    var isEmpty: Bool { profiles.isEmpty }

    // MARK: Intake

    /// Accept dropped/selected URLs: files, or folders to scan recursively.
    func ingest(urls: [URL]) {
        let files = expandToProfileFiles(urls)
        guard !files.isEmpty else { return }
        isProcessing = true
        Task.detached(priority: .userInitiated) { [migrator] in
            let results = files.map { migrator.migrate(fileURL: $0) }
            await MainActor.run {
                // Replace any prior result for the same filename, then append new.
                var byName = Dictionary(self.profiles.map { ($0.fileName, $0) },
                                        uniquingKeysWith: { _, new in new })
                for r in results { byName[r.fileName] = r }
                self.profiles = byName.values.sorted { $0.fileName < $1.fileName }
                self.isProcessing = false
            }
        }
    }

    func clear() {
        profiles = []
        lastExportSummaryPath = nil
        exportError = nil
    }

    /// Walk folders and keep only `.mobileconfig` files.
    private func expandToProfileFiles(_ urls: [URL]) -> [URL] {
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
        return out
    }

    // MARK: Export

    func export(to directory: URL) {
        exportError = nil
        let report = MigrationReport(results: profiles,
                                     generatedAtISO8601: Self.timestamp())
        do {
            let summary = try OutputWriter.write(report: report, to: directory)
            lastExportSummaryPath = summary.outputDirectory.path
        } catch {
            exportError = error.localizedDescription
        }
    }

    static func timestamp() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: Date())
    }
}
