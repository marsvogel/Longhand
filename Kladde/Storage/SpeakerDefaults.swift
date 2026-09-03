//
//  SpeakerDefaults.swift
//  Kladde
//
//  Last-used display names for diarization labels (A/B/…), so renaming
//  "Speaker A" → "Dimitri" sticks for the next recording.
//

import Foundation

nonisolated enum SpeakerDefaults {
    static func load() -> [String: String] {
        guard let data = try? Data(contentsOf: AppLocations.speakerNamesFile),
              let names = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return [:]
        }
        return names
    }

    static func save(_ names: [String: String]) {
        let trimmed = names.reduce(into: [String: String]()) { result, item in
            let value = item.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                result[item.key] = value
            }
        }
        guard let data = try? JSONEncoder().encode(trimmed) else {
            return
        }
        try? data.write(to: AppLocations.speakerNamesFile, options: .atomic)
    }

    static func merge(into names: inout [String: String]) {
        for (key, value) in load() where names[key] == nil {
            names[key] = value
        }
    }
}
