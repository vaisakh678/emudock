import Foundation

/// A phone or tablet hardware definition from `avdmanager list device`.
struct HardwareProfile: Identifiable, Sendable, Hashable {
    enum Kind: Sendable {
        case phone, foldable, tablet
    }

    /// The avdmanager device id, e.g. `pixel_9`.
    let id: String
    let name: String
    let oem: String
    let kind: Kind

    var symbolName: String {
        switch kind {
        case .phone: "smartphone"
        case .foldable: "rectangle.portrait.split.2x1"
        case .tablet: "ipad.landscape"
        }
    }

    /// The Pixel generation, e.g. 10 for "Pixel 10 Pro Fold"; nil for other devices.
    var pixelGeneration: Int? {
        guard let match = name.firstMatch(of: /^Pixel (\d+)/) else { return nil }
        return Int(match.1)
    }

    /// Orders variants within a Pixel generation: base, Pro, Pro XL, Pro Fold, a.
    private var variantRank: Int {
        let variant = name.replacing(/^Pixel \d+/, with: "").trimmingCharacters(in: .whitespaces)
        return ["", "Pro", "Pro XL", "Pro Fold", "XL", "a", "a XL"].firstIndex(of: variant) ?? 9
    }

    init(id: String, name: String, oem: String) {
        self.id = id
        self.name = name
        self.oem = oem
        let lowered = "\(id) \(name)".lowercased()
        if lowered.contains("fold") || lowered.contains("rollable") {
            kind = .foldable
        } else if lowered.contains("tablet") || ["Nexus 7", "Nexus 7 2013", "Nexus 9", "Nexus 10", "pixel_c"].contains(id) {
            kind = .tablet
        } else {
            kind = .phone
        }
    }

    /// Parses `avdmanager list device`, keeping phones and tablets.
    /// Wear OS, TV, Automotive, desktop, XR and glasses profiles carry a `Tag` and are skipped.
    static func parse(_ lines: [String]) -> [HardwareProfile] {
        var profiles: [HardwareProfile] = []
        var id: String?
        var name: String?
        var oem = ""
        var tagged = false

        func flush() {
            if let id, let name, !tagged {
                profiles.append(HardwareProfile(id: id, name: name, oem: oem))
            }
            id = nil
            name = nil
            oem = ""
            tagged = false
        }

        for line in lines {
            if let match = line.firstMatch(of: /^id: \d+ or "(.+)"$/) {
                flush()
                id = String(match.1)
            } else if let match = line.firstMatch(of: /^Name\s*:\s*(.+)$/) {
                name = String(match.1)
            } else if let match = line.firstMatch(of: /^OEM\s*:\s*(.+)$/) {
                oem = String(match.1)
            } else if line.hasPrefix("Tag") {
                tagged = true
            }
        }
        flush()
        return profiles
    }

    /// Splits profiles into a short "Popular" list (the two newest Pixel generations plus
    /// the Pixel Fold/Tablet and generic sizes) and everything else, both newest first.
    static func grouped(_ profiles: [HardwareProfile]) -> (popular: [HardwareProfile], others: [HardwareProfile]) {
        let generations = Set(profiles.compactMap(\.pixelGeneration)).sorted(by: >).prefix(2)
        let popularIDs: Set<String> = ["pixel_fold", "pixel_tablet", "medium_phone", "small_phone", "medium_tablet"]
        let sorted = profiles.sorted(by: newestFirst)
        let popular = sorted.filter { profile in
            profile.pixelGeneration.map(generations.contains) ?? popularIDs.contains(profile.id)
        }
        let popularSet = Set(popular.map(\.id))
        return (popular, sorted.filter { !popularSet.contains($0.id) })
    }

    /// Newer Pixels first, then other Google devices, then generic ones, by name.
    private static func newestFirst(_ lhs: HardwareProfile, _ rhs: HardwareProfile) -> Bool {
        switch (lhs.pixelGeneration, rhs.pixelGeneration) {
        case let (l?, r?) where l != r: return l > r
        case let (l?, r?) where l == r: return lhs.variantRank < rhs.variantRank
        case (_?, nil): return true
        case (nil, _?): return false
        default:
            if (lhs.oem == "Google") != (rhs.oem == "Google") { return lhs.oem == "Google" }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
