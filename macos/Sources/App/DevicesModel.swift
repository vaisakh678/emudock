import Foundation
import Observation

/// The user's AVDs and which of them are running, refreshed every couple of seconds.
@MainActor
@Observable
final class DevicesModel {
    enum DeviceState: Equatable {
        case stopped, starting, running, stopping, deleting

        var title: String {
            switch self {
            case .stopped: "Stopped"
            case .starting: "Starting…"
            case .running: "Running"
            case .stopping: "Stopping…"
            case .deleting: "Deleting…"
            }
        }

        var isBusy: Bool {
            self == .starting || self == .stopping || self == .deleting
        }
    }

    private(set) var devices: [AVD] = []
    private(set) var running: [String: RunningEmulator] = [:]
    private var booted: Set<String> = []
    private var launching: Set<String> = []
    private var stopping: Set<String> = []
    private var deleting: Set<String> = []
    private var tools: EmulatorTools?
    private var avdManager: AVDManager?
    private var pollTask: Task<Void, Never>?
    var errorMessage: String?

    func configure(with status: AndroidSDK.Status?) {
        tools = status.flatMap(EmulatorTools.init(status:))
        avdManager = status.flatMap(AVDManager.init(status:))
    }

    func state(of avd: AVD) -> DeviceState {
        if deleting.contains(avd.id) { return .deleting }
        if stopping.contains(avd.id) { return .stopping }
        if running[avd.id] != nil { return booted.contains(avd.id) ? .running : .starting }
        return launching.contains(avd.id) ? .starting : .stopped
    }

    /// Starts the refresh loop once; it runs for the app's lifetime.
    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func refresh() async {
        let (avds, found) = await Task.detached {
            (AVDCatalog.load(), EmulatorDiscovery.running())
        }.value
        devices = avds
        running = Dictionary(found.map { ($0.avdID, $0) }, uniquingKeysWith: { first, _ in first })

        let runningIDs = Set(running.keys)
        launching.subtract(runningIDs)
        stopping.formIntersection(runningIDs)
        booted.formIntersection(runningIDs)

        guard let tools else { return }
        for (id, emulator) in running where !booted.contains(id) {
            if await tools.isBootCompleted(emulator.serial) {
                booted.insert(id)
            }
        }
    }

    func launch(_ avd: AVD, coldBoot: Bool = false) {
        guard let tools, state(of: avd) == .stopped else { return }
        launching.insert(avd.id)
        do {
            try tools.launch(avd, coldBoot: coldBoot) { [weak self] message in
                Task { @MainActor in
                    self?.launching.remove(avd.id)
                    self?.errorMessage = "\(avd.displayName) couldn't start.\n\n\(message)"
                }
            }
        } catch {
            launching.remove(avd.id)
            errorMessage = error.localizedDescription
        }
        // Emulators that never come up (e.g. killed before writing their discovery file)
        // shouldn't show "Starting" forever.
        Task {
            try? await Task.sleep(for: .seconds(60))
            launching.remove(avd.id)
        }
    }

    /// Deletes stopped emulators one by one; running ones are left alone.
    func delete(_ avds: [AVD]) {
        guard let avdManager else { return }
        let targets = avds.filter { state(of: $0) == .stopped }
        guard !targets.isEmpty else { return }
        deleting.formUnion(targets.map(\.id))
        Task {
            var failures: [String] = []
            for avd in targets {
                do {
                    try await avdManager.delete(name: avd.id)
                } catch {
                    failures.append("\(avd.displayName): \(error.localizedDescription)")
                }
            }
            await refresh()
            deleting.subtract(targets.map(\.id))
            if !failures.isEmpty {
                errorMessage = "Couldn't delete:\n\n" + failures.joined(separator: "\n\n")
            }
        }
    }

    /// Changes the display name only; the AVD id used by `emulator -avd` stays the same.
    func rename(_ avd: AVD, to name: String) {
        let cleaned = AVDSettings.cleanName(name)
        guard !cleaned.isEmpty, cleaned != avd.displayName else { return }
        do {
            try AVDManager.updateConfig(at: avd.directory.appending(path: "config.ini"), with: ["avd.ini.displayname": cleaned])
        } catch {
            errorMessage = "Couldn't rename \(avd.displayName).\n\n\(error.localizedDescription)"
        }
        Task { await refresh() }
    }

    func stop(_ avd: AVD) {
        guard let tools, let emulator = running[avd.id] else { return }
        stopping.insert(avd.id)
        Task {
            await tools.stop(emulator)
            await refresh()
        }
    }
}
