//
//  TranscriptCard.swift
//  Kladde
//

import SwiftUI

/// Middle station of the flow diagram: the raw transcript, a placeholder
/// while transcription or the model download is running, or the failure
/// state with a retry. When several speakers were detected, their display
/// names can be edited here.
struct TranscriptCard: View {
    @Environment(DictationStore.self)
    private var store
    @Environment(ModelDownloadManager.self)
    private var modelDownload
    let entry: DictationEntry
    var isExpanded: Binding<Bool>?

    var body: some View {
        FlowCard(icon: "text.quote", title: "Transcript", isExpanded: isExpanded) {
            if entry.status == .transcribing {
                if modelDownload.state == .ready {
                    HStack(spacing: 6) {
                        InlineSpinner()
                        Text("Transcribing…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let transcript = entry.labeledTranscript {
                CopyButton(help: "Copy transcript") {
                    Pasteboard.copy(transcript)
                }
            }
        } content: {
            content
        }
    }

    @ViewBuilder private var content: some View {
        if entry.status == .transcriptionFailed {
            VStack(alignment: .leading, spacing: 8) {
                Text(entry.transcriptionError ?? "Transcription failed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Retry") {
                    store.retryTranscription(entry.id)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let transcript = entry.labeledTranscript {
            VStack(alignment: .leading, spacing: 12) {
                if entry.uniqueSpeakers.count > 1 {
                    speakerEditor
                }
                Text(transcript)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if entry.status == .transcribing, modelDownload.state != .ready {
            downloadStatus
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("""
                The transcript will appear here in a moment. Kladde is turning the \
                recording into text right now, sentence by sentence.
                """)
                .lineSpacing(3)
                .redacted(reason: .placeholder)
        }
    }

    private var speakerEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Speakers")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(entry.uniqueSpeakers, id: \.self) { speaker in
                HStack(spacing: 8) {
                    Text(speaker)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(width: 16, alignment: .leading)
                    TextField(
                        TranscriptFormatting.defaultName(for: speaker),
                        text: speakerNameBinding(speaker)
                    )
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder private var downloadStatus: some View {
        switch modelDownload.state {
        case let .failed(message):
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Retry Download") {
                    modelDownload.start()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

        case let .downloading(fraction):
            downloadProgress("Downloading transcription model…", fraction: fraction)

        case .idle:
            downloadProgress("Waiting for download…", fraction: 0)

        case .ready:
            EmptyView()
        }
    }

    private func speakerNameBinding(_ speaker: String) -> Binding<String> {
        Binding(
            get: {
                entry.speakerNames[speaker]
                    ?? TranscriptFormatting.defaultName(for: speaker)
            },
            set: { store.renameSpeaker(speaker, to: $0, on: entry.id) }
        )
    }

    private func downloadProgress(_ label: String, fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                Spacer()
                Text(fraction, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            ProgressView(value: fraction)
                .controlSize(.small)
        }
    }
}

// MARK: - Previews

#Preview("Transcript") {
    TranscriptCard(entry: DictationEntry.samples[0])
        .padding(24)
        .frame(width: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(DictationStore())
        .environment(ModelDownloadManager(state: .ready))
}

#Preview("Transcribing") {
    TranscriptCard(entry: .previewTranscribing)
        .padding(24)
        .frame(width: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(DictationStore())
        .environment(ModelDownloadManager(state: .ready))
}

#Preview("Downloading Model") {
    TranscriptCard(entry: .previewTranscribing)
        .padding(24)
        .frame(width: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(DictationStore())
        .environment(ModelDownloadManager(state: .downloading(0.42)))
}

#Preview("Download Failed") {
    TranscriptCard(entry: .previewTranscribing)
        .padding(24)
        .frame(width: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(DictationStore())
        .environment(ModelDownloadManager(state: .failed("The network connection was lost.")))
}

#Preview("Transcription Failed") {
    TranscriptCard(entry: .previewTranscriptionFailed)
        .padding(24)
        .frame(width: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(DictationStore())
        .environment(ModelDownloadManager(state: .ready))
}
