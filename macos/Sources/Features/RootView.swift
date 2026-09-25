import SwiftUI

struct RootView: View {
    @Environment(SDKStatusModel.self) private var sdk
    @Environment(DevicesModel.self) private var devices
    @Environment(UpdatesModel.self) private var updates

    var body: some View {
        Group {
            if let status = sdk.status {
                if status.isReady {
                    DevicesView(status: status)
                } else {
                    SetupView(status: status)
                        .padding(32)
                        .frame(minHeight: 560)
                }
            } else {
                ProgressView("Looking for the Android SDK…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: sdk.status, initial: true) { _, status in
            devices.configure(with: status)
            if let status { updates.checkIfDue(status: status) }
        }
        .task { devices.startPolling() }
    }
}
