import SwiftUI

/// The "Updates" part of the Android SDK sheet.
struct UpdatesSection: View {
    let status: AndroidSDK.Status
    @Environment(UpdatesModel.self) private var updates
    @Environment(SDKStatusModel.self) private var sdk
    @Environment(DevicesModel.self) private var devices

    /// Updating the emulator while emulators are running can fail on files in use.
    private var blockedByRunningEmulators: Bool {
        updates.selection.contains("emulator") && !devices.running.isEmpty
    }

    var body: some View {
        @Bindable var updates = updates
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Updates").font(.headline)
                if let lastChecked = updates.lastChecked {
                    Text("Checked \(lastChecked, format: .relative(presentation: .named))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if updates.phase == .checking {
                    ProgressView().controlSize(.small)
                    Text("Checking…").font(.callout).foregroundStyle(.secondary)
                } else {
                    Button("Check Now") {
                        Task { await updates.check(status: status) }
                    }
                    .disabled(updates.isBusy)
                }
            }

            if updates.updates.isEmpty {
                if updates.lastChecked != nil && updates.phase != .checking {
                    Label("Everything is up to date", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(updates.updates) { update in
                        UpdateRow(update: update, isSelected: Binding(
                            get: { updates.selection.contains(update.id) },
                            set: { selected in
                                if selected { updates.selection.insert(update.id) } else { updates.selection.remove(update.id) }
                            }
                        ))
                        if update.id != updates.updates.last?.id { Divider() }
                    }
                }
                .background(.background.secondary, in: .rect(cornerRadius: 8))
                .disabled(updates.isBusy)

                if blockedByRunningEmulators {
                    Label("Stop running emulators before updating the emulator.", systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }

            switch updates.phase {
            case let .installing(fraction, detail):
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let fraction {
                            ProgressView(value: fraction)
                        } else {
                            ProgressView().progressViewStyle(.linear)
                        }
                        Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Button("Cancel", role: .cancel) { updates.cancel() }
                }
            case let .failed(message):
                Text(message)
                    .font(.caption.monospaced())
                    .foregroundStyle(.red)
                    .lineLimit(5)
                    .textSelection(.enabled)
            case .idle, .checking:
                EmptyView()
            }

            if !updates.updates.isEmpty && !updates.isBusy {
                Button("Update Selected (\(updates.selection.count))") {
                    updates.installSelected(sdk: sdk)
                }
                .disabled(updates.selection.isEmpty || blockedByRunningEmulators)
            }
        }
    }
}

private struct UpdateRow: View {
    let update: PackageUpdate
    @Binding var isSelected: Bool

    var body: some View {
        Toggle(isOn: $isSelected) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(update.displayName)
                    Text(update.path).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(update.installed) → \(update.available)")
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.checkbox)
        .padding(10)
    }
}
