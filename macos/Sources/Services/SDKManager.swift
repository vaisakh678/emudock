import Foundation

/// Drives the SDK's `sdkmanager` tool.
struct SDKManager: Sendable {
    let executable: URL
    let sdkRoot: URL
    let javaHome: URL

    /// sdkmanager asks "Accept? (y/N)" for each license; answered on the user's behalf
    /// after they accepted the Android SDK License Agreement in the setup screen.
    private static let answers = String(repeating: "y\n", count: 100)

    private var environment: [String: String] {
        ["JAVA_HOME": javaHome.path(percentEncoded: false)]
    }

    private var sdkRootArgument: String {
        "--sdk_root=\(sdkRoot.path(percentEncoded: false))"
    }

    func acceptLicenses() async throws {
        try await ProcessRunner.run(executable, arguments: [sdkRootArgument, "--licenses"], environment: environment, input: Self.answers)
    }

    func install(_ packages: [String], progress: @escaping StepProgress) async throws {
        try await ProcessRunner.run(
            executable,
            arguments: [sdkRootArgument] + packages,
            environment: environment,
            input: Self.answers
        ) { line in
            if let (fraction, message) = Self.parseProgress(line) {
                progress(fraction, message)
            }
        }
    }

    func uninstall(_ packages: [String]) async throws {
        try await ProcessRunner.run(executable, arguments: [sdkRootArgument, "--uninstall"] + packages, environment: environment)
    }

    /// Every package path sdkmanager lists, installed or available.
    func listPackages() async throws -> [String] {
        Self.packagePaths(inList: try await list())
    }

    /// Raw `sdkmanager --list` output lines.
    func list() async throws -> [String] {
        try await ProcessRunner.run(executable, arguments: [sdkRootArgument, "--list"], environment: environment)
    }

    /// The command-line tools version running this sdkmanager, e.g. "12.0".
    func version() async throws -> String? {
        let lines = try await ProcessRunner.run(executable, arguments: ["--version"], environment: environment)
        return lines.last { $0.wholeMatch(of: /\d+(\.\d+)*/) != nil }
    }

    // MARK: - Parsing

    /// Parses a progress line such as `[=====     ] 45% Downloading foo.zip...`.
    static func parseProgress(_ line: String) -> (fraction: Double, message: String)? {
        guard let match = line.firstMatch(of: /(\d{1,3})%\s*(.*)/), let percent = Double(match.1) else { return nil }
        let message = match.2.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return (min(percent, 100) / 100, message)
    }

    /// Rows of the "Available Updates:" table: package path, installed and available versions.
    static func updates(inList lines: [String]) -> [PackageUpdate] {
        guard let start = lines.firstIndex(where: { $0.hasPrefix("Available Updates:") }) else { return [] }
        var updates: [PackageUpdate] = []
        for line in lines[lines.index(after: start)...] {
            let columns = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            if columns.count != 3 {
                // A line that isn't a table row ends the section.
                if line.hasSuffix(":") { break }
                continue
            }
            guard columns[0] != "ID", !columns[0].hasPrefix("---") else { continue }
            updates.append(PackageUpdate(path: columns[0], installed: columns[1], available: columns[2]))
        }
        return updates
    }

    /// Extracts the first column of `sdkmanager --list` table rows.
    static func packagePaths(inList lines: [String]) -> [String] {
        lines.compactMap { line in
            let columns = line.split(separator: "|", omittingEmptySubsequences: false)
            guard columns.count >= 3 else { return nil }
            let path = columns[0].trimmingCharacters(in: .whitespaces)
            guard !path.isEmpty, path != "Path", path != "ID", !path.hasPrefix("---") else { return nil }
            return path
        }
    }

    /// The newest Google Play system image for `abi`, e.g. `system-images;android-36;google_apis_playstore;arm64-v8a`.
    /// Preview images use codenames instead of numbers and are never picked.
    static func recommendedSystemImage(in paths: [String], abi: String = Host.systemImageABI) -> String? {
        let images = paths.compactMap { path -> (version: [Int], path: String)? in
            guard let match = path.wholeMatch(of: /system-images;android-(\d+(?:\.\d+)?);google_apis_playstore;(.+)/),
                  match.2 == abi else { return nil }
            return (match.1.split(separator: ".").compactMap { Int($0) }, path)
        }
        return images.max { $0.version.lexicographicallyPrecedes($1.version) }?.path
    }
}
