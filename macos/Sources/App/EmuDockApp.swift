import SwiftUI

@main
struct EmuDockApp: App {
    static let mainWindowID = "main"

    @State private var sdk = SDKStatusModel()
    @State private var devices = DevicesModel()
    @State private var updates = UpdatesModel()

    var body: some Scene {
        Window("EmuDock", id: Self.mainWindowID) {
            RootView()
                .environment(sdk)
                .environment(devices)
                .environment(updates)
                .frame(minWidth: 720, minHeight: 560)
                .task { await sdk.refresh() }
        }

        MenuBarExtra("EmuDock", systemImage: "iphone.gen3") {
            MenuBarView()
                .environment(sdk)
                .environment(devices)
        }
    }
}
