import CryptoKit
import Foundation

/// Installs Google's Android SDK Command-line Tools (`sdkmanager`, `avdmanager`).
enum CommandLineTools {
    static let repositoryURL = URL(string: "https://dl.google.com/android/repository/repository2-3.xml")!

    struct Archive: Equatable {
        let url: URL
        let sha1: String
        /// e.g. "23.0"
        let version: String
    }

    enum InstallError: LocalizedError {
        case noArchive
        case unexpectedLayout

        var errorDescription: String? {
            switch self {
            case .noArchive: "Couldn't find the Android command-line tools for this Mac."
            case .unexpectedLayout: "The downloaded command-line tools had an unexpected layout."
            }
        }
    }

    /// Picks the `cmdline-tools;latest` archive for macOS on `arch` from the SDK repository manifest.
    static func latestArchive(inRepository data: Data, arch: String = Host.sdkRepositoryArch) throws -> Archive? {
        let document = try XMLDocument(data: data)
        let package = "//remotePackage[@path='cmdline-tools;latest']"
        let revision = ["major", "minor"].compactMap { part in
            (try? document.nodes(forXPath: "\(package)/revision/\(part)"))?.first?.stringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let archives = try document.nodes(forXPath: "\(package)/archives/archive")
        for case let archive as XMLElement in archives {
            func value(_ xpath: String) -> String? {
                (try? archive.nodes(forXPath: xpath))?.first?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard value("host-os") == "macosx" else { continue }
            if let hostArch = value("host-arch"), hostArch != arch { continue }
            guard let file = value("complete/url"), let sha1 = value("complete/checksum") else { continue }
            return Archive(
                url: repositoryURL.deletingLastPathComponent().appending(path: file),
                sha1: sha1,
                version: revision.joined(separator: ".")
            )
        }
        return nil
    }

    /// The newest command-line tools archive for this Mac, from Google's SDK catalog.
    static func fetchLatest() async throws -> Archive {
        let (manifest, _) = try await URLSession.shared.data(from: repositoryURL)
        guard let archive = try latestArchive(inRepository: manifest) else { throw InstallError.noArchive }
        return archive
    }

    /// Downloads the tools into `<sdkRoot>/cmdline-tools/latest`, replacing any existing copy.
    static func install(into sdkRoot: URL, progress: @escaping StepProgress) async throws {
        progress(nil, "Finding the latest command-line tools")
        let archive = try await fetchLatest()

        let work = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: work) }
        let zip = work.appending(path: archive.url.lastPathComponent)
        try await Downloader.download(from: archive.url, to: zip, progress: Downloader.reporting(to: progress))

        progress(nil, "Verifying")
        try Checksum.verify(zip, matches: archive.sha1, using: Insecure.SHA1.self)

        progress(nil, "Extracting")
        try await EmuDock.Archive.unzip(zip, into: work)
        // The zip contains a top-level `cmdline-tools/` folder; sdkmanager expects it at cmdline-tools/latest.
        let extracted = work.appending(path: "cmdline-tools", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: extracted.appending(path: "bin/sdkmanager").path(percentEncoded: false)) else {
            throw InstallError.unexpectedLayout
        }
        let destination = AndroidSDK.sdkmanager(in: sdkRoot).deletingLastPathComponent().deletingLastPathComponent()
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: extracted, to: destination)
    }
}
