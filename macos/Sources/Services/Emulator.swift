import Foundation

/// A running emulator, found through the discovery file it writes while alive.
struct RunningEmulator: Sendable, Equatable {
    let avdID: String
    let serial: String
    let pid: Int32
}

enum EmulatorDiscovery {
    /// Each running emulator writes `pid_<pid>.ini` here and removes it on exit.
    static var runningDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Caches/TemporaryItems/avd/running", directoryHint: .isDirectory)
    }

    static func running(
        in directory: URL = runningDirectory,
        isAlive: (Int32) -> Bool = { kill($0, 0) == 0 }
    ) -> [RunningEmulator] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap { file in
            let name = file.deletingPathExtension().lastPathComponent
            guard file.pathExtension == "ini", name.hasPrefix("pid_"), let pid = Int32(name.dropFirst(4)),
                  // A crashed emulator leaves its file behind, so the process must still exist.
                  isAlive(pid),
                  let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
            let values = AVDCatalog.parseINI(text)
            guard let avdID = values["avd.id"], let port = values["port.serial"] else { return nil }
            return RunningEmulator(avdID: avdID, serial: "emulator-\(port)", pid: pid)
        }
    }
}

/// Launches and controls emulators using the SDK's `emulator` and `adb`.
struct EmulatorTools: Sendable {
    let emulator: URL
    let adb: URL
    let sdkRoot: URL

    init?(status: AndroidSDK.Status) {
        guard let emulator = status.emulator, let adb = status.adb, let sdkRoot = status.root else { return nil }
        self.emulator = emulator
        self.adb = adb
        self.sdkRoot = sdkRoot
    }

    static var logsDirectory: URL {
        URL.libraryDirectory.appending(path: "Logs/EmuDock", directoryHint: .isDirectory)
    }

    /// Starts the emulator in the background; it keeps running if EmuDock quits.
    /// `onFailure` is called with the emulator's error output if it exits unsuccessfully.
    func launch(_ avd: AVD, coldBoot: Bool, onFailure: @escaping @Sendable (String) -> Void) throws {
        try FileManager.default.createDirectory(at: Self.logsDirectory, withIntermediateDirectories: true)
        let logURL = Self.logsDirectory.appending(path: "\(avd.id).log")
        FileManager.default.createFile(atPath: logURL.path(percentEncoded: false), contents: nil)
        let log = try FileHandle(forWritingTo: logURL)

        let process = Process()
        process.executableURL = emulator
        process.arguments = ["-avd", avd.id] + (coldBoot ? ["-no-snapshot-load"] : [])
        let sdkPath = sdkRoot.path(percentEncoded: false)
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["ANDROID_HOME": sdkPath, "ANDROID_SDK_ROOT": sdkPath]
        ) { $1 }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = log
        process.standardError = log
        process.terminationHandler = { finished in
            try? log.close()
            guard finished.terminationStatus != 0 else { return }
            onFailure(Self.errorSummary(fromLog: logURL))
        }
        try process.run()
    }

    /// Asks the emulator to shut down, falling back to terminating its process.
    func stop(_ running: RunningEmulator) async {
        do {
            try await ProcessRunner.run(adb, arguments: ["-s", running.serial, "emu", "kill"])
        } catch {
            kill(running.pid, SIGTERM)
        }
    }

    func isBootCompleted(_ serial: String) async -> Bool {
        let lines = try? await ProcessRunner.run(adb, arguments: ["-s", serial, "shell", "getprop", "sys.boot_completed"])
        return lines?.last == "1"
    }

    /// The emulator's `ERROR` lines, or the end of its log if it printed none.
    static func errorSummary(fromLog logURL: URL) -> String {
        let lines = ((try? String(contentsOf: logURL, encoding: .utf8)) ?? "")
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        let errors = lines.filter { $0.contains("ERROR") || $0.contains("FATAL") }
        return (errors.isEmpty ? Array(lines.suffix(6)) : errors).joined(separator: "\n")
    }
}
