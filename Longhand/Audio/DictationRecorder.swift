//
//  DictationRecorder.swift
//  Longhand
//

import AVFoundation
import Observation

/// Records dictations as 16 kHz mono 16-bit WAV — whisper's native input
/// format — and publishes a normalized mic level for the live waveform.
@MainActor
@Observable
final class DictationRecorder {
    /// Thrown when audio capture cannot begin, e.g. without an input device.
    nonisolated enum RecorderError: LocalizedError {
        case captureFailedToStart

        var errorDescription: String? {
            "Recording could not start. Check that a microphone is available."
        }
    }

    /// Normalized 0…1 microphone level while recording.
    private(set) var level: Float = 0

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var meterTask: Task<Void, Never>?

    /// ID of the recording this recorder is currently armed for, mirrored in
    /// user defaults so a launch reuses the previous never-consumed prepared
    /// file instead of leaving a stray one behind per session.
    @ObservationIgnored private var preparedID: UUID?

    /// Unchanged since this lived on the store, so an ID left behind by an
    /// older build is still picked up instead of orphaning its file.
    private static let preparedIDKey = "preparedRecordingID"

    /// True when microphone access is already granted, letting callers skip
    /// the async permission request entirely.
    static var permissionGranted: Bool {
        AVAudioApplication.shared.recordPermission == .granted
    }

    func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    /// Creates the recorder for `url` and lets it allocate its capture
    /// resources up front, so a later `start()` only begins writing.
    /// Replaces any previously prepared or active recorder.
    func prepare(to url: URL) throws {
        stopMetering()
        recorder?.stop()

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVAudioFileTypeKey: Int(kAudioFileWAVEType)
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        recorder.prepareToRecord()
        self.recorder = recorder
    }

    /// Begins capture on the recorder set up by `prepare(to:)`.
    func start() throws {
        guard let recorder, recorder.record() else {
            self.recorder = nil
            throw RecorderError.captureFailedToStart
        }
        startMetering()
    }

    /// Prepares and starts in one step, for callers without a pre-arm phase.
    func start(to url: URL) throws {
        try prepare(to: url)
        try start()
    }

    func stop() -> TimeInterval {
        let duration = recorder?.currentTime ?? 0
        recorder?.stop()
        recorder = nil
        stopMetering()
        return duration
    }

    // MARK: - Pre-arming

    /// Prepares capture for the next dictation ahead of the click, so starting
    /// a recording only begins writing instead of spinning up the audio system
    /// first. Does nothing without microphone permission, and a failure simply
    /// leaves the next start to build its recorder itself. `isAvailable` lets
    /// the caller reject a stored ID that one of its dictations already uses.
    func prearm(isAvailable: (UUID) -> Bool) {
        guard Self.permissionGranted else {
            return
        }
        let id = preparedID ?? storedPreparedID(where: isAvailable) ?? UUID()
        do {
            try prepare(to: AppLocations.recordingURL(for: id))
            preparedID = id
            UserDefaults.standard.set(id.uuidString, forKey: Self.preparedIDKey)
        } catch {
            forgetPreparedID()
            DictationArchive.removeRecording(for: id)
        }
    }

    /// Consumes the pre-armed ID: the caller begins capture with `start()` and
    /// gives the new dictation this same ID, so the entry and the file already
    /// waiting for it agree.
    func takePreparedID() -> UUID? {
        guard let id = preparedID else {
            return nil
        }
        forgetPreparedID()
        return id
    }

    /// The prepared ID a previous session never consumed, unless it collides
    /// with a dictation that already exists.
    private func storedPreparedID(where isAvailable: (UUID) -> Bool) -> UUID? {
        guard let stored = UserDefaults.standard.string(forKey: Self.preparedIDKey),
              let id = UUID(uuidString: stored),
              isAvailable(id)
        else { return nil }
        return id
    }

    private func forgetPreparedID() {
        preparedID = nil
        UserDefaults.standard.removeObject(forKey: Self.preparedIDKey)
    }

    private func updateLevel() {
        guard let recorder else {
            return
        }
        recorder.updateMeters()
        let decibels = recorder.averagePower(forChannel: 0)
        level = max(0, min(1, (decibels + 50) / 50))
    }

    private func startMetering() {
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                guard let self else {
                    return
                }
                updateLevel()
            }
        }
    }

    private func stopMetering() {
        meterTask?.cancel()
        meterTask = nil
        level = 0
    }
}
