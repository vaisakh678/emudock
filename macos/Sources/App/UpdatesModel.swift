import Foundation
import Observation

/// Checks the SDK for package updates (at most once a day on its own) and installs them.
@MainActor
@Observable
final class UpdatesModel {
    enum Phase: Equatable {
        case idle
        case checking
        case installing(fraction: Double?, detail: String)
        case failed(String)
    }

    private struct Cache: Codable {
        let checked: Date
        let updates: [PackageUpdate]
    }

    private static let cacheKey = "sdkUpdates"
    private static let checkInterval: TimeInterval = 24 * 60 * 60

    private(set) var updates: [PackageUpdate] = []
    private(set) var lastChecked: Date?
    private(set) var phase = Phase.idle
    var selection: Set<String> = []
    private var task: Task<Void, Never>?

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let cache = try? JSONDecoder().decode(Cache.self, from: data) {
            apply(cache.updates, checked: cache.checked)
        }
    }

    var isBusy: Bool {
        switch phase {
        case .checking, .installing: true
        case .idle, .failed: false
        }
    }

    func checkIfDue(status: AndroidSDK.Status) {
        guard status.isReady, !isBusy else { return }
        if let lastChecked, Date.now.timeIntervalSince(lastChecked) < Self.checkInterval { return }
        task = Task { await check(status: status) }
    }

    func check(status: AndroidSDK.Status) async {
        guard let manager = SDKManager(status: status), !isBusy else { return }
        phase = .checking
        do {
            async let listing = manager.list()
            async let current = manager.version()
            async let latest = try? CommandLineTools.fetchLatest()

            // sdkmanager doesn't report its own updates, so the command-line tools are
            // compared against Google's catalog separately.
            var found = SDKManager.updates(inList: try await listing).filter { $0.path != PackageUpdate.commandLineTools }
            if let current = try await current, let latest = await latest,
               PackageUpdate.isNewer(latest.version, than: current) {
                found.append(PackageUpdate(path: PackageUpdate.commandLineTools, installed: current, available: latest.version))
            }
            apply(found, checked: .now)
            save()
            phase = .idle
        } catch is CancellationError {
            phase = .idle
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func installSelected(sdk: SDKStatusModel) {
        guard let status = sdk.status, let root = status.root, let manager = SDKManager(status: status), !isBusy else { return }
        let chosen = updates.filter { selection.contains($0.id) }
        guard !chosen.isEmpty else { return }
        phase = .installing(fraction: nil, detail: "Starting")

        task = Task {
            do {
                // Other packages first, while the current sdkmanager is still in place.
                let packages = chosen.map(\.path).filter { $0 != PackageUpdate.commandLineTools }
                if !packages.isEmpty {
                    try await manager.install(packages, progress: reporter)
                }
                if chosen.contains(where: { $0.path == PackageUpdate.commandLineTools }) {
                    try await CommandLineTools.install(into: root, progress: reporter)
                }
                phase = .idle
                await sdk.refresh()
                if let refreshed = sdk.status {
                    await check(status: refreshed)
                }
            } catch is CancellationError {
                phase = .idle
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        task?.cancel()
    }

    /// Drops a package that was uninstalled, so it isn't offered as an update.
    func forget(_ path: String) {
        guard updates.contains(where: { $0.path == path }) else { return }
        updates.removeAll { $0.path == path }
        selection.remove(path)
        save()
    }

    private var reporter: StepProgress {
        { fraction, detail in
            Task { @MainActor in
                guard case .installing = self.phase else { return }
                self.phase = .installing(fraction: fraction, detail: detail)
            }
        }
    }

    /// Essential tools (command-line tools, emulator, platform tools) first and pre-selected.
    private func apply(_ found: [PackageUpdate], checked: Date) {
        updates = found.sorted { lhs, rhs in
            lhs.isEssential != rhs.isEssential ? lhs.isEssential : lhs.displayName < rhs.displayName
        }
        lastChecked = checked
        selection = Set(updates.filter(\.isEssential).map(\.id))
    }

    private func save() {
        guard let lastChecked, let data = try? JSONEncoder().encode(Cache(checked: lastChecked, updates: updates)) else { return }
        UserDefaults.standard.set(data, forKey: Self.cacheKey)
    }
}

extension SDKManager {
    init?(status: AndroidSDK.Status) {
        guard let root = status.root, let javaHome = status.javaHome, let sdkmanager = status.sdkmanager else { return nil }
        self.init(executable: sdkmanager, sdkRoot: root, javaHome: javaHome)
    }
}
