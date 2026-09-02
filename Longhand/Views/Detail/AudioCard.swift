//
//  AudioCard.swift
//  Longhand
//

import SwiftUI

/// Top station of the flow diagram: live recording UI while the dictation
/// is running, playback UI afterwards.
struct AudioCard: View {
    @Environment(DictationStore.self)
    private var store
    let entry: DictationEntry
    var onStop: () -> Void
    @State private var playback = PlaybackController()

    var body: some View {
        Group {
            if entry.status == .recording {
                recordingBody
            } else {
                playbackBody
            }
        }
        .onChange(of: entry.id) {
            playback.stop()
        }
    }

    private var recordingBody: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                RecordingDot()
                Text("Recording")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                Spacer()
                Text(entry.createdAt, style: .timer)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            LiveWaveform(level: store.recorder.level)
                .frame(height: 44)
                .foregroundStyle(.red)
            Button(action: onStop) {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 34))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Stop Recording")
            }
            .buttonStyle(.borderless)
            .help("Stop and transcribe (⌘R)")
        }
        .flowCardChrome()
    }

    private var playbackBody: some View {
        FlowCard(icon: "waveform", title: "Audio") {
            CopyButton(help: "Copy audio file") {
                Pasteboard.copy(file: entry.audioURL)
            }
        } content: {
            HStack(spacing: 12) {
                Button {
                    playback.toggle(url: entry.audioURL)
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 30))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.tint)
                        .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
                }
                .buttonStyle(.borderless)
                .help(playback.isPlaying ? "Pause" : "Play")
                StaticWaveform(seed: entry.waveformSeed, peaks: entry.waveform, progress: playback.progress)
                    .frame(height: 36)
                    .foregroundStyle(.secondary)
                if let durationText = entry.durationText {
                    Text(durationText)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Playback") {
    AudioCard(entry: DictationEntry.samples[0]) {}
        .padding(24)
        .frame(width: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(DictationStore())
}

#Preview("Recording") {
    AudioCard(entry: .previewRecording) {}
        .padding(24)
        .frame(width: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(DictationStore())
}
