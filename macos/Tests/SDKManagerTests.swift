import Foundation
import Testing
@testable import EmuDock

struct SDKManagerTests {
    @Test func parsesProgressLines() throws {
        let parsed = try #require(SDKManager.parseProgress("[=========                              ] 25% Downloading foo.zip..."))
        #expect(parsed.fraction == 0.25)
        #expect(parsed.message == "Downloading foo.zip")
        #expect(SDKManager.parseProgress("Installed packages:") == nil)
    }

    @Test func extractsPackagePathsFromList() {
        let lines = [
            "Installed packages:",
            "Path                 | Version | Description",
            "-------              | ------- | -------",
            "emulator             | 36.5.10 | Android Emulator",
            "Available Packages:",
            "system-images;android-36;google_apis_playstore;arm64-v8a | 7 | Google Play ARM 64 v8a System Image",
        ]
        #expect(SDKManager.packagePaths(inList: lines) == [
            "emulator",
            "system-images;android-36;google_apis_playstore;arm64-v8a",
        ])
    }

    @Test func recommendsNewestPlayImageForABI() {
        let paths = [
            "system-images;android-35;google_apis_playstore;arm64-v8a",
            "system-images;android-36.1;google_apis_playstore;arm64-v8a",
            "system-images;android-36;google_apis_playstore;arm64-v8a",
            "system-images;android-37.0;google_apis_playstore;x86_64",
            "system-images;android-37.0;google_apis;arm64-v8a",
            "system-images;android-CinnamonBun;google_apis_playstore;arm64-v8a",
        ]
        #expect(SDKManager.recommendedSystemImage(in: paths, abi: "arm64-v8a")
            == "system-images;android-36.1;google_apis_playstore;arm64-v8a")
        #expect(SDKManager.recommendedSystemImage(in: paths, abi: "x86_64")
            == "system-images;android-37.0;google_apis_playstore;x86_64")
        #expect(SDKManager.recommendedSystemImage(in: [], abi: "arm64-v8a") == nil)
    }
}

struct SDKUpdatesTests {
    @Test func parsesAvailableUpdatesSection() {
        let lines = [
            "Available Packages:",
            "system-images;android-36;google_apis;arm64-v8a | 7 | Google APIs ARM 64 v8a System Image",
            "Available Updates:",
            "ID | Installed | Available",
            "------- | ------- | -------",
            "emulator | 36.5.10 | 37.1.11",
            "platform-tools | 37.0.0 | 37.0.1",
        ]
        #expect(SDKManager.updates(inList: lines) == [
            PackageUpdate(path: "emulator", installed: "36.5.10", available: "37.1.11"),
            PackageUpdate(path: "platform-tools", installed: "37.0.0", available: "37.0.1"),
        ])
        #expect(SDKManager.updates(inList: ["Installed packages:"]).isEmpty)
        #expect(!SDKManager.packagePaths(inList: lines).contains("ID"))
    }

    @Test func comparesVersionsNumerically() {
        #expect(PackageUpdate.isNewer("23.0", than: "12.0"))
        #expect(PackageUpdate.isNewer("37.1.11", than: "36.5.10"))
        #expect(PackageUpdate.isNewer("37.0.1", than: "37.0"))
        #expect(!PackageUpdate.isNewer("23.0", than: "23.0"))
        #expect(!PackageUpdate.isNewer("9.0", than: "12.0"))
    }

    @Test func namesEssentialPackages() {
        let tools = PackageUpdate(path: "cmdline-tools;latest", installed: "12.0", available: "23.0")
        let image = PackageUpdate(path: "system-images;android-36;google_apis_playstore;arm64-v8a", installed: "4", available: "7")
        #expect(tools.isEssential && tools.displayName == "Command-line tools")
        #expect(!image.isEssential && image.displayName == "Android 16 (API 36) · Google Play")
    }
}

struct CommandLineToolsTests {
    private let manifest = Data("""
    <sdk:sdk-repository xmlns:sdk="http://schemas.android.com/sdk/android/repo/repository2/03">
      <remotePackage path="cmdline-tools;latest">
        <revision><major>23</major><minor>0</minor></revision>
        <archives>
          <archive>
            <complete><checksum type="sha1">aaa</checksum><url>commandlinetools-linux-1_latest.zip</url></complete>
            <host-os>linux</host-os>
          </archive>
          <archive>
            <complete><checksum type="sha1">bbb</checksum><url>commandlinetools-mac_x86_64-1_latest.zip</url></complete>
            <host-os>macosx</host-os><host-arch>x64</host-arch>
          </archive>
          <archive>
            <complete><checksum type="sha1">ccc</checksum><url>commandlinetools-mac_arm64-1_latest.zip</url></complete>
            <host-os>macosx</host-os><host-arch>aarch64</host-arch>
          </archive>
        </archives>
      </remotePackage>
    </sdk:sdk-repository>
    """.utf8)

    @Test func picksMacArchiveForArchitecture() throws {
        let arm = try #require(try CommandLineTools.latestArchive(inRepository: manifest, arch: "aarch64"))
        #expect(arm.url.absoluteString == "https://dl.google.com/android/repository/commandlinetools-mac_arm64-1_latest.zip")
        #expect(arm.sha1 == "ccc")
        #expect(arm.version == "23.0")
        #expect(try CommandLineTools.latestArchive(inRepository: manifest, arch: "x64")?.sha1 == "bbb")
    }
}

struct ProcessRunnerTests {
    @Test func splitsOutputOnCarriageReturnsAndFeedsInput() async throws {
        let lines = try await ProcessRunner.run(
            URL(filePath: "/bin/sh"),
            arguments: ["-c", "printf '10%%\\r50%%\\r100%%\\n'; read answer; echo got $answer"],
            input: "y\n"
        )
        #expect(lines == ["10%", "50%", "100%", "got y"])
    }

    @Test func throwsOnNonZeroExit() async {
        await #expect(throws: ProcessRunner.Failure.self) {
            try await ProcessRunner.run(URL(filePath: "/bin/sh"), arguments: ["-c", "echo boom; exit 3"])
        }
    }
}
