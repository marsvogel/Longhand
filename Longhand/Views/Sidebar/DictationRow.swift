//
//  DictationRow.swift
//  Longhand
//
//  One sidebar row, laid out the way Notes lays out a note: a semibold
//  title, a detail line pairing the date with a content snippet, and a
//  trailing metadata line — Notes shows the folder there; Longhand shows
//  the recording's duration behind a small waveform. Selection paints the
//  accent-colored rounded tile, so every text style has a selected (white)
//  counterpart.
//

import SwiftUI

struct DictationRow: View {
    let entry: DictationEntry
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(entry.title)
                .fontWeight(.semibold)
                .lineLimit(1)
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            detailLine
                .font(.subheadline)
                .lineLimit(1)
            if entry.status != .recording {
                // The metadata line: duration behind a small waveform on the
                // left — Longhand's counterpart to Notes' folder line — and
                // the creation date right-aligned at the far end.
                HStack(spacing: 5) {
                    if let durationText = entry.durationText {
                        Image(systemName: "waveform")
                            .font(.caption2)
                            .accessibilityHidden(true)
                        Text(durationText)
                            .monospacedDigit()
                    }
                    Spacer()
                    Text(DictationDate.rowLabel(for: entry.createdAt))
                        .foregroundStyle(secondaryStyle)
                }
                .font(.caption)
                .foregroundStyle(tertiaryStyle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.clear))
        )
    }

    /// The middle line: the content snippet for a finished dictation, the
    /// live status while the pipeline runs.
    @ViewBuilder private var detailLine: some View {
        switch entry.status {
        case .recording:
            HStack(spacing: 5) {
                RecordingDot(diameter: 6)
                Text("Recording…")
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.red))
                Spacer()
                Text(entry.createdAt, style: .timer)
                    .monospacedDigit()
                    .foregroundStyle(secondaryStyle)
            }

        case .transcribing:
            processingLine("Transcribing…")

        case .generatingVariants:
            processingLine("Writing variants…")

        case .transcriptionFailed:
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.red))
                    .accessibilityHidden(true)
                Text("Transcription failed")
                    .foregroundStyle(secondaryStyle)
            }

        case .complete:
            if let snippet {
                Text(snippet)
                    .foregroundStyle(tertiaryStyle)
            }
        }
    }

    /// One-line content preview, the way Notes previews the note body next to
    /// the date: the polished rewrite once it exists, the live draft while it
    /// streams, the raw transcript before that.
    private var snippet: String? {
        guard let source = entry.cleanedUp ?? entry.cleanedUpDraft ?? entry.transcript else {
            return nil
        }
        let collapsed = source.prefix(200)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }

    private var secondaryStyle: AnyShapeStyle {
        isSelected ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary)
    }

    private var tertiaryStyle: AnyShapeStyle {
        isSelected ? AnyShapeStyle(.white.opacity(0.65)) : AnyShapeStyle(.tertiary)
    }

    private func processingLine(_ label: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(secondaryStyle)
            Spacer()
            InlineSpinner(size: 11)
        }
    }
}
