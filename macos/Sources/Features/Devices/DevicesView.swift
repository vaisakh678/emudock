import SwiftUI

struct DevicesView: View {
    let status: AndroidSDK.Status
    @Environment(DevicesModel.self) private var devices
    @Environment(SDKStatusModel.self) private var sdk
    @State private var showingSDK = false
    @State private var newDevice: NewDeviceModel?

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
                    List(devices.devices) { avd in
                        DeviceRow(avd: avd)
                    }
                    .listStyle(.inset)
                }
            }
            .navigationTitle("Devices")
            .toolbar {
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
            .sheet(item: $newDevice) { model in
                NewDeviceView(model: model) {
                    await sdk.refresh()
                    await devices.refresh()
                }
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
    private func showNewDevice() {
        newDevice = NewDeviceModel(status: status, existingNames: Set(devices.devices.map(\.id)))
    }
}

private struct DeviceRow: View {
    let avd: AVD
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

            Group {
                switch state {
                case .stopped:
                    Button("Launch", systemImage: "play.fill") { devices.launch(avd) }
                case .starting, .running:
                    Button("Stop", systemImage: "stop.fill") { devices.stop(avd) }
                        .disabled(devices.running[avd.id] == nil)
                case .stopping:
                    Button("Stop", systemImage: "stop.fill") {}
                        .disabled(true)
                }
            }
            .frame(width: 96)
        }
        .padding(.vertical, 8)
        .contextMenu {
            Button("Launch") { devices.launch(avd) }
                .disabled(state != .stopped)
            Button("Cold Boot") { devices.launch(avd, coldBoot: true) }
                .disabled(state != .stopped)
            Button("Stop") { devices.stop(avd) }
                .disabled(devices.running[avd.id] == nil)
            Divider()
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([avd.directory]) }
        }
    }
}

private struct StatusBadge: View {
    let state: DevicesModel.DeviceState

    var body: some View {
        HStack(spacing: 6) {
            if state == .starting || state == .stopping {
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
