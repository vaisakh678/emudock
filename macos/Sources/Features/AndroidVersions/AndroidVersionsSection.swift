import SwiftUI

/// The "Android versions" part of the Android SDK sheet: installed system images,
/// their size, which emulators use them, and removing unused ones.
struct AndroidVersionsSection: View {
    let status: AndroidSDK.Status
    @Environment(SDKStatusModel.self) private var sdk
    @Environment(DevicesModel.self) private var devices
    @Environment(UpdatesModel.self) private var updates
    @State private var model = AndroidVersionsModel()
    @State private var pendingRemoval: String?

    /// Newest first; paths that aren't regular phone or tablet images go last.
    private var paths: [String] {
        let known = SystemImage.sorted(status.systemImages.compactMap { SystemImage(path: $0, isInstalled: true) }).map(\.path)
        return known + status.systemImages.filter { !known.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Android versions").font(.headline)
                InfoButton(title: "About Android versions") {
                    Text("Each Android version (a \"system image\") is a separate download of about 1–2 GB, shared by every emulator that runs it.")
                    Text("Remove versions you no longer use to free up space. You can download them again when creating a new device.")
                        .foregroundStyle(.secondary)
                }
                if model.totalSize > 0 {
                    Text("\(model.totalSize.formatted(.byteCount(style: .file))) total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(spacing: 0) {
                ForEach(paths, id: \.self) { path in
                    VersionRow(
                        path: path,
                        users: devices.devices.filter { $0.systemImage == path },
                        size: model.sizes[path],
                        isRemoving: model.removing == path,
                        blocker: AndroidVersionsModel.removalBlocker(for: path, installed: status.systemImages, avds: devices.devices),
                        isBusy: model.removing != nil
                    ) {
                        pendingRemoval = path
                    }
                    if path != paths.last { Divider() }
                }
            }
            .background(.background.secondary, in: .rect(cornerRadius: 8))

            if let error = model.errorMessage {
                Text(error)
                    .font(.caption.monospaced())
                    .foregroundStyle(.red)
                    .lineLimit(5)
                    .textSelection(.enabled)
            }
        }
        .task(id: status.systemImages) { await model.loadSizes(status: status) }
        .confirmationDialog(
            removalTitle,
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })
        ) {
            Button("Remove", role: .destructive) {
                guard let path = pendingRemoval else { return }
                pendingRemoval = nil
                Task { await model.remove(path, sdk: sdk, updates: updates) }
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text(removalMessage)
        }
    }

    private var removalTitle: String {
        guard let path = pendingRemoval else { return "" }
        return "Remove \(SystemImage(path: path, isInstalled: true)?.title ?? path)?"
    }

    private var removalMessage: String {
        guard let path = pendingRemoval else { return "" }
        let freed = model.sizes[path].map { "This frees \($0.formatted(.byteCount(style: .file))). " } ?? ""
        return freed + "You can download it again when creating a new device."
    }
}

private struct VersionRow: View {
    let path: String
    let users: [AVD]
    let size: Int64?
    let isRemoving: Bool
    let blocker: String?
    let isBusy: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if let image = SystemImage(path: path, isInstalled: true) {
                    HStack(spacing: 6) {
                        Text(image.title)
                        Text("· \(image.tagDisplay)").foregroundStyle(.secondary)
                    }
                } else {
                    Text(path).font(.callout.monospaced())
                }
                Text(users.isEmpty ? "Not used by any emulator" : "Used by \(users.map(\.displayName).formatted(.list(type: .and)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .help(path)

            Spacer(minLength: 8)

            Text(size.map { $0.formatted(.byteCount(style: .file)) } ?? "…")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)

            if isRemoving {
                ProgressView().controlSize(.small)
                    .frame(width: 70)
            } else {
                Button("Remove", action: onRemove)
                    .disabled(blocker != nil || isBusy)
                    .help(blocker ?? "Delete this Android version to free up space")
                    .frame(width: 70)
            }
        }
        .padding(10)
    }
}
