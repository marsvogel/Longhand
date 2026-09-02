//
//  PlaybackController.swift
//  Longhand
//

import AVFoundation
import Observation

/// Plays back a recorded dictation and publishes progress for the waveform.
@MainActor
@Observable
final class PlaybackController: NSObject, AVAudioPlayerDelegate {
    private(set) var isPlaying = false
    /// 0…1 playback position; resets to 0 when playback finishes.
    private(set) var progress: Double = 0

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var progressTask: Task<Void, Never>?

    func toggle(url: URL) {
        if let player, player.url == url {
            if isPlaying {
                player.pause()
                isPlaying = false
                stopProgressUpdates()
            } else {
                player.play()
                isPlaying = true
                startProgressUpdates()
            }
            return
        }

        stop()
        guard let player = try? AVAudioPlayer(contentsOf: url) else {
            return
        }
        player.delegate = self
        self.player = player
        player.play()
        isPlaying = true
        startProgressUpdates()
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        progress = 0
        stopProgressUpdates()
    }

    // MARK: - AVAudioPlayerDelegate

    // The player does not guarantee a main-thread callback, so hop explicitly.
    nonisolated func audioPlayerDidFinishPlaying(_: AVAudioPlayer, successfully _: Bool) {
        Task { @MainActor in
            self.playbackDidFinish()
        }
    }

    private func playbackDidFinish() {
        isPlaying = false
        progress = 0
        stopProgressUpdates()
    }

    private func startProgressUpdates() {
        stopProgressUpdates()
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self else {
                    return
                }
                updateProgress()
            }
        }
    }

    private func stopProgressUpdates() {
        progressTask?.cancel()
        progressTask = nil
    }

    private func updateProgress() {
        guard let player else {
            return
        }
        progress = player.duration > 0 ? min(player.currentTime / player.duration, 1) : 0
    }
}
