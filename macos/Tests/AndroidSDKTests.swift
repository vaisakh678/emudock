import Foundation
import Testing
@testable import EmuDock

struct AndroidSDKTests {
    private let javaHome = URL(filePath: "/opt/java", directoryHint: .isDirectory)

    @Test func envVarsComeBeforeDefaultLocation() {
        let roots = AndroidSDK.candidateRoots(
            environment: ["ANDROID_HOME": "/opt/android"],
            home: URL(filePath: "/Users/test", directoryHint: .isDirectory)
        )
        #expect(roots.map { $0.path(percentEncoded: false) } == [
            "/opt/android/",
            "/Users/test/Library/Android/sdk/",
        ])
    }

    @Test func missingRootReportsNotReady() {
        let status = AndroidSDK.detect(roots: [URL(filePath: "/nonexistent/sdk")], javaHome: javaHome)
        #expect(status.root == nil)
        #expect(status.javaHome == javaHome)
        #expect(!status.isReady)
    }

    @Test func readyNeedsToolsJavaAndASystemImage() throws {
        let root = try makeSDK(files: [
            "cmdline-tools/latest/bin/sdkmanager", "cmdline-tools/latest/bin/avdmanager",
            "emulator/emulator", "platform-tools/adb",
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(!AndroidSDK.detect(roots: [root], javaHome: javaHome).isReady)

        try write(root.appending(path: "system-images/android-36/google_apis_playstore/arm64-v8a/package.xml"))
        let status = AndroidSDK.detect(roots: [root], javaHome: javaHome)
        #expect(status.systemImages == ["system-images;android-36;google_apis_playstore;arm64-v8a"])
        #expect(status.isReady)
        #expect(!AndroidSDK.detect(roots: [root], javaHome: nil).isReady)
    }

    @Test func imageFolderWithoutManifestIsIgnored() throws {
        let root = try makeSDK(files: [])
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appending(path: "system-images/android-35/google_apis/arm64-v8a"),
            withIntermediateDirectories: true
        )
        #expect(AndroidSDK.installedSystemImages(in: root).isEmpty)
    }

    @Test func measuresPackageFolder() throws {
        let root = try makeSDK(files: [])
        defer { try? FileManager.default.removeItem(at: root) }
        let package = "system-images;android-36;google_apis;arm64-v8a"
        let folder = AndroidSDK.directory(ofPackage: package, in: root)
        #expect(folder.path(percentEncoded: false) == root.path(percentEncoded: false) + "system-images/android-36/google_apis/arm64-v8a/")

        try FileManager.default.createDirectory(at: folder.appending(path: "data"), withIntermediateDirectories: true)
        try Data(count: 100_000).write(to: folder.appending(path: "system.img"))
        try Data(count: 50_000).write(to: folder.appending(path: "data/userdata.img"))
        #expect(AndroidSDK.size(of: folder) >= 150_000)
        #expect(AndroidSDK.size(of: root.appending(path: "missing")) == 0)
    }

    private func makeSDK(files: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for file in files {
            try write(root.appending(path: file), executable: true)
        }
        return root
    }

    private func write(_ url: URL, executable: Bool = false) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: url.path(percentEncoded: false),
            contents: Data(),
            attributes: [.posixPermissions: executable ? 0o755 : 0o644]
        )
    }
}
