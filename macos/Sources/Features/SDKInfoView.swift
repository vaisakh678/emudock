import SwiftUI

/// Where each SDK tool was found, shown from the Devices toolbar.
struct SDKInfoView: View {
    let status: AndroidSDK.Status
    @Environment(SDKStatusModel.self) private var sdk
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                details
                    .padding(28)
            }
            Divider()
            HStack {
                Button("Check Again") {
                    Task { await sdk.refresh() }
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 640, height: 640)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Android SDK ready", systemImage: "checkmark.seal.fill")
                .font(.title2.bold())
                .foregroundStyle(.green)

            Text(status.root?.path(percentEncoded: false) ?? "")
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                ToolRow(name: "java", url: status.javaHome)
                ToolRow(name: "sdkmanager", url: status.sdkmanager)
                ToolRow(name: "avdmanager", url: status.avdmanager)
                ToolRow(name: "emulator", url: status.emulator)
                ToolRow(name: "adb", url: status.adb)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("System images").font(.headline)
                ForEach(status.systemImages, id: \.self) { image in
                    Text(image).font(.callout.monospaced()).foregroundStyle(.secondary)
                }
            }

            Divider()
            UpdatesSection(status: status)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ToolRow: View {
    let name: String
    let url: URL?

    var body: some View {
        GridRow {
            Image(systemName: url == nil ? "xmark.circle" : "checkmark.circle.fill")
                .foregroundStyle(url == nil ? .red : .green)
            Text(name).font(.body.monospaced())
            Text(url?.path(percentEncoded: false) ?? "Missing")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
