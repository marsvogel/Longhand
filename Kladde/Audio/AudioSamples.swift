//
//  AudioSamples.swift
//  Kladde
//
//  The one place that turns a recording on disk into numbers. Two consumers
//  need it: whisper wants the whole sample array, the playback waveform only
//  wants its peaks. Both read the same 16 kHz mono WAV the same way, so the
//  read lives here once and each takes what it needs from the shared buffer.
//

import AVFAudio

nonisolated enum AudioSamples {
    /// Why a recording could not be read, phrased for display.
    struct ReadError: Swift.Error {
        let reason: String
    }

    /// Runs `body` over the recording's mono Float32 samples, without copying
    /// them out of the audio buffer. Recordings are written as 16 kHz mono WAV,
    /// so the file's processing format is already the layout both consumers
    /// want and one bulk read suffices.
    static func withSamples<T>(from url: URL, _ body: (UnsafeBufferPointer<Float>) -> T) throws -> T {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw ReadError(reason: error.localizedDescription)
        }
        guard file.length > 0,
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: file.processingFormat,
                  frameCapacity: AVAudioFrameCount(file.length)
              )
        else {
            throw ReadError(reason: "The recording contains no audio.")
        }
        do {
            try file.read(into: buffer)
        } catch {
            throw ReadError(reason: error.localizedDescription)
        }
        guard let channelData = buffer.floatChannelData else {
            throw ReadError(reason: "Unsupported sample format.")
        }
        // The buffer owns the samples, so it has to outlive the call.
        return withExtendedLifetime(buffer) {
            body(UnsafeBufferPointer(start: channelData[0], count: Int(buffer.frameLength)))
        }
    }

    /// Bucketed max-abs sample values, normalized 0…1 — the static waveform
    /// behind the playback scrubber. Runs off the main actor: long dictations
    /// mean tens of megabytes of samples.
    @concurrent
    static func peaks(from url: URL, bucketCount: Int = 80) async -> [Float]? {
        try? withSamples(from: url) { samples in
            let frameCount = samples.count
            guard frameCount > 0 else {
                return nil
            }
            let bucketSize = max(1, frameCount / bucketCount)
            var peaks: [Float] = []
            peaks.reserveCapacity(bucketCount + 1)
            for bucketStart in stride(from: 0, to: frameCount, by: bucketSize) {
                var peak: Float = 0
                for index in bucketStart..<min(bucketStart + bucketSize, frameCount) {
                    peak = max(peak, abs(samples[index]))
                }
                peaks.append(peak)
            }
            guard let maxPeak = peaks.max(), maxPeak > 0 else {
                return peaks
            }
            return peaks.map { $0 / maxPeak }
        }
    }
}
