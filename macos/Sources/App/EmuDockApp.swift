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
                .frame(minWidth: 720, minHeight: 360)
                .task { await sdk.refresh() }
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About EmuDock") { About.show() }
            }
            // Replaces the default "EmuDock Help" item, which has no help book to open.
            CommandGroup(replacing: .help) {
                Button("EmuDock on GitHub") { About.openRepository() }
                Button("Report an Issue…") { About.openIssues() }
            }
        }

        MenuBarExtra("EmuDock", systemImage: "iphone.gen3") {
            MenuBarView()
                .environment(sdk)
                .environment(devices)
        }
    }
}
