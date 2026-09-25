import Foundation
import Observation

/// Runs the one-click setup: Java, command-line tools, licenses, emulator tools, system image.
/// Steps whose pieces are already installed are skipped, so it also repairs a partial SDK.
@MainActor
@Observable
final class SetupModel {
    enum StepID: CaseIterable {
        case java, commandLineTools, licenses, emulatorTools, systemImage

        var title: String {
            switch self {
            case .java: "Java runtime"
            case .commandLineTools: "Android command-line tools"
            case .licenses: "SDK licenses"
            case .emulatorTools: "Emulator & platform tools"
            case .systemImage: "Android system image"
            }
        }
    }

    enum StepState: Equatable {
        case pending
        case running(fraction: Double?, detail: String)
        case done(String)
        case skipped(String)
        case failed(String)
    }

    struct Step: Identifiable {
        let id: StepID
        var state: StepState = .pending
    }

    private(set) var steps = StepID.allCases.map { Step(id: $0) }
    private(set) var isRunning = false
    var licensesAccepted = false
    private var task: Task<Void, Never>?

    var hasFailed: Bool {
        steps.contains { if case .failed = $0.state { true } else { false } }
    }

    func start(using sdk: SDKStatusModel) {
        guard !isRunning else { return }
        isRunning = true
        steps = StepID.allCases.map { Step(id: $0) }
        task = Task {
            await sdk.refresh()
            if let status = sdk.status {
                await run(from: status)
            }
            isRunning = false
            await sdk.refresh()
        }
    }

    func cancel() {
        task?.cancel()
    }

    private func run(from status: AndroidSDK.Status) async {
        let sdkRoot = status.root ?? AndroidSDK.defaultRoot
        var current = StepID.java
        do {
            let javaHome: URL
            if let existing = status.javaHome {
                javaHome = existing
                set(.java, .skipped("Using \(existing.path(percentEncoded: false))"))
            } else {
                begin(.java)
                javaHome = try await JavaRuntime.install(progress: reporter(for: .java))
                set(.java, .done("Installed Temurin 21"))
            }

            current = .commandLineTools
            if status.sdkmanager != nil {
                set(.commandLineTools, .skipped("Already installed"))
            } else {
                begin(.commandLineTools)
                try await CommandLineTools.install(into: sdkRoot, progress: reporter(for: .commandLineTools))
                set(.commandLineTools, .done("Installed to \(sdkRoot.path(percentEncoded: false))"))
            }

            let manager = SDKManager(executable: AndroidSDK.sdkmanager(in: sdkRoot), sdkRoot: sdkRoot, javaHome: javaHome)

            current = .licenses
            begin(.licenses)
            try await manager.acceptLicenses()
            set(.licenses, .done("Accepted"))

            current = .emulatorTools
            let missing = [("platform-tools", status.adb), ("emulator", status.emulator)]
                .filter { $0.1 == nil }
                .map(\.0)
            if missing.isEmpty {
                set(.emulatorTools, .skipped("Already installed"))
            } else {
                begin(.emulatorTools)
                try await manager.install(missing, progress: reporter(for: .emulatorTools))
                set(.emulatorTools, .done("Installed \(missing.joined(separator: " and "))"))
            }

            current = .systemImage
            if let existing = status.systemImages.last {
                set(.systemImage, .skipped("Already have \(existing)"))
            } else {
                set(.systemImage, .running(fraction: nil, detail: "Finding the latest Android version"))
                guard let image = SDKManager.recommendedSystemImage(in: try await manager.listPackages()) else {
                    throw SetupError.noSystemImage
                }
                try await manager.install([image], progress: reporter(for: .systemImage))
                set(.systemImage, .done("Installed \(image)"))
            }
        } catch is CancellationError {
            set(current, .failed("Cancelled"))
        } catch {
            set(current, .failed(error.localizedDescription))
        }
    }

    enum SetupError: LocalizedError {
        case noSystemImage

        var errorDescription: String? {
            "Couldn't find a Google Play system image for this Mac."
        }
    }

    // MARK: - State updates

    private func begin(_ id: StepID) {
        set(id, .running(fraction: nil, detail: "Starting"))
    }

    private func set(_ id: StepID, _ state: StepState) {
        guard let index = steps.firstIndex(where: { $0.id == id }) else { return }
        steps[index].state = state
    }

    /// Progress arrives from background threads; updates that land after the step
    /// has finished are dropped so they can't flip it back to running.
    private func reporter(for id: StepID) -> StepProgress {
        { [weak self] fraction, detail in
            Task { @MainActor in
                guard let self, let index = self.steps.firstIndex(where: { $0.id == id }),
                      case .running = self.steps[index].state else { return }
                self.steps[index].state = .running(fraction: fraction, detail: detail)
            }
        }
    }
}
