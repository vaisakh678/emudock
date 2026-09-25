import Foundation

/// Locates an existing Android SDK and the command-line tools EmuDock drives.
enum AndroidSDK {
    struct Status: Sendable, Equatable {
        var root: URL?
        var javaHome: URL?
        var sdkmanager: URL?
        var avdmanager: URL?
        var emulator: URL?
        var adb: URL?
        /// Installed system image package paths, e.g. `system-images;android-36;google_apis_playstore;arm64-v8a`.
        var systemImages: [String] = []

        var isReady: Bool {
            javaHome != nil && sdkmanager != nil && avdmanager != nil && emulator != nil && adb != nil
                && !systemImages.isEmpty
        }
    }

    /// Android Studio's default SDK location, also where EmuDock installs a new SDK.
    static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Android/sdk", directoryHint: .isDirectory)
    }

    static func sdkmanager(in root: URL) -> URL {
        root.appending(path: "cmdline-tools/latest/bin/sdkmanager")
    }

    /// Candidate SDK roots, most specific first: env vars, then Android Studio's default.
    static func candidateRoots(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        var roots: [URL] = []
        for key in ["ANDROID_HOME", "ANDROID_SDK_ROOT"] {
            if let path = environment[key], !path.isEmpty {
                roots.append(URL(filePath: path, directoryHint: .isDirectory))
            }
        }
        roots.append(home.appending(path: "Library/Android/sdk", directoryHint: .isDirectory))
        return roots
    }

    static func detect(
        roots: [URL] = candidateRoots(),
        javaHome: URL? = JavaRuntime.detect(),
        fileManager: FileManager = .default
    ) -> Status {
        guard let root = roots.first(where: { fileManager.fileExists(atPath: $0.path(percentEncoded: false)) }) else {
            return Status(javaHome: javaHome)
        }

        func tool(_ url: URL) -> URL? {
            fileManager.isExecutableFile(atPath: url.path(percentEncoded: false)) ? url : nil
        }

        return Status(
            root: root,
            javaHome: javaHome,
            sdkmanager: tool(sdkmanager(in: root)),
            avdmanager: tool(root.appending(path: "cmdline-tools/latest/bin/avdmanager")),
            emulator: tool(root.appending(path: "emulator/emulator")),
            adb: tool(root.appending(path: "platform-tools/adb")),
            systemImages: installedSystemImages(in: root, fileManager: fileManager)
        )
    }

    /// System images live at `system-images/<api>/<tag>/<abi>/`, each with a `package.xml`.
    static func installedSystemImages(in root: URL, fileManager: FileManager = .default) -> [String] {
        let base = root.appending(path: "system-images", directoryHint: .isDirectory)
        func children(_ url: URL) -> [String] {
            ((try? fileManager.contentsOfDirectory(atPath: url.path(percentEncoded: false))) ?? [])
                .filter { !$0.hasPrefix(".") }
                .sorted()
        }
        var images: [String] = []
        for api in children(base) {
            for tag in children(base.appending(path: api)) {
                for abi in children(base.appending(path: api).appending(path: tag)) {
                    let manifest = base.appending(path: "\(api)/\(tag)/\(abi)/package.xml")
                    if fileManager.fileExists(atPath: manifest.path(percentEncoded: false)) {
                        images.append("system-images;\(api);\(tag);\(abi)")
                    }
                }
            }
        }
        return images
    }
}
