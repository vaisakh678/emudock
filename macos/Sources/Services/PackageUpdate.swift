import Foundation

/// An installed SDK package with a newer version available.
struct PackageUpdate: Identifiable, Codable, Sendable, Hashable {
    let path: String
    let installed: String
    let available: String

    var id: String { path }

    static let commandLineTools = "cmdline-tools;latest"

    /// The tools EmuDock itself relies on; these are pre-selected for updating.
    var isEssential: Bool {
        [Self.commandLineTools, "emulator", "platform-tools"].contains(path)
    }

    var displayName: String {
        switch path {
        case Self.commandLineTools: return "Command-line tools"
        case "emulator": return "Emulator"
        case "platform-tools": return "Platform tools (adb)"
        default:
            if let image = SystemImage(path: path, isInstalled: true) {
                return "\(image.title) · \(image.tagDisplay)"
            }
            return path
        }
    }

    /// Compares dotted version strings numerically, so "23.0" > "12.0" and "37.1.11" > "36.5.10".
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ version: String) -> [Int] { version.split(separator: ".").map { Int($0) ?? 0 } }
        let lhs = parts(candidate)
        let rhs = parts(current)
        let count = max(lhs.count, rhs.count)
        let padded = { (v: [Int]) in v + Array(repeating: 0, count: count - v.count) }
        return padded(rhs).lexicographicallyPrecedes(padded(lhs))
    }
}
