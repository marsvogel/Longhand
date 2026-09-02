// ModelDownloadManager.swift
// Longhand

import Foundation
import Observation

/// Downloads the two transcription assets — the ggml weights and the Core ML
/// encoder bundle — into Application Support and publishes their availability
/// to the UI and the transcription pipeline. whisper.cpp loads the encoder
/// through Core ML when the bundle sits next to the weights, and otherwise
/// logs a load failure and falls back to Metal; keeping both on disk avoids
/// that and runs the encoder on the ANE.
@MainActor
@Observable
final class ModelDownloadManager {
    enum State: Equatable {
        case idle
        case downloading(Double)
        case failed(String)
        case ready
    }

    private(set) var state: State = .idle {
        didSet {
            guard state == .ready, !readyWaiters.isEmpty else {
                return
            }
            let waiters = readyWaiters
            readyWaiters = [:]
            for continuation in waiters.values {
                continuation.resume()
            }
        }
    }

    /// Continuations suspended in `waitUntilReady`, keyed for removal on
    /// task cancellation.
    @ObservationIgnored private var readyWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    nonisolated static let expectedModelSize: Int64 = 1_624_555_275
    nonisolated static let expectedCoreMLZipSize: Int64 = 1_173_393_014

    /// "ggml" file magic (0x67676d6c) as stored on disk, little-endian.
    nonisolated private static let ggmlMagic: [UInt8] = [0x6C, 0x6D, 0x67, 0x67]

    nonisolated private static let modelSource = URL(
        string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin"
    )!
    nonisolated private static let coreMLSource = URL(
        string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-encoder.mlmodelc.zip"
    )!

    /// The download session for whichever asset is in flight; retained so it
    /// stays alive until its delegate concludes, then invalidated.
    private var session: URLSession?

    /// The unpacked Core ML bundle exists and carries its compiled payload. A
    /// `.mlmodelc` always contains `coremldata.bin`, so its presence marks a
    /// complete, usable bundle rather than a half-written directory.
    nonisolated fileprivate static var coreMLEncoderPresent: Bool {
        let bundle = AppLocations.coreMLEncoderFile
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: bundle.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return false }
        return FileManager.default.fileExists(atPath: bundle.appending(path: "coremldata.bin").path)
    }

    init() {
        let modelFile = AppLocations.whisperModelFile
        if FileManager.default.fileExists(atPath: modelFile.path), !Self.isValidModelFile(at: modelFile) {
            try? FileManager.default.removeItem(at: modelFile)
        }
        if Self.isValidModelFile(at: modelFile), Self.coreMLEncoderPresent {
            state = .ready
        }
    }

    /// Previews only: fixed state, no filesystem access.
    init(state: State) {
        self.state = state
    }

    func start() {
        switch state {
        case .downloading, .ready:
            return

        case .idle, .failed:
            break
        }
        state = .downloading(0)
        Task { await installAssets() }
    }

    /// Suspends until both assets are on disk. Deliberately keeps waiting
    /// through `.failed`: the UI offers a retry, and pending transcriptions
    /// resume once a later attempt succeeds. Returns early only on task
    /// cancellation.
    func waitUntilReady() async {
        if state == .ready {
            return
        }
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if state == .ready || Task.isCancelled {
                    continuation.resume()
                } else {
                    readyWaiters[id] = continuation
                }
            }
        } onCancel: {
            Task { @MainActor in
                self.readyWaiters.removeValue(forKey: id)?.resume()
            }
        }
    }

    /// Fetches whichever assets are missing, weights first, reporting one
    /// combined progress bar weighted by their byte sizes so the bar sweeps
    /// 0…1 across both downloads rather than resetting between them.
    private func installAssets() async {
        let needsWeights = !Self.isValidModelFile(at: AppLocations.whisperModelFile)
        let needsCoreML = !Self.coreMLEncoderPresent
        let totalBytes = (needsWeights ? Self.expectedModelSize : 0)
            + (needsCoreML ? Self.expectedCoreMLZipSize : 0)
        guard totalBytes > 0 else {
            state = .ready
            return
        }

        var completedBytes: Int64 = 0
        if needsWeights {
            if let error = await download(
                Self.modelSource,
                expectedSize: Self.expectedModelSize,
                completedBytes: completedBytes,
                totalBytes: totalBytes,
                install: { Self.installWeights(from: $0) }
            ) {
                state = .failed(error)
                return
            }
            completedBytes += Self.expectedModelSize
        }
        if needsCoreML {
            if let error = await download(
                Self.coreMLSource,
                expectedSize: Self.expectedCoreMLZipSize,
                completedBytes: completedBytes,
                totalBytes: totalBytes,
                install: { Self.installCoreML(from: $0) }
            ) {
                state = .failed(error)
                return
            }
        }
        state = .ready
    }

    /// Runs one asset download to completion and returns an error message, or
    /// nil on success. `completedBytes`/`totalBytes` position this download's
    /// progress within the combined bar.
    private func download(
        _ url: URL,
        expectedSize: Int64,
        completedBytes: Int64,
        totalBytes: Int64,
        install: @escaping @Sendable (URL) -> String?
    ) async -> String? {
        let errorMessage = await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let delegate = ModelDownloadDelegate(
                expectedSize: expectedSize,
                install: install,
                onProgress: { bytesWritten in
                    Task { @MainActor in
                        self.updateProgress(Double(completedBytes + bytesWritten) / Double(totalBytes))
                    }
                },
                onCompletion: { continuation.resume(returning: $0) }
            )
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            self.session = session
            session.downloadTask(with: url).resume()
        }
        // Back on the main actor once the download concludes: tear the session
        // down before the next asset reuses the slot.
        session?.finishTasksAndInvalidate()
        session = nil
        return errorMessage
    }

    private func updateProgress(_ fraction: Double) {
        if case .downloading = state {
            state = .downloading(min(1, fraction))
        }
    }

    /// A complete weights file has the exact published size and starts with the
    /// ggml magic; anything else is a partial or bogus download.
    nonisolated fileprivate static func isValidModelFile(at url: URL) -> Bool {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes?[.size] as? Int64 == expectedModelSize,
              let handle = try? FileHandle(forReadingFrom: url)
        else { return false }
        defer { try? handle.close() }
        guard let magic = try? handle.read(upToCount: 4) else {
            return false
        }
        return [UInt8](magic) == ggmlMagic
    }

    /// Validates the finished weights download and moves it into place.
    nonisolated private static func installWeights(from location: URL) -> String? {
        guard isValidModelFile(at: location) else {
            return "The downloaded file is not a valid transcription model."
        }
        let destination = AppLocations.whisperModelFile
        do {
            try FileManager.default.removeItem(at: destination)
        } catch CocoaError.fileNoSuchFile {
            // Nothing to remove; proceed.
        } catch {
            return error.localizedDescription
        }
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Validates the finished Core ML archive and unpacks it next to the
    /// weights. The `.mlmodelc` sits at the archive's top level, so extracting
    /// into the Models directory yields the bundle whisper.cpp looks for.
    nonisolated private static func installCoreML(from location: URL) -> String? {
        let size = (try? FileManager.default.attributesOfItem(atPath: location.path))?[.size] as? Int64
        guard size == expectedCoreMLZipSize else {
            return "The downloaded Core ML model is incomplete."
        }
        let destination = AppLocations.coreMLEncoderFile
        try? FileManager.default.removeItem(at: destination)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", location.path, AppLocations.modelsDirectory.path]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return error.localizedDescription
        }
        guard process.terminationStatus == 0 else {
            return "Could not unpack the Core ML model."
        }
        guard coreMLEncoderPresent else {
            return "The Core ML model is missing files after unpacking."
        }
        return nil
    }
}

