//
//  WaveformViews.swift
//  Kladde
//

import SwiftUI

/// Static bars for the recorded audio: real peaks when available, otherwise
/// a deterministic pattern derived from the seed. Bars up to `progress` are
/// tinted to show the playback position.
struct StaticWaveform: View {
    var seed: Double
    var peaks: [Float]?
    var progress: Double

    var body: some View {
        WaveformBars(progress: progress) { index, count in
            if let peaks, !peaks.isEmpty {
                let peakIndex = min(peaks.count - 1, index * peaks.count / max(count, 1))
                return 0.12 + 0.88 * Double(peaks[peakIndex])
            }
            let x = Double(index)
            let envelope = sin(x * 0.31 + seed) * 0.5 + 0.5
            let detail = sin(x * 1.7 + seed * 3.1) * 0.5 + 0.5
            return 0.12 + 0.88 * pow(envelope, 1.4) * (0.35 + 0.65 * detail)
        }
    }
}

/// The microphone levels measured while recording, one bar per measurement,
/// newest at the right. Nothing here is animated or synthesized: every bar is
/// a sample of the audio going to disk, so the trace stands still when the
/// room does.
struct LiveWaveform: View {
    var levels: [Float]

    var body: some View {
        WaveformBars { index, count in
            // Fewer measurements than bars — the first seconds of a recording
            // — leave the left end at the baseline and fill in rightwards.
            let position = levels.count - count + index
            guard position >= 0, position < levels.count else {
                return 0
            }
            return 0.08 + 0.92 * Double(levels[position])
        }
    }
}

// MARK: - Bars

private struct WaveformBars: View {
    var progress: Double = 0
    var amplitude: (_ index: Int, _ count: Int) -> Double

    var body: some View {
        Canvas { context, size in
            let barWidth: CGFloat = 3
            let gap: CGFloat = 3
            let count = max(1, Int(size.width / (barWidth + gap)))
            let playedCount = Int((Double(count) * progress).rounded())
            for index in 0..<count {
                let height = max(3, amplitude(index, count) * size.height)
                let rect = CGRect(
                    x: CGFloat(index) * (barWidth + gap),
                    y: (size.height - height) / 2,
                    width: barWidth,
                    height: height
                )
                let style = index < playedCount
                    ? AnyShapeStyle(.tint)
                    : AnyShapeStyle(ForegroundStyle())
                context.fill(
                    Path(roundedRect: rect, cornerRadius: barWidth / 2),
                    with: .style(style)
                )
            }
        }
    }
}
