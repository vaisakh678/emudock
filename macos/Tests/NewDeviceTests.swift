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
