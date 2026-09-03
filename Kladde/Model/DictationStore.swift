//
//  DictationStore.swift
//  Kladde
//
//  The observable state object behind the main window. Views render its
//  published state and call its intent methods; they never mutate entries
//  directly. The store drives the real pipeline: record → transcribe with
//  whisper → rewrite via CHECK24 LLM Proxy, persisting after every mutation.
//  While the user speaks it pre-warms the whisper context so model load never
//  lands in the wait after the recording stops.
//
//  It orchestrates, it does not implement: capture lives in DictationRecorder,
//  inference in WhisperTranscriber, rewriting in LLMProxyClient, and
//  reading and writing the list in DictationArchive.
//

import SwiftUI

@MainActor
@Observable
final class DictationStore {
    private(set) var entries: [DictationEntry]
    /// Set when the user declined microphone access; ContentView presents it.
    var micPermissionDenied = false
    /// Set when the recorder could not start; ContentView presents it.
    var recordingError: String?

    let recorder = DictationRecorder()
    let modelDownload: ModelDownloadManager

    private let transcriber = WhisperTranscriber()
    private let persistsToDisk: Bool

    private static let newDictationTitle = "New Dictation"

    /// The dictation currently being recorded — at most one at a time, since
    /// `startDictation` refuses to begin a second one. Private: callers that
    /// hold no entry stop through `stopRecording()`.
    private var recordingID: DictationEntry.ID? {
        entries.first { $0.status == .recording }?.id
    }

    var isRecording: Bool {
        recordingID != nil
    }

    /// In-memory store for previews: no persistence, model treated as ready,
    /// and never any pre-warming.
    init(entries: [DictationEntry] = []) {
        self.entries = entries
        self.modelDownload = ModelDownloadManager(state: .ready)
        self.persistsToDisk = false
    }

    private init(entries: [DictationEntry], modelDownload: ModelDownloadManager) {
        self.entries = entries
        self.modelDownload = modelDownload
        self.persistsToDisk = true
    }

    /// The store used by the app: loads persisted entries and resumes work
    /// that a previous launch left unfinished.
    static func live(modelDownload: ModelDownloadManager) -> DictationStore {
        let store = DictationStore(entries: DictationArchive.load(), modelDownload: modelDownload)
        store.recoverInterruptedEntries()
        store.prearmRecorder()
        return store
    }

    // MARK: - Intents

    @discardableResult
    func startDictation() async -> DictationEntry.ID? {
        guard !isRecording else {
            return nil
        }
        // Fast path: when access is already granted the async request — and
        // its suspension — is skipped entirely.
        if !DictationRecorder.permissionGranted {
            guard await recorder.requestPermission() else {
                micPermissionDenied = true
                return nil
            }
            // The permission await suspends; a second invocation may have
            // started a recording in the meantime.
            guard !isRecording else {
                return nil
            }
        }
        let preparedID = recorder.takePreparedID()
        var entry = DictationEntry(
            id: preparedID ?? UUID(),
            title: Self.newDictationTitle,
            createdAt: .now,
            duration: nil,
            status: .recording
        )
        entry.waveformSeed = Double(entries.count) * 4.7 + 3
        do {
            if preparedID != nil {
                do {
                    try recorder.start()
                } catch {
                    // A pre-armed recorder can go stale (e.g. the input
                    // device changed); rebuild it at click time before
                    // giving up.
                    try recorder.start(to: entry.audioURL)
                }
            } else {
                try recorder.start(to: entry.audioURL)
            }
        } catch {
            DictationArchive.removeRecording(for: entry.id)
            recordingError = error.localizedDescription
            return nil
        }
        withAnimation(.smooth) {
            entries.insert(entry, at: 0)
        }
        persist()
        prewarmPipeline()
        return entry.id
    }

    func finishDictation(_ id: DictationEntry.ID) {
        guard let index = entries.firstIndex(where: { $0.id == id }),
              entries[index].status == .recording else { return }
        let duration = recorder.stop()
        withAnimation(.smooth) {
            entries[index].duration = max(duration, 1)
            entries[index].status = .transcribing
        }
        computeWaveform(for: id)
        runTranscription(id)
        persist()
        prearmRecorder()
    }

    /// Stops whichever dictation is running, for callers that know one is but
    /// hold no entry — the ⌘R command, which fires from the menu bar with no
    /// selection of its own.
    func stopRecording() {
        guard let recordingID else {
            return
        }
        finishDictation(recordingID)
    }

    func retryTranscription(_ id: DictationEntry.ID) {
        guard let index = entries.firstIndex(where: { $0.id == id }),
              entries[index].status == .transcriptionFailed else { return }
        update(id) { entry in
            entry.transcriptionError = nil
            entry.status = .transcribing
        }
        runTranscription(id)
        persist()
    }

