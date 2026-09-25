import CryptoKit
import Foundation

/// Finds a Java 17+ runtime for `sdkmanager`/`avdmanager`, or installs Temurin 21.
enum JavaRuntime {
    /// Where EmuDock keeps the Temurin JRE it downloads (a `.jre` bundle layout).
    static var managedBundle: URL {
        URL.applicationSupportDirectory.appending(path: "EmuDock/jre", directoryHint: .isDirectory)
    }

    static var managedHome: URL {
        managedBundle.appending(path: "Contents/Home", directoryHint: .isDirectory)
    }

    /// Returns a Java home, preferring runtimes known to be recent enough.
    static func detect(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        var candidates = [managedHome]
        for studio in ["/Applications/Android Studio.app", "~/Applications/Android Studio.app"] {
            let path = (studio as NSString).expandingTildeInPath
            candidates.append(URL(filePath: path).appending(path: "Contents/jbr/Contents/Home", directoryHint: .isDirectory))
        }
        if let javaHome = environment["JAVA_HOME"], !javaHome.isEmpty {
            candidates.append(URL(filePath: javaHome, directoryHint: .isDirectory))
        }
        if let found = candidates.first(where: { hasJava($0, fileManager: fileManager) }) {
            return found
        }
        return systemJavaHome()
    }

    private static func hasJava(_ home: URL, fileManager: FileManager) -> Bool {
        fileManager.isExecutableFile(atPath: home.appending(path: "bin/java").path(percentEncoded: false))
    }

    /// Asks macOS for an installed JDK of version 17 or newer.
    private static func systemJavaHome() -> URL? {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/libexec/java_home")
        process.arguments = ["-v", "17+"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : URL(filePath: path, directoryHint: .isDirectory)
    }

    // MARK: - Install

    struct Release: Decodable {
        struct Binary: Decodable {
            struct Package: Decodable {
                let name: String
                let link: URL
                let checksum: String
            }
            let package: Package
        }
        let binary: Binary
    }

    enum InstallError: LocalizedError {
        case noRelease
        case unexpectedLayout

        var errorDescription: String? {
            switch self {
            case .noRelease: "Couldn't find a Java runtime download for this Mac."
            case .unexpectedLayout: "The downloaded Java runtime had an unexpected layout."
            }
        }
    }

    /// Downloads the latest Temurin 21 JRE into `managedBundle` and returns its Java home.
    static func install(progress: @escaping StepProgress) async throws -> URL {
        progress(nil, "Finding the latest Java runtime")
        var components = URLComponents(string: "https://api.adoptium.net/v3/assets/latest/21/hotspot")!
        components.queryItems = [
            URLQueryItem(name: "architecture", value: Host.adoptiumArch),
            URLQueryItem(name: "image_type", value: "jre"),
            URLQueryItem(name: "os", value: "mac"),
            URLQueryItem(name: "vendor", value: "eclipse"),
        ]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let releases = try JSONDecoder().decode([Release].self, from: data)
        guard let package = releases.first(where: { $0.binary.package.name.hasSuffix(".tar.gz") })?.binary.package else {
            throw InstallError.noRelease
        }

        let work = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: work) }
        let archive = work.appending(path: package.name)
        try await Downloader.download(from: package.link, to: archive, progress: Downloader.reporting(to: progress))

        progress(nil, "Verifying")
        try Checksum.verify(archive, matches: package.checksum, using: SHA256.self)

        progress(nil, "Extracting")
        let extracted = work.appending(path: "extracted", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
        try await Archive.untar(archive, into: extracted)

        // The archive holds one bundle directory, e.g. jdk-21.0.12.1+1-jre/Contents/Home.
        let bundle = try FileManager.default.contentsOfDirectory(at: extracted, includingPropertiesForKeys: nil)
            .first { hasJava($0.appending(path: "Contents/Home"), fileManager: .default) }
        guard let bundle else { throw InstallError.unexpectedLayout }

        try? FileManager.default.removeItem(at: managedBundle)
        try FileManager.default.createDirectory(at: managedBundle.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: bundle, to: managedBundle)
        return managedHome
    }
}

func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "EmuDock-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
