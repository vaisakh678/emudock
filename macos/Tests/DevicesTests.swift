import Foundation
import Testing
@testable import EmuDock

struct AVDCatalogTests {
    @Test func loadsAVDFromPointerAndConfig() throws {
        let home = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: home) }
        let avdDir = home.appending(path: "Medium_Phone.avd", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: avdDir, withIntermediateDirectories: true)
        // The .ini name (the AVD name) can differ from its folder name.
        try """
        avd.ini.encoding=UTF-8
        path=\(avdDir.path(percentEncoded: false))
        target=android-36
        """.write(to: home.appending(path: "Medium_Phone_API_36.0.ini"), atomically: true, encoding: .utf8)
        try """
        avd.ini.displayname=Medium Phone API 36.0
        hw.device.name=medium_phone
        hw.lcd.width=1080
        hw.lcd.height=2400
        tag.display=Google Play
        target=android-36
        """.write(to: avdDir.appending(path: "config.ini"), atomically: true, encoding: .utf8)

        let avds = AVDCatalog.load(from: home)
        let avd = try #require(avds.first)
        #expect(avds.count == 1)
        #expect(avd.id == "Medium_Phone_API_36.0")
        #expect(avd.displayName == "Medium Phone API 36.0")
        #expect(avd.summary == "Android 16 (API 36) · Google Play · 1080 × 2400")
        #expect(avd.symbolName == "smartphone")
    }

    @Test func tagComesFromImageFolder() {
        #expect(AVDCatalog.imageTagDisplay(["image.sysdir.1": "system-images/android-37.0/google_apis_playstore_ps16k/arm64-v8a/"])
            == "Google Play · 16 KB pages")
        #expect(AVDCatalog.imageTagDisplay(["image.sysdir.1": "system-images/android-33/google_apis/arm64-v8a/"])
            == "Google APIs (rootable)")
        #expect(AVDCatalog.imageTagDisplay([:]) == nil)
    }

    @Test func fallsBackWhenConfigIsMissing() throws {
        let home = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: home) }
        try "target=android-37.0\n".write(to: home.appending(path: "rooted_api37.ini"), atomically: true, encoding: .utf8)

        let avd = try #require(AVDCatalog.load(from: home).first)
        #expect(avd.displayName == "rooted api37")
        #expect(avd.summary == "Android 17 (API 37.0)")
    }

    @Test func avdHomeFollowsEnvironment() {
        let home = URL(filePath: "/Users/test", directoryHint: .isDirectory)
        #expect(AVDCatalog.avdHome(environment: [:], home: home).path(percentEncoded: false) == "/Users/test/.android/avd/")
        #expect(AVDCatalog.avdHome(environment: ["ANDROID_USER_HOME": "/x"], home: home).path(percentEncoded: false) == "/x/avd/")
        #expect(AVDCatalog.avdHome(environment: ["ANDROID_AVD_HOME": "/y", "ANDROID_USER_HOME": "/x"], home: home)
            .path(percentEncoded: false) == "/y/")
    }
}

struct EmulatorDiscoveryTests {
    @Test func readsLiveEmulatorsAndIgnoresStaleFiles() throws {
        let dir = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: dir) }
        try "avd.id=Pixel_9\nport.serial=5554\n".write(to: dir.appending(path: "pid_100.ini"), atomically: true, encoding: .utf8)
        try "avd.id=Old\nport.serial=5556\n".write(to: dir.appending(path: "pid_200.ini"), atomically: true, encoding: .utf8)

        let running = EmulatorDiscovery.running(in: dir, isAlive: { $0 == 100 })
        #expect(running == [RunningEmulator(avdID: "Pixel_9", serial: "emulator-5554", pid: 100)])
    }

    @Test func errorSummaryPrefersErrorLines() throws {
        let dir = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = dir.appending(path: "x.log")
        try "INFO | starting\nERROR | Running multiple emulators with the same AVD\nINFO | bye\n"
            .write(to: log, atomically: true, encoding: .utf8)
        #expect(EmulatorTools.errorSummary(fromLog: log) == "ERROR | Running multiple emulators with the same AVD")
    }
}

private func temporaryFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
