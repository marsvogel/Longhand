//
//  TranscriptSegment.swift
//  Kladde
//

import Foundation

/// One timed span of speech, optionally tagged with a diarization speaker id
/// (`A`, `B`, …). Display names live on the entry / global defaults.
nonisolated struct TranscriptSegment: Identifiable, Codable, Sendable, Equatable {
    var id: String
    var start: Double
    var end: Double
    var text: String
    /// Stable diarization label from the model (`A`, `B`, …).
    var speaker: String

    init(
        start: Double,
        end: Double,
        text: String,
        speaker: String,
        id: String = UUID().uuidString
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
        self.speaker = speaker
    }
}

nonisolated enum TranscriptFormatting {
    /// Default visible label when the user has not renamed a speaker yet.
    static func defaultName(for speaker: String) -> String {
        "Speaker \(speaker)"
    }

    static func displayName(for speaker: String, names: [String: String]) -> String {
        let trimmed = names[speaker]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? defaultName(for: speaker) : trimmed
    }

    /// Merges consecutive segments of the same speaker into labeled blocks.
    static func labeledText(segments: [TranscriptSegment], names: [String: String]) -> String {
        guard !segments.isEmpty else {
            return ""
        }
        var blocks: [(speaker: String, text: String)] = []
        for segment in segments {
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                continue
            }
            if let last = blocks.last, last.speaker == segment.speaker {
                blocks[blocks.count - 1].text += " " + text
            } else {
                blocks.append((segment.speaker, text))
            }
        }
        if blocks.count == 1 {
            return blocks[0].text
        }
        return blocks
            .map { block in
                "**\(displayName(for: block.speaker, names: names)):** \(block.text)"
            }
            .joined(separator: "\n\n")
    }
}