    /// Re-runs the whole variants stage, whether the last one failed or
    /// succeeded — one path for the retry after an error and for asking again
    /// for a rewrite that is simply not good enough, since the two do the same
    /// work. It covers the title too: a failed title leaves no error of its own
    /// to retry from, so an entry still carrying the placeholder gets its
    /// second chance here, while a title that already stuck is kept. The status
    /// flip is what the card and the connector read to show the work is live.
    func regenerateVariant(_ id: DictationEntry.ID) {
        guard let entry = entries.first(where: { $0.id == id }),
              entry.labeledTranscript != nil else { return }
        update(id) { entry in
            entry.cleanedUp = nil
            entry.cleanedUpError = nil
            entry.status = .generatingVariants
        }
        Task { await generateVariants(for: id) }
        persist()
    }

    func delete(_ id: DictationEntry.ID) {
        // Deleting the entry that is being recorded must release the microphone.
        let wasRecording = recordingID == id
        if wasRecording {
            _ = recorder.stop()
        }
        if persistsToDisk {
            DictationArchive.removeRecording(for: id)
        }
        withAnimation(.smooth) {
            entries.removeAll { $0.id == id }
        }
        persist()
        if wasRecording {
            prearmRecorder()
        }
    }

    // MARK: - Pipeline

    private func runTranscription(_ id: DictationEntry.ID) {
        Task {
            await modelDownload.waitUntilReady()
            guard let entry = entries.first(where: { $0.id == id }) else {
                return
            }
            do {
                let segments = try await Self.transcribeSegments(
                    audioURL: entry.audioURL,
                    modelURL: AppLocations.whisperModelFile,
                    via: transcriber
                )
                var names = SpeakerDefaults.load()
                for speaker in Set(segments.map(\.speaker)) where names[speaker] == nil {
                    names[speaker] = TranscriptFormatting.defaultName(for: speaker)
                }
                let flat = TranscriptFormatting.labeledText(segments: segments, names: names)
                update(id) { entry in
                    entry.segments = segments
                    entry.speakerNames = names
                    entry.transcript = flat
                    entry.status = .generatingVariants
                }
                let variants = Task { await self.generateVariants(for: id) }
                persist()
                await variants.value
            } catch {
                update(id) { entry in
                    entry.status = .transcriptionFailed
                    entry.transcriptionError = error.localizedDescription
                }
                persist()
            }
        }
    }

    /// Runs the title suggestion and the rewrite in parallel. The entry
    /// completes as soon as the rewrite has an outcome — text or error, the
    /// latter landing in `cleanedUpError` — without waiting for the title; a
    /// failed title keeps the placeholder silently.
    private func generateVariants(for id: DictationEntry.ID) async {
        guard let entry = entries.first(where: { $0.id == id }),
              let transcript = entry.labeledTranscript else { return }
        let needsRewrite = entry.cleanedUp == nil && entry.cleanedUpError == nil
        let needsTitle = entry.title == Self.newDictationTitle

        if !needsRewrite {
            update(id) { $0.status = .complete }
            guard needsTitle else {
                persist()
                return
            }
        }
        await withTaskGroup(of: PipelineOutcome.self) { group in
            if needsTitle {
                group.addTask {
                    .title(try? await Self.transform(Agent.title, transcript: transcript))
                }
            }
            if needsRewrite {
                group.addTask {
                    do {
                        let text = try await Self.transform(Agent.cleanUp, transcript: transcript)
                        return .rewrite(text: text, error: nil)
                    } catch {
                        return .rewrite(text: nil, error: error.localizedDescription)
                    }
                }
            } else {
                // The status flip above must reach disk — after the title
                // dispatch, not before it.
                persist()
            }
            for await outcome in group {
                apply(outcome, to: id)
                if case .rewrite = outcome {
                    update(id) { $0.status = .complete }
                }
                persist()
            }
        }
    }

    private static func transform(
        _ agent: Agent,
        transcript: String
    ) async throws -> String {
        try await LLMProxyClient.run(agent: agent, transcript: transcript)
    }

    /// On-device Whisper transcribes; the proxy runs only where Whisper
    /// cannot — an unreadable model file, an inference failure. Whisper comes
    /// first because the recording then never leaves the machine, and it
    /// keeps the dictation in the language it was spoken in: on the same
    /// audio, Whisper stayed German throughout where the cloud models mixed
    /// English in.
    private static func transcribeSegments(
        audioURL: URL,
        modelURL: URL,
        via transcriber: WhisperTranscriber
    ) async throws -> [TranscriptSegment] {
        do {
            let whisper = try await transcriber.transcribe(audioURL: audioURL, modelURL: modelURL)
            if !whisper.isEmpty {
                return whisper
            }
        } catch {
            guard LLMProxyClient.hasAPIKey else {
                throw error
            }
            return try await ProxyTranscriber.transcribe(audioURL: audioURL)
        }
        // Silence is silence; asking the proxy about it would only cost a round trip.
        throw WhisperTranscriber.TranscriptionError.audioUnreadable(
            audioURL,
            "No speech detected."
        )
    }

