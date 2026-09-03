//
//  DictationEntry.swift
//  Kladde
//

import Foundation

/// One dictation: the recording plus everything derived from it.
nonisolated struct DictationEntry: Identifiable, Codable {
    /// Where the entry currently is in the audio → transcript → rewrite pipeline.
    enum Status: String, Codable {
        case recording = "recording"
        case transcribing = "transcribing"
        case generatingVariants = "generatingVariants"
        case complete = "complete"
        case transcriptionFailed = "transcriptionFailed"
    }

    var id = UUID()
    var title: String
    var createdAt: Date
    var duration: TimeInterval?
    var status: Status
    /// Flat transcript for sidebar / copy fallback. Prefer `segments` when present.
    var transcript: String?
    /// Speaker-labeled spans from diarization (or a single Whisper span).
    var segments: [TranscriptSegment]?
    /// Display names for diarization labels on this entry (`A` → "Dimitri").
    var speakerNames: [String: String] = [:]
    /// The transcript rewritten into written language.
    var cleanedUp: String?
    var waveformSeed: Double = 7
    var transcriptionError: String?
    var cleanedUpError: String?
    /// Bucketed peak levels of the recording, 0…1; nil falls back to the seed formula.
    var waveform: [Float]?
    /// Rewrite text streamed in while the final text is still being written.
    /// Transient — cleared the moment the final text lands and never encoded,
    /// so a crash mid-stream can never leave a half-written rewrite on disk.
    var cleanedUpDraft: String?

    /// Everything except `cleanedUpDraft`, which is a live-stream scratch value
    /// that must not be persisted.
    private enum CodingKeys: String, CodingKey {
        case id = "id"
        case title = "title"
        case createdAt = "createdAt"
        case duration = "duration"
        case status = "status"
        case transcript = "transcript"
        case segments = "segments"
        case speakerNames = "speakerNames"
        case cleanedUp = "cleanedUp"
        case waveformSeed = "waveformSeed"
        case transcriptionError = "transcriptionError"
        case cleanedUpError = "cleanedUpError"
        case waveform = "waveform"
    }

    var audioURL: URL { AppLocations.recordingURL(for: id) }

    var durationText: String? {
        duration.map { Duration.seconds($0).formatted(.time(pattern: .minuteSecond)) }
    }

    /// Text shown in the transcript card / sent to rewrite agents.
    var labeledTranscript: String? {
        if let segments, !segments.isEmpty {
            let text = TranscriptFormatting.labeledText(segments: segments, names: speakerNames)
            return text.isEmpty ? nil : text
        }
        return transcript
    }

    var uniqueSpeakers: [String] {
        let fromSegments = segments?.map(\.speaker) ?? []
        return Array(Set(fromSegments)).sorted()
    }
}

// MARK: - Decoding

nonisolated extension DictationEntry {
    /// The shape earlier builds persisted: rewrites lived in maps keyed by a
    /// variant name, e.g. `"variants": {"cleanedUp": "…"}`.
    private enum LegacyKeys: String, CodingKey {
        case variants = "variants"
        case variantErrors = "variantErrors"
    }

    /// Hand-written decode (in an extension, so the memberwise initialiser
    /// survives) for two reasons: entries persisted by earlier builds keep
    /// loading through the legacy fallback — the next persist writes them
    /// back in today's flat shape — and `cleanedUpDraft` starts empty instead
    /// of decoding. `encode(to:)` stays synthesised.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
        status = try container.decode(Status.self, forKey: .status)
        transcript = try container.decodeIfPresent(String.self, forKey: .transcript)
        segments = try container.decodeIfPresent([TranscriptSegment].self, forKey: .segments)
        speakerNames = try container.decodeIfPresent([String: String].self, forKey: .speakerNames) ?? [:]
        cleanedUp = try container.decodeIfPresent(String.self, forKey: .cleanedUp)
            ?? legacy.decodeIfPresent([String: String].self, forKey: .variants)?["cleanedUp"]
        waveformSeed = try container.decodeIfPresent(Double.self, forKey: .waveformSeed) ?? 7
        transcriptionError = try container.decodeIfPresent(String.self, forKey: .transcriptionError)
        cleanedUpError = try container.decodeIfPresent(String.self, forKey: .cleanedUpError)
            ?? legacy.decodeIfPresent([String: String].self, forKey: .variantErrors)?["cleanedUp"]
        waveform = try container.decodeIfPresent([Float].self, forKey: .waveform)
        cleanedUpDraft = nil
    }
}
