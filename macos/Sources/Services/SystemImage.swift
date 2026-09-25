import Foundation

/// Marketing names for Android API levels.
enum AndroidVersion {
    /// "Android 16" for "36" or "36.1"; nil for unknown or preview levels.
    static func name(forAPI apiLevel: String) -> String? {
        guard let major = Int(apiLevel.split(separator: ".").first ?? "") else { return nil }
        let names = [28: "9", 29: "10", 30: "11", 31: "12", 32: "12L", 33: "13", 34: "14", 35: "15", 36: "16", 37: "17"]
        if let name = names[major] { return "Android \(name)" }
        return major > 37 ? "Android \(major - 20)" : nil
    }
}

/// A system image package such as `system-images;android-36;google_apis_playstore;arm64-v8a`.
struct SystemImage: Identifiable, Sendable, Hashable {
    let path: String
    let apiLevel: String
    let tag: String
    let abi: String
    var isInstalled: Bool

    var id: String { path }

    init?(path: String, isInstalled: Bool) {
        let parts = path.split(separator: ";").map(String.init)
        guard parts.count == 4, parts[0] == "system-images", parts[1].hasPrefix("android-") else { return nil }
        let api = String(parts[1].dropFirst("android-".count))
        // Numbered levels only: previews use codenames like "android-CinnamonBun".
        guard api.first?.isNumber == true else { return nil }
        self.path = path
        self.apiLevel = api
        self.tag = parts[2]
        self.abi = parts[3]
        self.isInstalled = isInstalled
    }

    var version: [Int] {
        apiLevel.split(separator: ".").compactMap { Int($0) }
    }

    var isGooglePlay: Bool { tag.hasPrefix("google_apis_playstore") }

    var title: String {
        let api = "API \(apiLevel)"
        return AndroidVersion.name(forAPI: apiLevel).map { "\($0) (\(api))" } ?? api
    }

    var tagDisplay: String {
        var base = tag
        var suffix = ""
        if base.hasSuffix("_ps16k") {
            base = String(base.dropLast("_ps16k".count))
            suffix = " · 16 KB pages"
        }
        let name = switch base {
        case "google_apis_playstore": "Google Play"
        case "google_apis": "Google APIs (rootable)"
        case "default": "AOSP"
        default: base
        }
        return name + suffix
    }

    /// Phone and tablet images for this Mac's architecture (not Wear OS, TV, Automotive…).
    var isPhoneOrTablet: Bool {
        abi == Host.systemImageABI
            && ["google_apis_playstore", "google_apis", "default"].contains(tag.replacing("_ps16k", with: ""))
    }

    /// Newest first; at the same level, Google Play before other tags.
    static func sorted(_ images: [SystemImage]) -> [SystemImage] {
        images.sorted { lhs, rhs in
            if lhs.version != rhs.version { return rhs.version.lexicographicallyPrecedes(lhs.version) }
            if lhs.isGooglePlay != rhs.isGooglePlay { return lhs.isGooglePlay }
            return lhs.tag < rhs.tag
        }
    }
}