    /// Renames a diarization label on this entry and remembers it for later ones.
    func renameSpeaker(_ speaker: String, to name: String, on id: DictationEntry.ID) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        update(id) { entry in
            if trimmed.isEmpty {
                entry.speakerNames[speaker] = TranscriptFormatting.defaultName(for: speaker)
            } else {
                entry.speakerNames[speaker] = trimmed
            }
            if let segments = entry.segments {
                entry.transcript = TranscriptFormatting.labeledText(
                    segments: segments,
                    names: entry.speakerNames
                )
            }
        }
        if let entry = entries.first(where: { $0.id == id }) {
            SpeakerDefaults.save(entry.speakerNames)
        }
        persist()
    }

    private func apply(_ outcome: PipelineOutcome, to id: DictationEntry.ID) {
        switch outcome {
        case let .title(title):
            guard let title, !title.isEmpty else {
                return
            }
            update(id) { $0.title = title }

        case let .rewrite(text, error):
            update(id) { entry in
                entry.cleanedUp = text
                entry.cleanedUpError = error
                // The streamed draft has served its purpose; the final text
                // (or error) now owns the card.
                entry.cleanedUpDraft = nil
            }
        }
    }

    /// Folds a streamed partial into the entry's live draft. No animation and
    /// no persist — this fires up to ~25×/s and only grows an on-screen
    /// string. The length guard keeps the draft monotonic even if two
    /// main-actor hops land out of order, and stops once the final text has
    /// arrived.
    private func updateDraft(_ id: DictationEntry.ID, text: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }),
              entries[index].cleanedUp == nil,
              entries[index].cleanedUpError == nil,
              text.count > (entries[index].cleanedUpDraft?.count ?? 0)
        else { return }
        entries[index].cleanedUpDraft = text
    }

    // MARK: - Persistence

    private func persist() {
        guard persistsToDisk else {
            return
        }
        DictationArchive.save(entries)
    }

    // MARK: - Helpers

    private func update(_ id: DictationEntry.ID, _ mutate: (inout DictationEntry) -> Void) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else {
            return
        }
        withAnimation(.smooth) {
            mutate(&entries[index])
        }
    }

    /// Reads the finished recording's peaks for the playback waveform.
    private func computeWaveform(for id: DictationEntry.ID) {
        let audioURL = AppLocations.recordingURL(for: id)
        Task {
            guard let waveform = await AudioSamples.peaks(from: audioURL) else {
                return
            }
            update(id) { $0.waveform = waveform }
            persist()
        }
    }
}

// MARK: - Launch and idle

/// What the store does when nobody is asking: pick up the work a previous
/// launch left unfinished, and use the idle time to have whisper and the
/// recorder ready before the next click needs them.
private extension DictationStore {
    /// Entries can be left mid-pipeline when the app quits; resume or fail them.
    func recoverInterruptedEntries() {
        for index in entries.indices {
            let id = entries[index].id
            switch entries[index].status {
            case .recording:
                entries[index].status = .transcriptionFailed
                entries[index].transcriptionError = "Recording was interrupted."

            case .transcribing:
                runTranscription(id)

            case .generatingVariants:
                if entries[index].transcript == nil {
                    entries[index].status = .transcribing
                    runTranscription(id)
                } else {
                    Task { await generateVariants(for: id) }
                }

            case .complete:
                // A quit during regenerateVariant can persist a rewrite with
                // neither text nor error; re-run it so it does not stay a
                // placeholder forever.
                let entry = entries[index]
                if entry.transcript != nil, entry.cleanedUp == nil, entry.cleanedUpError == nil {
                    Task { await generateVariants(for: id) }
                }

            case .transcriptionFailed:
                break
            }
        }
        persist()
    }

    /// Loads the whisper context while the user is still speaking.
    func prewarmPipeline() {
        guard persistsToDisk else {
            return
        }
        Task {
            await self.transcriber.warmUp(modelURL: AppLocations.whisperModelFile)
        }
    }

    /// Lets the recorder ready itself for the next dictation while the app is
    /// idle, so the next click only has to begin capture. Previews never
    /// pre-arm; a recording in progress owns the recorder.
    func prearmRecorder() {
        guard persistsToDisk, !isRecording else {
            return
        }
        recorder.prearm { id in !entries.contains { $0.id == id } }
    }
}

/// Result of one parallel claude call in the variants stage.
nonisolated private enum PipelineOutcome: Sendable {
    case rewrite(text:
        String?, error: String?)

    case title(String?)
}
