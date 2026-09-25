import Foundation
import Testing
@testable import EmuDock

struct SystemImageTests {
    @Test func parsesPackagePath() throws {
        let image = try #require(SystemImage(path: "system-images;android-37.0;google_apis_playstore_ps16k;arm64-v8a", isInstalled: true))
        #expect(image.apiLevel == "37.0")
        #expect(image.title == "Android 17 (API 37.0)")
        #expect(image.tagDisplay == "Google Play · 16 KB pages")
        #expect(image.isGooglePlay)
    }

    @Test func rejectsPreviewsAndOtherPackages() {
        #expect(SystemImage(path: "system-images;android-CinnamonBun;google_apis;arm64-v8a", isInstalled: false) == nil)
        #expect(SystemImage(path: "platforms;android-36", isInstalled: false) == nil)
    }

    @Test func filtersToPhoneImagesForThisMac() throws {
        let abi = Host.systemImageABI
        let phone = try #require(SystemImage(path: "system-images;android-36;google_apis;\(abi)", isInstalled: false))
        let wear = try #require(SystemImage(path: "system-images;android-36;android-wear;\(abi)", isInstalled: false))
        let otherArch = try #require(SystemImage(path: "system-images;android-36;google_apis;mips", isInstalled: false))
        #expect(phone.isPhoneOrTablet)
        #expect(!wear.isPhoneOrTablet)
        #expect(!otherArch.isPhoneOrTablet)
    }

    @Test func sortsNewestFirstThenGooglePlay() {
        let images = [
            "system-images;android-35;google_apis_playstore;arm64-v8a",
            "system-images;android-36;google_apis;arm64-v8a",
            "system-images;android-36.1;google_apis_playstore;arm64-v8a",
            "system-images;android-36;google_apis_playstore;arm64-v8a",
        ].compactMap { SystemImage(path: $0, isInstalled: false) }
        #expect(SystemImage.sorted(images).map(\.path) == [
            "system-images;android-36.1;google_apis_playstore;arm64-v8a",
            "system-images;android-36;google_apis_playstore;arm64-v8a",
            "system-images;android-36;google_apis;arm64-v8a",
            "system-images;android-35;google_apis_playstore;arm64-v8a",
        ])
    }
}

struct AVDManagerTests {
    @Test func makesValidAVDNames() {
        #expect(AVDManager.avdName(for: "Pixel 9 API 36") == "Pixel_9_API_36")
        #expect(AVDManager.avdName(for: "  Test (rooted) 36.1 ") == "Test__rooted__36.1")
        #expect(AVDManager.avdName(for: "   ") == "Device")
    }

    @Test func updatesAndAppendsConfigKeys() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).ini")
        defer { try? FileManager.default.removeItem(at: url) }
        try "avd.ini.displayname=Old\nhw.keyboard=no\nhw.ramSize=2048\n".write(to: url, atomically: true, encoding: .utf8)

        try AVDManager.updateConfig(at: url, with: ["avd.ini.displayname": "Pixel 9", "hw.keyboard": "yes", "hw.gpu.mode": "auto"])
        #expect(try String(contentsOf: url, encoding: .utf8)
            == "avd.ini.displayname=Pixel 9\nhw.keyboard=yes\nhw.ramSize=2048\nhw.gpu.mode=auto\n")
    }
}

struct HardwareProfileTests {
    /// Real `avdmanager list device` output from command-line tools 23, trimmed like ProcessRunner does.
    private func fixture() throws -> [String] {
        let url = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/avdmanager-list-device-v23.txt")
        return try String(contentsOf: url, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    @Test func keepsPhonesAndTabletsOnly() throws {
        let profiles = HardwareProfile.parse(try fixture())
        let ids = Set(profiles.map(\.id))
        #expect(ids.isSuperset(of: ["pixel_10", "pixel_10_pro_fold", "pixel_9a", "pixel_tablet", "medium_phone"]))
        #expect(!ids.contains("wearos_large_round"))
        #expect(!ids.contains("automotive_1024p_landscape"))
        #expect(!ids.contains { $0.hasPrefix("tv_") || $0.hasPrefix("desktop_") })
    }

    @Test func classifiesKinds() throws {
        let profiles = Dictionary(uniqueKeysWithValues: HardwareProfile.parse(try fixture()).map { ($0.id, $0) })
        #expect(profiles["pixel_10"]?.kind == .phone)
        #expect(profiles["pixel_10_pro_fold"]?.kind == .foldable)
        #expect(profiles["pixel_tablet"]?.kind == .tablet)
        #expect(profiles["Nexus 9"]?.kind == .tablet)
    }

    @Test func popularIsTwoNewestPixelGenerationsPlusStaples() throws {
        let grouped = HardwareProfile.grouped(HardwareProfile.parse(try fixture()))
        #expect(grouped.popular.prefix(5).map(\.name) == ["Pixel 10", "Pixel 10 Pro", "Pixel 10 Pro XL", "Pixel 10 Pro Fold", "Pixel 10a"])
        #expect(grouped.popular.contains { $0.id == "pixel_9" })
        #expect(!grouped.popular.contains { $0.id == "pixel_8" })
        #expect(grouped.popular.contains { $0.id == "pixel_tablet" })
        #expect(grouped.popular.contains { $0.id == "medium_phone" })
        #expect(grouped.others.first?.name == "Pixel 8")
        #expect(Set(grouped.popular.map(\.id)).isDisjoint(with: grouped.others.map(\.id)))
    }
}

@MainActor
struct NewDeviceModelTests {
    private func status() -> AndroidSDK.Status {
        AndroidSDK.Status(
            root: URL(filePath: "/sdk"), javaHome: URL(filePath: "/java"),
            sdkmanager: URL(filePath: "/sdk/sdkmanager"), avdmanager: URL(filePath: "/sdk/avdmanager"),
            emulator: URL(filePath: "/sdk/emulator"), adb: URL(filePath: "/sdk/adb"),
            systemImages: ["system-images;android-36;google_apis_playstore;\(Host.systemImageABI)"]
        )
    }

    @Test func canCreateOnceHardwareAndImageAreChosen() throws {
        let model = try #require(NewDeviceModel(status: status(), existingNames: []))
        #expect(model.image != nil)
        model.hardware = HardwareProfile(id: "pixel_10", name: "Pixel 10", oem: "Google")
        #expect(model.name == "Pixel 10 API 36")
        #expect(model.canCreate)
    }
}
