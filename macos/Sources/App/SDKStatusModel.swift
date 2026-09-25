import Observation

/// App-wide view of the local Android SDK install.
@MainActor
@Observable
final class SDKStatusModel {
    private(set) var status: AndroidSDK.Status?

    func refresh() async {
        status = await Task.detached { AndroidSDK.detect() }.value
    }
}
