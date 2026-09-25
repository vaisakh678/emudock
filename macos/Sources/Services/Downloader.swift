import CryptoKit
import Foundation

/// Downloads a file to disk, reporting byte progress.
final class Downloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    enum DownloadError: LocalizedError {
        case httpStatus(Int, URL)
        case checksumMismatch(String)

        var errorDescription: String? {
            switch self {
            case let .httpStatus(code, url):
                "Download of \(url.lastPathComponent) failed (HTTP \(code))."
            case let .checksumMismatch(file):
                "\(file) is corrupted (checksum mismatch). Try again."
            }
        }
    }

    /// Received bytes and total bytes (total is -1 when the server doesn't say).
    typealias Progress = @Sendable (_ received: Int64, _ total: Int64) -> Void

    private let destination: URL
    private let progress: Progress
    private var continuation: CheckedContinuation<Void, Error>?
    private var moveError: Error?
    private var lastReported: Int64 = 0

    private init(destination: URL, progress: @escaping Progress) {
        self.destination = destination
        self.progress = progress
    }

    static func download(from url: URL, to destination: URL, progress: @escaping Progress) async throws {
        let downloader = Downloader(destination: destination, progress: progress)
        // Delegate callbacks arrive on one serial queue, so the downloader's state needs no lock.
        let session = URLSession(configuration: .default, delegate: downloader, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                downloader.continuation = continuation
                session.downloadTask(with: url).resume()
            }
        } onCancel: {
            session.invalidateAndCancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        // Report roughly every 1 MB rather than for every network chunk.
        guard totalBytesWritten - lastReported >= 1 << 20 || totalBytesWritten == totalBytesExpectedToWrite else { return }
        lastReported = totalBytesWritten
        progress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // `location` is deleted when this method returns, so it has to be moved now.
        guard let status = (downloadTask.response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else { return }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            moveError = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let result: Result<Void, Error>
        if let error {
            result = .failure((error as? URLError)?.code == .cancelled ? CancellationError() : error)
        } else if let status = (task.response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
            result = .failure(DownloadError.httpStatus(status, task.originalRequest?.url ?? destination))
        } else if let moveError {
            result = .failure(moveError)
        } else {
            result = .success(())
        }
        continuation?.resume(with: result)
        continuation = nil
    }
}

enum Checksum {
    /// Hashes `file` in chunks and throws if it doesn't match the expected hex digest.
    static func verify<H: HashFunction>(_ file: URL, matches expectedHex: String, using _: H.Type) throws {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = H()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        let actual = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == expectedHex.lowercased() else {
            throw Downloader.DownloadError.checksumMismatch(file.lastPathComponent)
        }
    }
}

enum Archive {
    static func unzip(_ file: URL, into directory: URL) async throws {
        try await ProcessRunner.run(
            URL(filePath: "/usr/bin/ditto"),
            arguments: ["-x", "-k", file.path(percentEncoded: false), directory.path(percentEncoded: false)]
        )
    }

    static func untar(_ file: URL, into directory: URL) async throws {
        try await ProcessRunner.run(
            URL(filePath: "/usr/bin/tar"),
            arguments: ["-xzf", file.path(percentEncoded: false), "-C", directory.path(percentEncoded: false)]
        )
    }
}

/// Progress callback for a setup step: a fraction in 0...1 (nil when unknown) and a status line.
typealias StepProgress = @Sendable (_ fraction: Double?, _ detail: String) -> Void

extension Downloader {
    /// Adapts byte progress into a step progress line like "Downloading 12 MB of 150 MB".
    static func reporting(to progress: @escaping StepProgress) -> Progress {
        { received, total in
            let done = received.formatted(.byteCount(style: .file))
            if total > 0 {
                progress(Double(received) / Double(total), "Downloading \(done) of \(total.formatted(.byteCount(style: .file)))")
            } else {
                progress(nil, "Downloading \(done)")
            }
        }
    }
}
