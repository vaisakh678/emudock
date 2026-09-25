import Foundation

/// An Android Virtual Device, read from `~/.android/avd/<name>.ini` and its `config.ini`.
struct AVD: Identifiable, Sendable, Equatable {
    /// The AVD name passed to `emulator -avd`.
    let id: String
    let displayName: String
    let directory: URL
    /// API level as written in the config, e.g. "36" or "37.0".
    let apiLevel: String?
    let tagDisplay: String?
    let deviceName: String?
    let screenSize: ScreenSize?

    struct ScreenSize: Sendable, Equatable {
        let width: Int
        let height: Int
    }

    /// Marketing name for the API level, e.g. "Android 16".
    var androidVersion: String? {
        apiLevel.flatMap(AndroidVersion.name(forAPI:))
    }

    var summary: String {
        var parts: [String] = []
        switch (androidVersion, apiLevel) {
        case let (version?, api?): parts.append("\(version) (API \(api))")
        case let (nil, api?): parts.append("API \(api)")
        default: break
        }
        if let tagDisplay { parts.append(tagDisplay) }
        if let screenSize { parts.append("\(screenSize.width) × \(screenSize.height)") }
        return parts.joined(separator: " · ")
    }

    var symbolName: String {
        let device = deviceName?.lowercased() ?? ""
        if device.contains("tablet") { return "ipad.landscape" }
        if device.contains("fold") { return "rectangle.portrait.split.2x1" }
        if device.contains("tv") { return "tv" }
        if device.contains("wear") || device.contains("watch") { return "applewatch" }
        if device.contains("automotive") { return "car" }
        if device.contains("desktop") { return "desktopcomputer" }
        return "smartphone"
    }
}

enum AVDCatalog {
    /// Where AVDs live, following the same environment variables as the Android tools.
    static func avdHome(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        if let path = environment["ANDROID_AVD_HOME"], !path.isEmpty {
            return URL(filePath: path, directoryHint: .isDirectory)
        }
        for key in ["ANDROID_USER_HOME", "ANDROID_EMULATOR_HOME"] {
            if let path = environment[key], !path.isEmpty {
                return URL(filePath: path, directoryHint: .isDirectory).appending(path: "avd", directoryHint: .isDirectory)
            }
        }
        return home.appending(path: ".android/avd", directoryHint: .isDirectory)
    }

    static func load(from avdHome: URL = avdHome(), fileManager: FileManager = .default) -> [AVD] {
        let entries = (try? fileManager.contentsOfDirectory(at: avdHome, includingPropertiesForKeys: nil)) ?? []
        return entries
            .filter { $0.pathExtension == "ini" }
            .compactMap { load(ini: $0, avdHome: avdHome) }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private static func load(ini: URL, avdHome: URL) -> AVD? {
        guard let pointer = try? parseINI(String(contentsOf: ini, encoding: .utf8)) else { return nil }
        let name = ini.deletingPathExtension().lastPathComponent
        let directory = pointer["path"].map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? avdHome.appending(path: "\(name).avd", directoryHint: .isDirectory)
        let config = (try? parseINI(String(contentsOf: directory.appending(path: "config.ini"), encoding: .utf8))) ?? [:]

        let target = config["target"] ?? pointer["target"]
        let screenSize = Int(config["hw.lcd.width"] ?? "").flatMap { width in
            Int(config["hw.lcd.height"] ?? "").map { AVD.ScreenSize(width: width, height: $0) }
        }
        return AVD(
            id: name,
            displayName: config["avd.ini.displayname"] ?? name.replacing("_", with: " "),
            directory: directory,
            apiLevel: target.flatMap { $0.hasPrefix("android-") ? String($0.dropFirst("android-".count)) : nil },
            tagDisplay: imageTagDisplay(config) ?? config["tag.display"],
            deviceName: config["hw.device.name"],
            screenSize: screenSize
        )
    }

    /// "Google Play · 16 KB pages" etc., from the system image folder, e.g.
    /// `system-images/android-37.0/google_apis_playstore_ps16k/arm64-v8a/`. The config's own
    /// `tag.display` is inconsistent ("Google APIs PlayStore") and omits the 16 KB variant.
    static func imageTagDisplay(_ config: [String: String]) -> String? {
        guard let sysdir = config["image.sysdir.1"] else { return nil }
        let path = sysdir.split(separator: "/").joined(separator: ";")
        return SystemImage(path: path, isInstalled: true)?.tagDisplay
    }

    static func parseINI(_ text: String) -> [String: String] {
        var values: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard let separator = line.firstIndex(of: "="), !line.hasPrefix("#") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            values[key] = value
        }
        return values
    }
}
