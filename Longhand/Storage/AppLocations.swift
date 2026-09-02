//
//  AppLocations.swift
//  Longhand
//

import Foundation

/// Well-known file locations under ~/Library/Application Support/Longhand.
/// Directories are created lazily on first access.
nonisolated enum AppLocations {
    static var supportDirectory: URL {
        directory(URL.applicationSupportDirectory.appending(path: "Longhand", directoryHint: .isDirectory))
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
