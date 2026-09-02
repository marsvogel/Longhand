//
//  DictationStore.swift
//  Longhand
//
//  The observable state object behind the main window. Views render its
//  published state and call its intent methods; they never mutate entries
//  directly. The store drives the real pipeline: record → transcribe with
//  whisper → rewrite with the claude CLI, persisting after every mutation.
//  While the user speaks it pre-warms the expensive stages — the whisper
//  context and one claude process per transformation — so their startup
//  cost never lands in the wait after the recording stops.
//
//  It orchestrates, it does not implement: capture lives in DictationRecorder,
//  inference in WhisperTranscriber, rewriting in ClaudeCLI/ClaudeWarmPool, and
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

    /// Warm claude instances keyed by the dictation they were armed for:
    /// created at recording start, taken exactly once when that entry's
    /// transcript dispatches, torn down when the entry aborts first. Keeping
    /// pools per entry means starting the next recording while the previous
    /// dictation still transcribes does not cost it its warm instances.
    @ObservationIgnored private var warmPools: [DictationEntry.ID: ClaudeWarmPool] = [:]

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
        prewarmPipeline(for: entry.id)
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

    func retryVariant(_ id: DictationEntry.ID) {
        guard let entry = entries.first(where: { $0.id == id }),
              entry.cleanedUpError != nil,
              let transcript = entry.transcript else { return }
        update(id) { $0.cleanedUpError = nil }
        Task {
            do {
                let text = try await Self.transform(Agent.cleanUp, transcript: transcript, via: nil)
                update(id) { $0.cleanedUp = text }
            } catch {
                update(id) { $0.cleanedUpError = error.localizedDescription }
            }
            persist()
        }
        persist()
    }

    func delete(_ id: DictationEntry.ID) {
        // Deleting the entry that is being recorded must release the microphone.
        let wasRecording = recordingID == id
        if wasRecording {
            _ = recorder.stop()
        }
        invalidateWarmPool(for: id)
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
                invalidateWarmPool(for: id)
                return
            }
            do {
                let transcript = try await transcriber.transcribe(
                    audioURL: entry.audioURL,
                    modelURL: AppLocations.whisperModelFile
                )
                update(id) { entry in
                    entry.transcript = transcript
                    entry.status = .generatingVariants
                }
                let variants = Task { await self.generateVariants(for: id) }
                persist()
                await variants.value
            } catch {
                invalidateWarmPool(for: id)
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
              let transcript = entry.transcript else { return }
        let needsRewrite = entry.cleanedUp == nil && entry.cleanedUpError == nil
        let needsTitle = entry.title == Self.newDictationTitle

        if !needsRewrite {
            update(id) { $0.status = .complete }
            guard needsTitle else {
                persist()
                return
            }
        }
        let pool = takeWarmPool(for: id)
        await withTaskGroup(of: PipelineOutcome.self) { group in
            if needsTitle {
                group.addTask {
                    .title(try? await Self.transform(Agent.title, transcript: transcript, via: pool))
                }
            }
            if needsRewrite {
                group.addTask {
                    do {
                        let text = try await Self.transform(
                            Agent.cleanUp,
                            transcript: transcript,
                            via: pool
                        ) { partial in
                            Task { @MainActor in self.updateDraft(id, text: partial) }
                        }
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

    /// Every claude call in the store funnels through here: through the warm
    /// pool when one is supplied — the pool itself falls back to a cold run
    /// on any warm failure — and straight to a cold run otherwise. Retries
    /// and recovery pass nil, keeping them cold by construction.
    private static func transform(
        _ agent: Agent,
        transcript: String,
        via pool: ClaudeWarmPool?,
        onPartial: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws -> String {
        if let pool {
            return try await pool.run(agent: agent, transcript: transcript, onPartial: onPartial)
        }
        return try await ClaudeCLI.run(agent: agent, transcript: transcript)
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

    /// Entries can be left mid-pipeline when the app quits; resume or fail them.
    private func recoverInterruptedEntries() {
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
                // A quit during retryVariant can persist a rewrite with
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

    // MARK: - Pre-warming

    /// Spawns the warm claude instances and loads the whisper context while
    /// the user is still speaking. Previews never pre-warm.
    private func prewarmPipeline(for id: DictationEntry.ID) {
        guard persistsToDisk else {
            return
        }
        // Idle warm instances each pin ~350 MB and open API connections, and
        // dispatch waits for the whisper model however long its download (or
        // a retry after failure) takes; claude therefore only warms once the
        // model is ready and dispatch is at most seconds away.
        if modelDownload.state == .ready {
            let pool = ClaudeWarmPool()
            warmPools[id] = pool
            pool.prewarm()
        }
        Task {
            // A no-op while the model file has not finished downloading.
            await self.transcriber.warmUp(modelURL: AppLocations.whisperModelFile)
        }
    }

    /// Hands out the pool armed for this entry, exactly once; afterwards —
    /// and for every entry that never had one — claude calls run cold.
    private func takeWarmPool(for id: DictationEntry.ID) -> ClaudeWarmPool? {
        warmPools.removeValue(forKey: id)
    }

    /// Tears down the warm instances when this entry aborts before dispatch.
    private func invalidateWarmPool(for id: DictationEntry.ID) {
        warmPools.removeValue(forKey: id)?.invalidate()
    }

    // MARK: - Recorder pre-arm

    /// Lets the recorder ready itself for the next dictation while the app is
    /// idle, so the next click only has to begin capture. Previews never
    /// pre-arm; a recording in progress owns the recorder.
    private func prearmRecorder() {
        guard persistsToDisk, !isRecording else {
            return
        }
        recorder.prearm { id in !entries.contains { $0.id == id } }
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

/// Result of one parallel claude call in the variants stage.
nonisolated private enum PipelineOutcome: Sendable {
    case rewrite(text:
        String?, error: String?)

    case title(String?)
}
