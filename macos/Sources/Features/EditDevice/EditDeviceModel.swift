import Foundation
import Observation

/// State for the Edit Device sheet: the AVD's settings as loaded, and the user's edits.
@MainActor
@Observable
final class EditDeviceModel: Identifiable {
    let avd: AVD
    let original: AVDSettings
    var settings: AVDSettings
    var customResolution: Bool
    /// The emulator only builds its data disk at the configured size when the disk is
    /// created, so a storage change applies only if the existing data is erased.
    var eraseData = false
    private(set) var errorMessage: String?

    static let resolutionPresets: [(name: String, resolution: AVDSettings.Resolution)] = [
        ("HD", .init(width: 720, height: 1280, density: 320)),
        ("Full HD", .init(width: 1080, height: 1920, density: 420)),
        ("Full HD+", .init(width: 1080, height: 2400, density: 420)),
        ("Pixel 9 / 10", .init(width: 1080, height: 2424, density: 420)),
        ("QHD+", .init(width: 1344, height: 2992, density: 480)),
        ("QHD+ tall", .init(width: 1440, height: 3120, density: 560)),
        ("Tablet", .init(width: 2560, height: 1600, density: 320)),
    ]

    private var configURL: URL { avd.directory.appending(path: "config.ini") }

    init?(avd: AVD) {
        guard let text = try? String(contentsOf: avd.directory.appending(path: "config.ini"), encoding: .utf8) else {
            return nil
        }
        var settings = AVDSettings(config: AVDCatalog.parseINI(text))
        if settings.name.isEmpty { settings.name = avd.displayName }
        self.avd = avd
        original = settings
        self.settings = settings
        customResolution = false
    }

    var hasChanges: Bool { settings != original }

    var storageChanged: Bool { settings.storageMB != original.storageMB }

    var canSave: Bool {
        hasChanges && !AVDSettings.cleanName(settings.name).isEmpty && settings.resolution.isValid
            && (!storageChanged || eraseData)
    }

    /// Choices that always include the current value, even if it's outside the usual list.
    var ramOptions: [Int] { Set(HostResources.ramOptions + [original.ramMB]).sorted() }
    var coreOptions: [Int] { Set(HostResources.coreOptions + [original.cpuCores]).sorted() }

    var storageOptions: [Int] {
        Set([2048, 4096, 6144, 8192, 16384, 32768, 65536] + [original.storageMB]).sorted()
    }

    var resolutionOptions: [(name: String, resolution: AVDSettings.Resolution)] {
        let presets = Self.resolutionPresets
        guard !presets.contains(where: { $0.resolution == original.resolution }) else { return presets }
        return [("Current", original.resolution)] + presets
    }

    var switchesSkin: Bool { settings.resolution != original.resolution }

    func applyRecommended() {
        settings.ramMB = HostResources.recommendedRAM
        settings.cpuCores = HostResources.recommendedCores
    }

    /// Writes the changed keys to `config.ini`, keeping a copy of the previous file next to it.
    func save() -> Bool {
        do {
            let backup = avd.directory.appending(path: "config.ini.emudock-backup")
            try? FileManager.default.removeItem(at: backup)
            try FileManager.default.copyItem(at: configURL, to: backup)
            try AVDManager.updateConfig(at: configURL, with: settings.changes(from: original))
            if storageChanged {
                try Self.eraseData(in: avd.directory)
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Removes the data disk and saved snapshots; the emulator recreates a fresh data
    /// disk at the configured size on its next start, like `emulator -wipe-data`.
    static func eraseData(in directory: URL) throws {
        for name in ["userdata-qemu.img", "userdata-qemu.img.qcow2", "snapshots"] {
            let url = directory.appending(path: name)
            if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }
}
