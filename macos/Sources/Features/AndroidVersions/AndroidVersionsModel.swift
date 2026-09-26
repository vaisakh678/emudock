import Foundation
import Observation

/// Installed Android versions (system images): their size on disk, and removing unused ones.
@MainActor
@Observable
final class AndroidVersionsModel {
    private(set) var sizes: [String: Int64] = [:]
    private(set) var removing: String?
    var errorMessage: String?

    var totalSize: Int64 { sizes.values.reduce(0, +) }

    /// Measures every installed image folder off the main thread.
    func loadSizes(status: AndroidSDK.Status) async {
        guard let root = status.root else { return }
        let paths = status.systemImages
        sizes = await Task.detached {
            Dictionary(uniqueKeysWithValues: paths.map { ($0, AndroidSDK.size(of: AndroidSDK.directory(ofPackage: $0, in: root))) })
        }.value
    }

    func remove(_ path: String, sdk: SDKStatusModel, updates: UpdatesModel) async {
        guard removing == nil, let status = sdk.status, let manager = SDKManager(status: status) else { return }
        removing = path
        errorMessage = nil
        do {
            try await manager.uninstall([path])
            sizes[path] = nil
            updates.forget(path)
        } catch {
            errorMessage = error.localizedDescription
        }
        await sdk.refresh()
        removing = nil
    }

    /// Why `path` can't be removed right now, or nil if it can.
    static func removalBlocker(for path: String, installed: [String], avds: [AVD]) -> String? {
        let users = avds.filter { $0.systemImage == path }
        if !users.isEmpty {
            return "Used by \(users.map(\.displayName).formatted(.list(type: .and))). Delete those emulators first."
        }
        if installed.count <= 1 {
            return "EmuDock needs at least one Android version to create emulators."
        }
        return nil
    }
}
