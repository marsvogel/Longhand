// WhisperTranscriber.swift
// Longhand

import CWhisper
import Foundation

/// Runs whisper.cpp inference. An actor because the whisper context must
/// never be used from more than one thread at a time.
actor WhisperTranscriber {
    nonisolated enum TranscriptionError: LocalizedError {
        case modelLoadFailed(URL)
        case audioUnreadable(URL, String)
        case whisperFailed(Int32)

        var errorDescription: String? {
            switch self {
            case let .modelLoadFailed(url):
                "Could not load the transcription model \(url.lastPathComponent)."

            case let .audioUnreadable(url, reason):
                "Could not read \(url.lastPathComponent): \(reason)"

            case let .whisperFailed(status):
                "Transcription failed (whisper error \(status))."
            }
        }
    }

    private var context: OpaquePointer?
    private var loadedModelURL: URL?
    /// True once the loaded context has run any inference; a warmup pass
    /// adds nothing after that.
    private var hasRunInference = false

    /// whisper.cpp and its ggml/Metal backend print their model-load and
    /// device chatter straight to stderr on every context init. Route both
    /// log streams to a sink so the console stays clean. Referenced from
    /// `loadContext`, this static let runs its body exactly once, before the
    /// first `whisper_init`.
    private static let silenceNativeLogging: Void = {
        let sink: @convention(c) (
            ggml_log_level, UnsafePointer<CChar>?, UnsafeMutableRawPointer?
        ) -> Void = { _, _, _ in }
        whisper_log_set(sink, nil)
        ggml_log_set(sink, nil)
    }()

    /// Loads the context ahead of time and runs one second of silence
    /// through it so the first real transcription starts at steady-state
    /// speed; the silence pass absorbs the Metal first-run penalty (~1 s,
    /// several seconds more on a cold shader cache). Runs at most once per
    /// loaded context, never concurrently with `transcribe` (actor
    /// isolation), and does nothing while the model file is not on disk.
    func warmUp(modelURL: URL) async {
        guard FileManager.default.fileExists(atPath: modelURL.path),
              let context = try? loadContext(for: modelURL),
              !hasRunInference
        else { return }
        hasRunInference = true
        let silence = [Float](repeating: 0, count: 16_000)
        _ = runInference(context, samples: silence)
    }

    func transcribe(audioURL: URL, modelURL: URL) async throws -> String {
        let context = try loadContext(for: modelURL)
        let samples = try Self.samples(from: audioURL)

        let status = runInference(context, samples: samples)
        hasRunInference = true
        guard status == 0 else {
            throw TranscriptionError.whisperFailed(status)
        }

        var transcript = ""
        for segment in 0..<whisper_full_n_segments(context) {
            transcript += String(cString: whisper_full_get_segment_text(context, segment))
        }
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runInference(_ context: OpaquePointer, samples: [Float]) -> Int32 {
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        // Leave 2 processors free (i.e. the high-efficiency cores).
        params.n_threads = Int32(max(1, min(8, ProcessInfo.processInfo.processorCount - 2)))

        // A fixed language skips whisper's language-detection pass — an extra
        // full encoder run over the first window whose only output is the
        // language guess, then thrown away before the real transcription
        // encodes the same window again. Dictation is German, so pin it.
        return "de".withCString { language -> Int32 in
            // Borrowed pointer; whisper_full must run within this scope.
            params.language = language
            return samples.withUnsafeBufferPointer { buffer in
                whisper_full(context, params, buffer.baseAddress, Int32(buffer.count))
            }
        }
    }

    /// Creates the whisper context on first use and keeps it for subsequent
    /// transcriptions; reloads only if the model file changes.
    private func loadContext(for modelURL: URL) throws -> OpaquePointer {
        _ = Self.silenceNativeLogging
        if let context, loadedModelURL == modelURL {
            return context
        }
        if let context {
            whisper_free(context)
            self.context = nil
            loadedModelURL = nil
        }
        hasRunInference = false
        let params = whisper_context_default_params()
        guard let context = whisper_init_from_file_with_params(modelURL.path, params) else {
            throw TranscriptionError.modelLoadFailed(modelURL)
        }
        self.context = context
        loadedModelURL = modelURL
        return context
    }

    /// The recording as the mono Float32 samples whisper expects, with the
    /// shared read's failure reason folded into a transcription error.
    nonisolated private static func samples(from url: URL) throws -> [Float] {
        do {
            return try AudioSamples.withSamples(from: url) { Array($0) }
        } catch {
            let reason = (error as? AudioSamples.ReadError)?.reason ?? error.localizedDescription
            throw TranscriptionError.audioUnreadable(url, reason)
        }
    }

    deinit {
        if let context {
            whisper_free(context)
        }
    }
}
