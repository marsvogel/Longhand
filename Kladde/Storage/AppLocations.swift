//
//  AppLocations.swift
//  Kladde
//

import Foundation

/// Well-known file locations under ~/Library/Application Support/Kladde.
/// Directories are created lazily on first access.
nonisolated enum AppLocations {
    /// The app stored everything under its former name, Longhand, until the
    /// rename. Moving the directory over — recordings, transcripts, and the
    /// 2.8 GB model alike — keeps a rename from looking like data loss.
    /// Referenced from `supportDirectory`, this runs once per launch, and
    /// before anything creates the new directory.
    private static let migrateLegacyDirectory: Void = {
        let manager = FileManager.default
        let legacy = URL.applicationSupportDirectory
            .appending(path: "Longhand", directoryHint: .isDirectory)
        let current = URL.applicationSupportDirectory
            .appending(path: "Kladde", directoryHint: .isDirectory)
        guard manager.fileExists(atPath: legacy.path),
              !manager.fileExists(atPath: current.path)
        else { return }
        try? manager.moveItem(at: legacy, to: current)
    }()

    static var supportDirectory: URL {
        _ = migrateLegacyDirectory
        return directory(
            URL.applicationSupportDirectory.appending(path: "Kladde", directoryHint: .isDirectory)
        )
    }

    static var recordingsDirectory: URL {
        directory(supportDirectory.appending(path: "Recordings", directoryHint: .isDirectory))
    }

    static var modelsDirectory: URL {
        directory(supportDirectory.appending(path: "Models", directoryHint: .isDirectory))
    }

    static var entriesFile: URL {
        supportDirectory.appending(path: "entries.json")
    }

    /// One-line CHECK24 LLM Proxy API key (not committed; lives only here).
    static var llmProxyAPIKeyFile: URL {
        supportDirectory.appending(path: "llm-proxy-api-key")
    }

    /// Persisted display names for diarization labels (`A` → "Dimitri").
    static var speakerNamesFile: URL {
        supportDirectory.appending(path: "speaker-names.json")
    }

    static var whisperModelFile: URL {
        modelsDirectory.appending(path: "ggml-large-v3-turbo.bin")
    }

    /// The Core ML encoder bundle whisper.cpp loads alongside the weights.
    /// whisper derives this exact name from the weights file (`<base>-encoder
    /// .mlmodelc`); when present it runs the encoder through Core ML instead of
    /// logging a load failure and falling back to Metal.
    static var coreMLEncoderFile: URL {
        modelsDirectory.appending(path: "ggml-large-v3-turbo-encoder.mlmodelc", directoryHint: .isDirectory)
    }

    static func recordingURL(for id: UUID) -> URL {
        recordingsDirectory.appending(path: "\(id.uuidString).wav")
    }

    private static func directory(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