/// Session delegate for one asset download. Callbacks arrive on the session's
/// serial delegate queue; all mutable state stays confined to that queue.
nonisolated private final class ModelDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let expectedSize: Int64
    private let install: @Sendable (URL) -> String?
    private let onProgress: @Sendable (_ bytesWritten: Int64) -> Void
    private let onCompletion: @Sendable (_ errorMessage: String?) -> Void

    private var lastProgressReport: ContinuousClock.Instant?
    private var hasConcluded = false

    init(
        expectedSize: Int64,
        install: @escaping @Sendable (URL) -> String?,
        onProgress: @escaping @Sendable (_ bytesWritten: Int64) -> Void,
        onCompletion: @escaping @Sendable (_ errorMessage: String?) -> Void
    ) {
        self.expectedSize = expectedSize
        self.install = install
        self.onProgress = onProgress
        self.onCompletion = onCompletion
    }

    func urlSession(
        _: URLSession,
        downloadTask _: URLSessionDownloadTask,
        didWriteData _: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite _: Int64
    ) {
        let now = ContinuousClock.now
        if let lastProgressReport, now - lastProgressReport < .milliseconds(100) {
            return
        }
        lastProgressReport = now
        onProgress(min(totalBytesWritten, expectedSize))
    }

    func urlSession(
        _: URLSession,
        downloadTask _: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // The temporary file only survives this callback; install it now.
        conclude(install(location))
    }

    func urlSession(_: URLSession, task _: URLSessionTask, didCompleteWithError error: (any Error)?) {
        // A nil error follows didFinishDownloadingTo, which already concluded.
        guard let error else {
            return
        }
        conclude(error.localizedDescription)
    }

    private func conclude(_ errorMessage: String?) {
        guard !hasConcluded else {
            return
        }
        hasConcluded = true
        onCompletion(errorMessage)
    }
}
