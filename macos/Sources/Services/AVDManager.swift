import Foundation

/// A hardware profile offered in the New Device wizard.
struct HardwarePreset: Identifiable, Sendable, Hashable {
    enum Kind: Sendable {
        case phone, foldable, tablet
    }

    /// The avdmanager device id, e.g. `pixel_9`.
    let id: String
    let name: String
    let kind: Kind

    var symbolName: String {
        switch kind {
        case .phone: "smartphone"
        case .foldable: "rectangle.portrait.split.2x1"
        case .tablet: "ipad.landscape"
        }
    }

    /// Newest first. Only the ones the installed avdmanager knows are shown.
    static let all: [HardwarePreset] = [
        HardwarePreset(id: "pixel_9_pro_xl", name: "Pixel 9 Pro XL", kind: .phone),
        HardwarePreset(id: "pixel_9_pro", name: "Pixel 9 Pro", kind: .phone),
        HardwarePreset(id: "pixel_9", name: "Pixel 9", kind: .phone),
        HardwarePreset(id: "pixel_9_pro_fold", name: "Pixel 9 Pro Fold", kind: .foldable),
        HardwarePreset(id: "pixel_8_pro", name: "Pixel 8 Pro", kind: .phone),
        HardwarePreset(id: "pixel_8", name: "Pixel 8", kind: .phone),
        HardwarePreset(id: "pixel_fold", name: "Pixel Fold", kind: .foldable),
        HardwarePreset(id: "pixel_7_pro", name: "Pixel 7 Pro", kind: .phone),
        HardwarePreset(id: "pixel_7", name: "Pixel 7", kind: .phone),
        HardwarePreset(id: "medium_phone", name: "Medium Phone", kind: .phone),
        HardwarePreset(id: "small_phone", name: "Small Phone", kind: .phone),
        HardwarePreset(id: "pixel_tablet", name: "Pixel Tablet", kind: .tablet),
        HardwarePreset(id: "medium_tablet", name: "Medium Tablet", kind: .tablet),
    ]
}

/// Drives the SDK's `avdmanager` tool.
struct AVDManager: Sendable {
    let executable: URL
    let sdkRoot: URL
    let javaHome: URL

    private var environment: [String: String] {
        let sdkPath = sdkRoot.path(percentEncoded: false)
        return ["JAVA_HOME": javaHome.path(percentEncoded: false), "ANDROID_HOME": sdkPath, "ANDROID_SDK_ROOT": sdkPath]
    }

    /// Hardware profile ids this avdmanager knows (`avdmanager list device -c`).
    func deviceIDs() async throws -> Set<String> {
        let lines = try await ProcessRunner.run(executable, arguments: ["list", "device", "-c"], environment: environment)
        return Set(lines.filter { !$0.hasPrefix("Warning") })
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
