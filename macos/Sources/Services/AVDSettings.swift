import Foundation

/// The editable hardware settings of an AVD, read from and written to its `config.ini`.
struct AVDSettings: Equatable, Sendable {
    enum Orientation: String, CaseIterable, Sendable {
        case portrait, landscape
    }

    enum Camera: String, CaseIterable, Sendable {
        case none, emulated, virtualscene, webcam0

        var title: String {
            switch self {
            case .none: "None"
            case .emulated: "Emulated"
            case .virtualscene: "Virtual scene"
            case .webcam0: "Mac camera"
            }
        }
    }

    struct Resolution: Hashable, Sendable {
        var width: Int
        var height: Int
        var density: Int

        var title: String { "\(width) × \(height) · \(density) dpi" }

        var isValid: Bool {
            (240...4096).contains(width) && (240...4096).contains(height) && (120...640).contains(density)
        }
    }

    var name: String
    var ramMB: Int
    var cpuCores: Int
    var storageMB: Int
    var resolution: Resolution
    var orientation: Orientation
    var hostKeyboard: Bool
    var backCamera: Camera
    var frontCamera: Camera
    var alwaysColdBoot: Bool
    var deviceFrame: Bool

    init(config: [String: String]) {
        name = config["avd.ini.displayname"] ?? ""
        ramMB = config["hw.ramSize"].flatMap(Self.megabytes) ?? 2048
        cpuCores = config["hw.cpu.ncore"].flatMap { Int($0) } ?? 2
        storageMB = config["disk.dataPartition.size"].flatMap(Self.megabytes) ?? 6144
        resolution = Resolution(
            width: config["hw.lcd.width"].flatMap { Int($0) } ?? 1080,
            height: config["hw.lcd.height"].flatMap { Int($0) } ?? 2400,
            density: config["hw.lcd.density"].flatMap { Int($0) } ?? 420
        )
        orientation = config["hw.initialOrientation"].flatMap(Orientation.init(rawValue:)) ?? .portrait
        hostKeyboard = config["hw.keyboard"] == "yes"
        backCamera = config["hw.camera.back"].flatMap(Camera.init(rawValue:)) ?? .emulated
        frontCamera = config["hw.camera.front"].flatMap(Camera.init(rawValue:)) ?? .emulated
        alwaysColdBoot = config["fastboot.forceColdBoot"] == "yes"
        deviceFrame = config["showDeviceFrame"] != "no"
    }

    /// The `config.ini` keys to write, only for settings that differ from `original`.
    func changes(from original: AVDSettings) -> [String: String] {
        var values: [String: String] = [:]
        let trimmedName = Self.cleanName(name)
        if trimmedName != Self.cleanName(original.name), !trimmedName.isEmpty { values["avd.ini.displayname"] = trimmedName }
        if ramMB != original.ramMB { values["hw.ramSize"] = String(ramMB) }
        if cpuCores != original.cpuCores { values["hw.cpu.ncore"] = String(cpuCores) }
        if storageMB != original.storageMB { values["disk.dataPartition.size"] = Self.sizeString(storageMB) }
        if resolution != original.resolution {
            values["hw.lcd.width"] = String(resolution.width)
            values["hw.lcd.height"] = String(resolution.height)
            values["hw.lcd.density"] = String(resolution.density)
            // A device skin (e.g. the Pixel 9 Pro XL frame) is drawn for its own screen size,
            // so a new resolution switches to a plain frame of that size.
            let skin = "\(resolution.width)x\(resolution.height)"
            values["skin.name"] = skin
            values["skin.path"] = skin
            values["skin.dynamic"] = "yes"
        }
        if orientation != original.orientation { values["hw.initialOrientation"] = orientation.rawValue }
        if hostKeyboard != original.hostKeyboard { values["hw.keyboard"] = hostKeyboard ? "yes" : "no" }
        if backCamera != original.backCamera { values["hw.camera.back"] = backCamera.rawValue }
        if frontCamera != original.frontCamera { values["hw.camera.front"] = frontCamera.rawValue }
        if alwaysColdBoot != original.alwaysColdBoot { values["fastboot.forceColdBoot"] = alwaysColdBoot ? "yes" : "no" }
        if deviceFrame != original.deviceFrame { values["showDeviceFrame"] = deviceFrame ? "yes" : "no" }
        return values
    }

    /// A display name on one line with no surrounding spaces (config.ini is line-based).
    static func cleanName(_ name: String) -> String {
        name.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Sizes

    /// Parses config sizes like "2048", "2G", "1536M", "512 MB" or raw bytes ("6442450944") into megabytes.
    static func megabytes(_ text: String) -> Int? {
        guard let match = text.trimmingCharacters(in: .whitespaces)
            .wholeMatch(of: /(?i)(\d+)\s*([kmgt]?)b?/),
            let number = Int(match.1) else { return nil }
        switch match.2.lowercased() {
        case "k": return number / 1024
        case "m": return number
        case "g": return number * 1024
        case "t": return number * 1024 * 1024
        // Unitless: small numbers are megabytes (hw.ramSize), large ones are bytes (disk sizes).
        default: return number > 1_000_000 ? number / (1024 * 1024) : number
        }
    }

    static func sizeString(_ megabytes: Int) -> String {
        megabytes % 1024 == 0 ? "\(megabytes / 1024)G" : "\(megabytes)M"
    }

    static func sizeTitle(_ megabytes: Int) -> String {
        megabytes % 1024 == 0 ? "\(megabytes / 1024) GB" : String(format: "%.1f GB", Double(megabytes) / 1024)
    }
}

/// Limits and recommendations based on this Mac's hardware.
enum HostResources {
    static let memoryMB = Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024))
    static let cores = ProcessInfo.processInfo.activeProcessorCount

    /// Emulator RAM choices, up to half of the Mac's memory (and at most 8 GB).
    static var ramOptions: [Int] {
        [1024, 1536, 2048, 3072, 4096, 6144, 8192].filter { $0 <= memoryMB / 2 }
    }

    static var coreOptions: [Int] {
        Array(1...min(cores, 8))
    }

    static var recommendedRAM: Int { memoryMB >= 16 * 1024 ? 4096 : 2048 }
    static var recommendedCores: Int { min(4, max(1, cores / 2)) }
}
