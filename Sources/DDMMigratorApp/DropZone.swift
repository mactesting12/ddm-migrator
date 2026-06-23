import SwiftUI

/// The empty-state drop target with a short explainer.
struct DropZone: View {
    @Binding var isTargeted: Bool
    var onChoose: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: isTargeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.tint)
            Text("Drop .mobileconfig files or a folder")
                .font(.title3).fontWeight(.medium)
            Text("DDM Migrator reads legacy configuration profiles and converts each payload\ninto Declarative Device Management declarations for macOS 27.\n\nInput is files. Output is files. Nothing is sent to any MDM.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: onChoose) {
                Label("Choose files…", systemImage: "folder")
            }
            .controlSize(.large)
            .padding(.top, 4)

            legend.padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.4))
        )
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem("✅", "migrated")
            legendItem("🔀", "fanned out")
            legendItem("📦", "legacy wrap")
            legendItem("⚠️", "review")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func legendItem(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 4) { Text(symbol); Text(text) }
    }
}
