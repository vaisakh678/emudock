import SwiftUI

struct DevicesView: View {
    let status: AndroidSDK.Status
    @Environment(DevicesModel.self) private var devices
    @Environment(SDKStatusModel.self) private var sdk
    @Environment(UpdatesModel.self) private var updates
    @State private var showingSDK = false
    @State private var newDevice: NewDeviceModel?
    @State private var selection: Set<String> = []
    @State private var pendingDeletion: [AVD] = []
    @State private var editing: EditDeviceModel?
    @State private var renaming: AVD?
    @State private var newName = ""

    var body: some View {
        @Bindable var devices = devices
        NavigationStack {
            Group {
                if devices.devices.isEmpty {
                    ContentUnavailableView {
                        Label("No emulators yet", systemImage: "smartphone")
                    } description: {
                        Text("Create an emulator to get started.")
                    } actions: {
                        Button("New Device") { showNewDevice() }
                    }
                } else {
                    List(devices.devices, selection: $selection) { avd in
                        DeviceRow(avd: avd) { edit(avd) }
                    }
                    .listStyle(.inset)
                    .contextMenu(forSelectionType: String.self) { ids in
                        contextMenu(for: devices.devices.filter { ids.contains($0.id) })
                    }
                    .onDeleteCommand { requestDeletion(of: selection) }
                }
            }
            .navigationTitle("Devices")
            .toolbar {
                if !updates.updates.isEmpty {
                    ToolbarItem {
                        Button {
                            showingSDK = true
                        } label: {
                            Label(
                                updates.updates.count == 1 ? "1 Update" : "\(updates.updates.count) Updates",
                                systemImage: "arrow.down.circle.fill"
                            )
                            .labelStyle(.titleAndIcon)
                        }
                        .help("SDK updates are available")
                    }
                }
                ToolbarItem {
                    Button("Delete", systemImage: "trash") { requestDeletion(of: selection) }
                        .disabled(deletable(selection).isEmpty)
                        .help("Delete the selected emulators")
                }
                ToolbarItem {
                    Button("New Device", systemImage: "plus") { showNewDevice() }
                }
                ToolbarItem {
                    Button("Android SDK", systemImage: "wrench.and.screwdriver") { showingSDK = true }
                }
            }
            .sheet(isPresented: $showingSDK) {
                SDKInfoView(status: status)
            }
            .sheet(item: $editing) { model in
                EditDeviceView(model: model)
            }
            .sheet(item: $newDevice) { model in
                NewDeviceView(model: model) {
                    await sdk.refresh()
                    await devices.refresh()
                }
            }
            .alert(
                "Rename Emulator",
                isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
            ) {
                TextField("Name", text: $newName)
                Button("Rename") {
                    if let renaming { devices.rename(renaming, to: newName) }
                    renaming = nil
                }
                .disabled(AVDSettings.cleanName(newName).isEmpty)
                Button("Cancel", role: .cancel) { renaming = nil }
            } message: {
                Text("The emulator ID \(renaming?.id ?? "") stays the same.")
            }
            .confirmationDialog(
                deletionTitle,
                isPresented: Binding(get: { !pendingDeletion.isEmpty }, set: { if !$0 { pendingDeletion = [] } })
            ) {
                Button("Delete", role: .destructive) {
                    devices.delete(pendingDeletion)
                    selection.subtract(pendingDeletion.map(\.id))
                    pendingDeletion = []
                }
                Button("Cancel", role: .cancel) { pendingDeletion = [] }
            } message: {
                Text(deletionMessage)
            }
            .alert(
                "Emulator error",
                isPresented: Binding(get: { devices.errorMessage != nil }, set: { if !$0 { devices.errorMessage = nil } })
            ) {
                Button("Show Logs") { NSWorkspace.shared.open(EmulatorTools.logsDirectory) }
                Button("OK", role: .cancel) {}
            } message: {
                Text(devices.errorMessage ?? "")
            }
        }
    }
}

