import SwiftUI
import UniformTypeIdentifiers
import AppKit
import DDMCore

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.isEmpty {
                DropZone(isTargeted: $isTargeted, onChoose: chooseFiles)
                    .padding(24)
            } else {
                ResultsList()
                    .overlay(alignment: .top) {
                        if model.isProcessing { processingBar }
                    }
            }
            Divider()
            footer
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop)
        .background(isTargeted ? Color.accentColor.opacity(0.06) : Color.clear)
        .frame(minWidth: 820, minHeight: 560)
        .onAppear(perform: applyDemoModeIfRequested)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("DDM Migrator").font(.headline)
                Text("Legacy .mobileconfig → Declarative Device Management (macOS 27)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !model.isEmpty {
                Button(role: .destructive) { model.clear() } label: {
                    Label("Clear", systemImage: "trash")
                }
                Button(action: chooseFiles) { Label("Add files…", systemImage: "plus") }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var footer: some View {
        HStack {
            if let path = model.lastExportSummaryPath {
                Label("Exported to \(path)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.caption).lineLimit(1).truncationMode(.middle)
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                }
                .controlSize(.small)
            } else if let err = model.exportError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).font(.caption).lineLimit(1)
            } else {
                Text(summaryLine).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: exportFiles) {
                Label("Export…", systemImage: "square.and.arrow.up")
            }
            .keyboardShortcut("e")
            .disabled(model.isEmpty || model.isProcessing)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var processingBar: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Processing…").font(.caption)
        }
        .padding(6)
        .background(.thinMaterial, in: Capsule())
        .padding(.top, 8)
    }

    private var summaryLine: String {
        let declarations = model.profiles.reduce(0) { $0 + $1.declarationCount }
        let payloads = model.profiles.reduce(0) { $0 + $1.sourcePayloadCount }
        return "\(model.profiles.count) profile(s) · \(payloads) payload(s) · \(declarations) declaration(s)"
    }

    // MARK: Demo mode (for screenshots / kicking the tires)
    //
    // Set DDM_DEMO_FILES to a colon-separated list of .mobileconfig paths to
    // preload them on launch. Optionally set DDM_DEMO_WINDOW to "x,y,w,h" (top-
    // left origin, points) to place the window at a known spot for a clean
    // screenshot. Has no effect in normal use.
    private func applyDemoModeIfRequested() {
        let env = ProcessInfo.processInfo.environment
        if let frame = env["DDM_DEMO_WINDOW"] {
            let n = frame.split(separator: ",").compactMap { Double($0) }
            if n.count == 4, let screen = NSScreen.main, let win = NSApp.windows.first {
                win.setContentSize(NSSize(width: n[2], height: n[3]))
                win.setFrameTopLeftPoint(
                    NSPoint(x: n[0], y: screen.frame.height - n[1]))
                win.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                // Report the exact on-screen frame (top-left origin, points) so
                // a screenshot script can crop precisely. Demo-only.
                if let path = env["DDM_DEMO_FRAMEFILE"] {
                    let f = win.frame
                    let topY = screen.frame.height - (f.origin.y + f.height)
                    let line = "\(Int(f.origin.x)),\(Int(topY)),\(Int(f.width)),\(Int(f.height))"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        try? line.write(toFile: path, atomically: true, encoding: .utf8)
                    }
                }
            }
        }
        if let files = env["DDM_DEMO_FILES"], !files.isEmpty {
            model.ingest(urls: files.split(separator: ":").map { URL(fileURLWithPath: String($0)) })
        }
    }

    // MARK: Actions

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        var urls: [URL] = []
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { urls.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            model.ingest(urls: urls)
        }
        return true
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        if let type = UTType(filenameExtension: "mobileconfig") {
            panel.allowedContentTypes = [type, .folder]
        }
        panel.prompt = "Add"
        if panel.runModal() == .OK {
            model.ingest(urls: panel.urls)
        }
    }

    private func exportFiles() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Choose an output folder for .ddm.json files and the migration report."
        if panel.runModal() == .OK, let dir = panel.url {
            model.export(to: dir)
        }
    }
}

// MARK: - Status colours shared across views

extension ProfileStatus {
    var color: Color {
        switch self {
        case .migrated: return .green
        case .partial: return .orange
        case .legacyWrap: return .blue
        case .error: return .red
        }
    }
    var label: String {
        switch self {
        case .migrated: return "Migrated"
        case .partial: return "Partial"
        case .legacyWrap: return "Legacy wrap"
        case .error: return "Error"
        }
    }
}

extension Classification {
    var color: Color {
        switch self {
        case .migrated: return .green
        case .fannedOut: return .teal
        case .legacyWrapped: return .blue
        case .flagged: return .orange
        }
    }
}
