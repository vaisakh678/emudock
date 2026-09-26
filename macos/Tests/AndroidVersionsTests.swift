import Foundation
import Testing
@testable import EmuDock

@MainActor
struct AndroidVersionsTests {
    private let api36 = "system-images;android-36;google_apis_playstore;arm64-v8a"
    private let api34 = "system-images;android-34;google_apis;arm64-v8a"

    private func avd(_ name: String, image: String?) -> AVD {
        AVD(
            id: name, displayName: name, directory: URL(filePath: "/tmp/\(name).avd"),
            apiLevel: nil, tagDisplay: nil, deviceName: nil, screenSize: nil, systemImage: image
        )
    }

    @Test func versionInUseCantBeRemoved() throws {
        let blocker = try #require(AndroidVersionsModel.removalBlocker(
            for: api36, installed: [api34, api36], avds: [avd("Pixel 9", image: api36), avd("Tablet", image: api36)]
        ))
        #expect(blocker.contains("Pixel 9 and Tablet"))
    }

    @Test func unusedVersionCanBeRemoved() {
        #expect(AndroidVersionsModel.removalBlocker(for: api34, installed: [api34, api36], avds: [avd("Pixel 9", image: api36)]) == nil)
    }

    @Test func lastVersionIsKept() {
        #expect(AndroidVersionsModel.removalBlocker(for: api36, installed: [api36], avds: []) != nil)
    }
}
