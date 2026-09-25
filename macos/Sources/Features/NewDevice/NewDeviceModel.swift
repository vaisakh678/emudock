import Foundation
import Observation

/// State for the New Device sheet: pick hardware, pick a system image, name it, create.
@MainActor
@Observable
final class NewDeviceModel: Identifiable {
    enum Phase: Equatable {
        case editing
        case working(fraction: Double?, detail: String)
        case failed(String)
    }

    private let avdManager: AVDManager
    private let sdkManager: SDKManager
    private let existingNames: Set<String>

    private(set) var presets: [HardwarePreset] = []
    private(set) var images: [SystemImage]
    private(set) var isLoadingDownloads = true
    private(set) var phase = Phase.editing
    var showAllImageTypes = false

    var preset: HardwarePreset? { didSet { suggestName() } }
    var image: SystemImage? { didSet { suggestName() } }
    var name = ""
    /// Once the user edits the name, stop overwriting it with suggestions.
    var nameEdited = false

    private var task: Task<Void, Never>?

    init?(status: AndroidSDK.Status, existingNames: Set<String>) {
        guard let root = status.root, let javaHome = status.javaHome,
              let avdmanager = status.avdmanager, let sdkmanager = status.sdkmanager else { return nil }
        avdManager = AVDManager(executable: avdmanager, sdkRoot: root, javaHome: javaHome)
        sdkManager = SDKManager(executable: sdkmanager, sdkRoot: root, javaHome: javaHome)
        self.existingNames = existingNames
        images = SystemImage.sorted(
            status.systemImages.compactMap { SystemImage(path: $0, isInstalled: true) }.filter(\.isPhoneOrTablet)
        )
        image = images.first
    }

    /// Installed images always; downloadable ones only for recent Android versions,
    /// and only Google Play images unless the user asks for all types.
    var visibleImages: [SystemImage] {
        images.filter { image in
            image.isInstalled || ((image.version.first ?? 0) >= 30 && (showAllImageTypes || image.tag == "google_apis_playstore"))
        }
    }

    var canCreate: Bool {
        phase == .editing && preset != nil && image != nil && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var isWorking: Bool {
        if case .working = phase { true } else { false }
    }

    func load() async {
        async let deviceIDs = try? avdManager.deviceIDs()
        async let available = try? sdkManager.listPackages()

        let known = await deviceIDs ?? []
        presets = HardwarePreset.all.filter { known.contains($0.id) }
        if presets.isEmpty { presets = HardwarePreset.all.filter { $0.id == "medium_phone" } }
        preset = presets.first

        let installed = Set(images.map(\.path))
        let downloads = (await available ?? [])
            .filter { !installed.contains($0) }
            .compactMap { SystemImage(path: $0, isInstalled: false) }
            .filter(\.isPhoneOrTablet)
        images = SystemImage.sorted(images + Set(downloads))
        if image == nil { image = visibleImages.first }
        isLoadingDownloads = false
    }

    func create(onSuccess: @escaping @MainActor () async -> Void) {
        guard canCreate, let preset, let image else { return }
        let displayName = name.trimmingCharacters(in: .whitespaces)
        let avdName = uniqueAVDName(for: displayName)
        phase = .working(fraction: nil, detail: "Starting")

        task = Task {
            do {
                if !image.isInstalled {
                    try await sdkManager.install([image.path]) { fraction, detail in
                        Task { @MainActor in
                            guard self.isWorking else { return }
                            self.phase = .working(fraction: fraction, detail: "\(image.title): \(detail)")
                        }
                    }
                }
                phase = .working(fraction: nil, detail: "Creating \(displayName)")
                try await avdManager.create(name: avdName, image: image.path, device: preset.id)

                let config = AVDCatalog.avdHome().appending(path: "\(avdName).avd/config.ini")
                try AVDManager.updateConfig(at: config, with: [
                    "avd.ini.displayname": displayName,
                    // Type into the emulator with the Mac keyboard.
                    "hw.keyboard": "yes",
                    "hw.gpu.enabled": "yes",
                    "hw.gpu.mode": "auto",
                ])
                await onSuccess()
            } catch is CancellationError {
                phase = .editing
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        task?.cancel()
    }

    func dismissError() {
        phase = .editing
    }

    private func suggestName() {
        guard !nameEdited, let preset else { return }
        name = image.map { "\(preset.name) API \($0.apiLevel)" } ?? preset.name
    }

    private func uniqueAVDName(for displayName: String) -> String {
        let base = AVDManager.avdName(for: displayName)
        var candidate = base
        var counter = 2
        while existingNames.contains(candidate) {
            candidate = "\(base)_\(counter)"
            counter += 1
        }
        return candidate
    }
}
