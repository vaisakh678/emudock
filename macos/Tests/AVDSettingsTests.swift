import Foundation
import Testing
@testable import EmuDock

struct AVDSettingsTests {
    @Test func parsesEverySizeFormatSeenInTheWild() {
        #expect(AVDSettings.megabytes("2048") == 2048)
        #expect(AVDSettings.megabytes("2G") == 2048)
        #expect(AVDSettings.megabytes("1536M") == 1536)
        #expect(AVDSettings.megabytes("16G") == 16384)
        #expect(AVDSettings.megabytes("512 MB") == 512)
        #expect(AVDSettings.megabytes("6442450944") == 6144)
        #expect(AVDSettings.megabytes("lots") == nil)
    }

    @Test func formatsSizes() {
        #expect(AVDSettings.sizeString(4096) == "4G")
        #expect(AVDSettings.sizeString(1536) == "1536M")
        #expect(AVDSettings.sizeTitle(1536) == "1.5 GB")
    }

    @Test func readsConfig() {
        let settings = AVDSettings(config: [
            "hw.ramSize": "1536M", "hw.cpu.ncore": "4", "disk.dataPartition.size": "6442450944",
            "hw.lcd.width": "1344", "hw.lcd.height": "2992", "hw.lcd.density": "480",
            "hw.keyboard": "yes", "hw.camera.back": "virtualscene", "hw.camera.front": "none",
            "fastboot.forceColdBoot": "no", "showDeviceFrame": "yes", "hw.initialOrientation": "portrait",
        ])
        #expect(settings.ramMB == 1536)
        #expect(settings.cpuCores == 4)
        #expect(settings.storageMB == 6144)
        #expect(settings.resolution == .init(width: 1344, height: 2992, density: 480))
        #expect(settings.hostKeyboard)
        #expect(settings.backCamera == .virtualscene)
        #expect(settings.frontCamera == AVDSettings.Camera.none)
        #expect(!settings.alwaysColdBoot)
        #expect(settings.deviceFrame)
    }

    @Test func writesOnlyChangedKeys() {
        let original = AVDSettings(config: ["hw.ramSize": "2048", "hw.cpu.ncore": "1", "disk.dataPartition.size": "16G"])
        var edited = original
        #expect(edited.changes(from: original).isEmpty)

        edited.ramMB = 4096
        edited.cpuCores = 4
        edited.storageMB = 32768
        #expect(edited.changes(from: original) == [
            "hw.ramSize": "4096",
            "hw.cpu.ncore": "4",
            "disk.dataPartition.size": "32G",
        ])
    }

    @Test func renamesDisplayNameOnly() {
        let original = AVDSettings(config: ["avd.ini.displayname": "Medium Phone API 36.0"])
        var edited = original
        edited.name = "  Work phone\n  "
        #expect(edited.changes(from: original) == ["avd.ini.displayname": "Work phone"])
        edited.name = "   "
        #expect(edited.changes(from: original).isEmpty)
    }

    @Test func newResolutionSwitchesToPlainSkin() {
        let original = AVDSettings(config: ["hw.lcd.width": "1344", "hw.lcd.height": "2992", "hw.lcd.density": "480"])
        var edited = original
        edited.resolution = .init(width: 1080, height: 2400, density: 420)
        let changes = edited.changes(from: original)
        #expect(changes["hw.lcd.width"] == "1080")
        #expect(changes["hw.lcd.density"] == "420")
        #expect(changes["skin.name"] == "1080x2400")
        #expect(changes["skin.path"] == "1080x2400")
    }

    @Test func validatesResolution() {
        #expect(AVDSettings.Resolution(width: 1080, height: 2400, density: 420).isValid)
        #expect(!AVDSettings.Resolution(width: 10, height: 2400, density: 420).isValid)
        #expect(!AVDSettings.Resolution(width: 1080, height: 2400, density: 900).isValid)
    }

    @Test func hostOptionsStayWithinThisMac() {
        #expect(HostResources.ramOptions.allSatisfy { $0 <= HostResources.memoryMB / 2 })
        #expect(HostResources.coreOptions.max()! <= HostResources.cores)
        #expect(HostResources.recommendedCores <= HostResources.cores)
    }
}

@MainActor
struct EditDeviceModelTests {
    @Test func storageChangeNeedsEraseAndRemovesDataDisk() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).avd", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir.appending(path: "snapshots/default_boot"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "disk.dataPartition.size=10G\nhw.ramSize=2048\n".write(to: dir.appending(path: "config.ini"), atomically: true, encoding: .utf8)
        for file in ["userdata-qemu.img", "userdata-qemu.img.qcow2", "encryptionkey.img"] {
            FileManager.default.createFile(atPath: dir.appending(path: file).path(percentEncoded: false), contents: Data())
        }
        let avd = AVD(id: "Test", displayName: "Test", directory: dir, apiLevel: "36", tagDisplay: nil, deviceName: nil, screenSize: nil)
        let model = try #require(EditDeviceModel(avd: avd))

        model.settings.storageMB = 16384
        #expect(!model.canSave)
        model.eraseData = true
        #expect(model.canSave)
        #expect(model.save())

        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path(percentEncoded: false))
        #expect(!files.contains("userdata-qemu.img"))
        #expect(!files.contains("userdata-qemu.img.qcow2"))
        #expect(!files.contains("snapshots"))
        #expect(files.contains("encryptionkey.img"))
        #expect(files.contains("config.ini.emudock-backup"))
        #expect(try String(contentsOf: dir.appending(path: "config.ini"), encoding: .utf8).contains("disk.dataPartition.size=16G"))
    }

    @Test func otherEditsKeepData() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).avd", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "disk.dataPartition.size=10G\nhw.ramSize=2048\n".write(to: dir.appending(path: "config.ini"), atomically: true, encoding: .utf8)
        FileManager.default.createFile(atPath: dir.appending(path: "userdata-qemu.img").path(percentEncoded: false), contents: Data())
        let avd = AVD(id: "Test", displayName: "Test", directory: dir, apiLevel: "36", tagDisplay: nil, deviceName: nil, screenSize: nil)
        let model = try #require(EditDeviceModel(avd: avd))

        model.settings.ramMB = 4096
        #expect(model.save())
        #expect(FileManager.default.fileExists(atPath: dir.appending(path: "userdata-qemu.img").path(percentEncoded: false)))
    }
}
