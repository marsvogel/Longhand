//
//  DictationArchive.swift
//  Kladde
//
//  The on-disk form of the dictation list: entries.json plus the recordings
//  beside it. The store decides *when* to read and write; this decides *how*,
//  so no JSON coder or FileManager call is left in the model layer.
//

import Foundation

nonisolated enum DictationArchive {
    /// The persisted entries, or none on a first launch. An unreadable file is
    /// never overwritten with an empty list — it is moved aside so its contents
    /// stay recoverable.
    static func load() -> [DictationEntry] {
        guard let data = try? Data(contentsOf: AppLocations.entriesFile) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let entries = try? decoder.decode([DictationEntry].self, from: data) {
            return entries
        }
        let backup = AppLocations.entriesFile.appendingPathExtension("corrupt")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.moveItem(at: AppLocations.entriesFile, to: backup)
        return []
    }

    /// Writes the entries atomically, so an interrupted write can never
    /// truncate the list. Failures stay silent by design: persistence must not
    /// interrupt a dictation in progress.
    static func save(_ entries: [DictationEntry]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entries) else {
            return
        }
        try? data.write(to: AppLocations.entriesFile, options: .atomic)
    }

    /// Deletes a dictation's recording; a missing file is not an error.
    static func removeRecording(for id: DictationEntry.ID) {
        try? FileManager.default.removeItem(at: AppLocations.recordingURL(for: id))
    }

    /// Whether a dictation's audio is on disk — false while it is still being
    /// recorded, and for entries whose file a previous launch never wrote.
    static func hasRecording(for id: DictationEntry.ID) -> Bool {
        FileManager.default.fileExists(atPath: AppLocations.recordingURL(for: id).path)
    }
}
