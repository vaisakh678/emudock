import Foundation

/// Runs a command-line tool, streaming its output line by line.
enum ProcessRunner {
    struct Failure: LocalizedError {
        let command: String
        let status: Int32
        let output: [String]

        var errorDescription: String? {
            let tail = output.suffix(12).joined(separator: "\n")
            return "\(command) failed (exit code \(status)).\n\(tail)"
        }
    }

    /// Writing to the stdin of a process that has already exited raises SIGPIPE,
    /// which would kill the app. Ignored once so the write fails with EPIPE instead.
    private static let ignoreSIGPIPE: Void = { signal(SIGPIPE, SIG_IGN) }()

    /// Runs `executable` and returns every output line (stdout and stderr merged).
    /// Lines are split on both `\n` and `\r`, so progress bars redrawn with `\r`
    /// arrive as separate lines through `onLine`.
    @discardableResult
    static func run(
        _ executable: URL,
        arguments: [String] = [],
        environment: [String: String] = [:],
        input: String? = nil,
        onLine: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws -> [String] {
        _ = ignoreSIGPIPE
        try Task.checkCancellation()

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        let stdin = Pipe()
        process.standardInput = input == nil ? FileHandle.nullDevice : stdin

        let collector = LineCollector(onLine: onLine)
        let reader = output.fileHandleForReading
        reader.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                collector.append(data)
            }
        }

        let handle = ProcessHandle(process)
        let status: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { finished in
                    reader.readabilityHandler = nil
                    collector.append(reader.readDataToEndOfFile())
                    collector.finish()
                    continuation.resume(returning: finished.terminationStatus)
                }
                do {
                    try process.run()
                } catch {
                    reader.readabilityHandler = nil
                    continuation.resume(throwing: error)
                    return
                }
                if let input {
                    try? stdin.fileHandleForWriting.write(contentsOf: Data(input.utf8))
                    try? stdin.fileHandleForWriting.close()
                }
            }
        } onCancel: {
            handle.terminate()
        }

        try Task.checkCancellation()
        let lines = collector.lines
        guard status == 0 else {
            throw Failure(command: executable.lastPathComponent, status: status, output: lines)
        }
        return lines
    }
}

/// Lets the cancellation handler, which may run on any thread, stop the process.
private final class ProcessHandle: @unchecked Sendable {
    private let process: Process

    init(_ process: Process) {
        self.process = process
    }

    func terminate() {
        if process.isRunning { process.terminate() }
    }
}

/// Buffers raw pipe output and emits complete, non-empty lines.
private final class LineCollector: @unchecked Sendable {
    private let lock = NSLock()
    private let onLine: @Sendable (String) -> Void
    private var pending = Data()
    private var collected: [String] = []

    init(onLine: @escaping @Sendable (String) -> Void) {
        self.onLine = onLine
    }

    var lines: [String] {
        lock.withLock { collected }
    }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.withLock {
            pending.append(data)
            while let end = pending.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
                emit(pending[pending.startIndex..<end])
                pending.removeSubrange(pending.startIndex...end)
            }
        }
    }

    func finish() {
        lock.withLock {
            emit(pending)
            pending.removeAll()
        }
    }

    private func emit(_ bytes: Data) {
        let line = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return }
        collected.append(line)
        onLine(line)
    }
}