extension DevicesView {
    private func edit(_ avd: AVD) {
        editing = EditDeviceModel(avd: avd)
        if editing == nil {
            devices.errorMessage = "Couldn't read the settings of \(avd.displayName)."
        }
    }

    private func showNewDevice() {
        newDevice = NewDeviceModel(status: status, existingNames: Set(devices.devices.map(\.id)))
    }

    /// Selected emulators that can be deleted now (running ones must be stopped first).
    private func deletable(_ ids: Set<String>) -> [AVD] {
        devices.devices.filter { ids.contains($0.id) && devices.state(of: $0) == .stopped }
    }

    private func requestDeletion(of ids: Set<String>) {
        pendingDeletion = deletable(ids)
    }

    private var deletionTitle: String {
        pendingDeletion.count == 1
            ? "Delete \(pendingDeletion[0].displayName)?"
            : "Delete \(pendingDeletion.count) emulators?"
    }

    private var deletionMessage: String {
        let names = pendingDeletion.map(\.displayName).formatted(.list(type: .and))
        var message = "\(names) will be permanently deleted, including their installed apps and data. This can't be undone."
        let skipped = devices.devices.filter { selection.contains($0.id) && devices.state(of: $0) != .stopped }
        if !skipped.isEmpty {
            message += "\n\nRunning emulators are skipped: \(skipped.map(\.displayName).formatted(.list(type: .and)))."
        }
        return message
    }

    @ViewBuilder
    private func contextMenu(for avds: [AVD]) -> some View {
        if avds.count == 1, let avd = avds.first {
            let state = devices.state(of: avd)
            Button("Launch") { devices.launch(avd) }
                .disabled(state != .stopped)
            Button("Cold Boot") { devices.launch(avd, coldBoot: true) }
                .disabled(state != .stopped)
            Button("Stop") { devices.stop(avd) }
                .disabled(devices.running[avd.id] == nil)
            Divider()
            Button("Rename…") {
                newName = avd.displayName
                renaming = avd
            }
            Button("Edit…") { edit(avd) }
                .disabled(state != .stopped)
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([avd.directory]) }
            Divider()
        }
        if !avds.isEmpty {
            Button(avds.count == 1 ? "Delete…" : "Delete \(avds.count) Emulators…", role: .destructive) {
                requestDeletion(of: Set(avds.map(\.id)))
            }
            .disabled(deletable(Set(avds.map(\.id))).isEmpty)
        }
    }
}

private struct DeviceRow: View {
    let avd: AVD
    let onEdit: () -> Void
    @Environment(DevicesModel.self) private var devices

    var body: some View {
        let state = devices.state(of: avd)
        HStack(spacing: 14) {
            Image(systemName: avd.symbolName)
                .font(.title)
                .foregroundStyle(.tint)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(avd.displayName)
                    .font(.headline)
                Text(avd.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            StatusBadge(state: state)

            Button("Edit", systemImage: "slider.horizontal.3", action: onEdit)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(state != .stopped)
                .help(state == .stopped ? "Edit RAM, storage, display and more" : "Stop the emulator to edit it")

            Group {
                switch state {
                case .stopped:
                    Button("Launch", systemImage: "play.fill") { devices.launch(avd) }
                case .starting, .running:
                    Button("Stop", systemImage: "stop.fill") { devices.stop(avd) }
                        .disabled(devices.running[avd.id] == nil)
                case .stopping, .deleting:
                    Button("Stop", systemImage: "stop.fill") {}
                        .disabled(true)
                }
            }
            .frame(width: 96)
        }
        .padding(.vertical, 8)
    }
}

private struct StatusBadge: View {
    let state: DevicesModel.DeviceState

    var body: some View {
        HStack(spacing: 6) {
            if state.isBusy {
                ProgressView().controlSize(.mini)
            } else {
                Circle()
                    .fill(state == .running ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 8, height: 8)
            }
            Text(state.title)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(width: 96, alignment: .leading)
    }
}
