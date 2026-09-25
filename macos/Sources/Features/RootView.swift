import SwiftUI

struct RootView: View {
    @Environment(SDKStatusModel.self) private var sdk
    @Environment(DevicesModel.self) private var devices

    var body: some View {
        Group {
            if let status = sdk.status {
                if status.isReady {
                    DevicesView(status: status)
                } else {
                    SetupView(status: status)
                        .padding(32)
                }
            } else {
                ProgressView("Looking for the Android SDK…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: sdk.status, initial: true) { _, status in
            devices.configure(with: status)
        }
        .task { devices.startPolling() }
    }
}
