import Foundation

/// Drives the SDK's `avdmanager` tool.
struct AVDManager: Sendable {
    let executable: URL
    let sdkRoot: URL
    let javaHome: URL

    init(executable: URL, sdkRoot: URL, javaHome: URL) {
        self.executable = executable
        self.sdkRoot = sdkRoot
        self.javaHome = javaHome
    }

    init?(status: AndroidSDK.Status) {
        guard let root = status.root, let javaHome = status.javaHome, let avdmanager = status.avdmanager else { return nil }
        self.init(executable: avdmanager, sdkRoot: root, javaHome: javaHome)
    }

    private var environment: [String: String] {
        let sdkPath = sdkRoot.path(percentEncoded: false)
        return ["JAVA_HOME": javaHome.path(percentEncoded: false), "ANDROID_HOME": sdkPath, "ANDROID_SDK_ROOT": sdkPath]
    }

    /// Phone and tablet hardware profiles this avdmanager knows.
    func hardwareProfiles() async throws -> [HardwareProfile] {
        let lines = try await ProcessRunner.run(executable, arguments: ["list", "device"], environment: environment)
        return HardwareProfile.parse(lines)
    }

    func create(name: String, image: String, device: String) async throws {
        // avdmanager asks "Do you wish to create a custom hardware profile? [no]".
        try await ProcessRunner.run(
            executable,
            arguments: ["create", "avd", "--name", name, "--package", image, "--device", device],
            environment: environment,
            input: "no\n"
        )
    }

    /// Deletes the AVD's folder and its `.ini` pointer, including all its apps and data.
    func delete(name: String) async throws {
        try await ProcessRunner.run(executable, arguments: ["delete", "avd", "--name", name], environment: environment)
    }

    /// Turns a display name into a valid AVD name: letters, digits, `.`, `_` and `-` only.
    static func avdName(for displayName: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        let mapped = String(displayName.trimmingCharacters(in: .whitespaces).map { allowed.contains($0) ? $0 : "_" })
        return mapped.isEmpty ? "Device" : mapped
    }

    /// Sets keys in an AVD's `config.ini`, replacing existing values and appending new ones.
    static func updateConfig(at url: URL, with values: [String: String]) throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        var remaining = values
        var lines = text.split(whereSeparator: \.isNewline).map { line -> String in
            guard let separator = line.firstIndex(of: "=") else { return String(line) }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            guard let value = remaining.removeValue(forKey: key) else { return String(line) }
            return "\(key)=\(value)"
        }
        lines += remaining.keys.sorted().map { "\($0)=\(remaining[$0]!)" }
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
