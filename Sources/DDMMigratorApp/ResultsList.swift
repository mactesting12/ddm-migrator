import SwiftUI
import DDMCore

/// The results table: one expandable row per input profile.
struct ResultsList: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                // Column header
                HStack {
                    Text("Profile").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Status").frame(width: 120, alignment: .leading)
                    Text("Payloads").frame(width: 80, alignment: .trailing)
                    Text("Declarations").frame(width: 100, alignment: .trailing)
                }
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.top, 8)

                ForEach(model.profiles) { profile in
                    ProfileRow(profile: profile)
                }
            }
            .padding(12)
        }
    }
}

/// Demo flags (screenshots): DDM_DEMO_EXPAND=1 expands rows AND shows JSON;
/// DDM_DEMO_EXPAND=rows expands rows but leaves JSON collapsed.
private let demoExpandValue = ProcessInfo.processInfo.environment["DDM_DEMO_EXPAND"] ?? ""
private let demoExpandRows = demoExpandValue == "1" || demoExpandValue == "rows"
private let demoShowJSON = demoExpandValue == "1"

private struct ProfileRow: View {
    let profile: ProfileResult
    @State private var expanded = demoExpandRows

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption).foregroundStyle(.secondary).frame(width: 14)
                    Text(profile.status.symbol)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(profile.fileName).fontWeight(.medium).lineLimit(1)
                        if let name = profile.profileDisplayName {
                            Text(name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    StatusBadge(status: profile.status)
                        .frame(width: 120, alignment: .leading)
                    Text("\(profile.sourcePayloadCount)")
                        .frame(width: 80, alignment: .trailing).monospacedDigit()
                    Text("\(profile.declarationCount)")
                        .frame(width: 100, alignment: .trailing).monospacedDigit()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12).padding(.vertical, 10)

            if expanded {
                Divider().padding(.leading, 12)
                if let error = profile.error {
                    Label(error, systemImage: "exclamationmark.octagon.fill")
                        .foregroundStyle(.red).font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                } else {
                    VStack(spacing: 10) {
                        ForEach(profile.payloads) { payload in
                            PayloadDetail(payload: payload)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(profile.status.color.opacity(0.35)))
    }
}

private struct StatusBadge: View {
    let status: ProfileStatus
    var body: some View {
        Text(status.label)
            .font(.caption).fontWeight(.semibold)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(status.color.opacity(0.18)))
            .foregroundStyle(status.color)
    }
}

private struct PayloadDetail: View {
    let payload: PayloadResult
    @State private var showJSON = demoShowJSON

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Text(payload.classification.symbol)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(payload.sourceType).font(.system(.callout, design: .monospaced)).fontWeight(.medium)
                        Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                        if payload.targetDomains.isEmpty {
                            Text("(no declaration)").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text(payload.targetDomains.map(shortDomain).joined(separator: ", "))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(payload.classification.color)
                        }
                    }
                    Text(payload.reason).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if !payload.producedDeclarations.isEmpty {
                    Button(showJSON ? "Hide JSON" : "Show JSON") {
                        withAnimation(.easeInOut(duration: 0.12)) { showJSON.toggle() }
                    }
                    .controlSize(.small).buttonStyle(.borderless)
                }
            }

            if showJSON {
                ForEach(Array(payload.producedDeclarations.enumerated()), id: \.offset) { _, decl in
                    JSONPreview(text: decl.envelope().prettyPrintedString())
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(payload.classification.color.opacity(0.06)))
    }

    private func shortDomain(_ d: String) -> String {
        d.replacingOccurrences(of: "com.apple.configuration.", with: "…")
    }
}

/// A monospaced, lightly syntax-highlighted JSON viewer.
struct JSONPreview: View {
    let text: String
    var body: some View {
        ScrollView(.horizontal) {
            Text(highlighted)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
        }
        .frame(maxHeight: 240)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
    }

    /// Minimal highlighting: keys, string values, and literals get a tint.
    private var highlighted: AttributedString {
        var result = AttributedString(text)
        for (pattern, color) in JSONPreview.rules {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = text as NSString
            for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let r = match.range(at: match.numberOfRanges - 1)
                if let range = Range(r, in: text),
                   let attrRange = Range(range, in: result) {
                    result[attrRange].foregroundColor = color
                }
            }
        }
        return result
    }

    private static let rules: [(String, Color)] = [
        ("\"(.*?)\"\\s*:", .purple),                 // keys
        (":\\s*(\"[^\"]*\")", .brown),               // string values
        (":\\s*(true|false|null)", .orange),          // literals
        (":\\s*(-?[0-9.]+)", .blue),                  // numbers
    ]
}
