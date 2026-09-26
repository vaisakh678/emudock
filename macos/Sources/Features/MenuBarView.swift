import SwiftUI

struct MenuBarView: View {
    @Environment(SDKStatusModel.self) private var sdk
    @Environment(DevicesModel.self) private var devices
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if sdk.status?.isReady == true {
            if devices.devices.isEmpty {
                Text("No emulators yet")
            }
            ForEach(devices.devices) { avd in
                let state = devices.state(of: avd)
                Menu {
                    Button("Launch") { devices.launch(avd) }
                        .disabled(state != .stopped)
                    Button("Cold Boot") { devices.launch(avd, coldBoot: true) }
                        .disabled(state != .stopped)
                    Button("Stop") { devices.stop(avd) }
                        .disabled(devices.running[avd.id] == nil)
                } label: {
                    Text(state == .stopped ? avd.displayName : "\(avd.displayName) — \(state.title)")
                }
            }
        } else {
            Text("Android SDK needs setup")
        }
        Divider()
        Button("Open EmuDock") {
            openWindow(id: EmuDockApp.mainWindowID)
            NSApplication.shared.activate()
        }
        Button("About EmuDock") { About.show() }
        Button("EmuDock on GitHub") { About.openRepository() }
        Divider()
        Button("Quit EmuDock") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
