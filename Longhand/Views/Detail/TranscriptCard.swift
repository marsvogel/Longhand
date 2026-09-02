//
//  TranscriptCard.swift
//  Longhand
//

import SwiftUI

/// Middle station of the flow diagram: the raw transcript, a placeholder
/// while transcription or the model download is running, or the failure
/// state with a retry.
struct TranscriptCard: View {
    @Environment(DictationStore.self)
    private var store
    @Environment(ModelDownloadManager.self)
    private var modelDownload
    let entry: DictationEntry

    var body: some View {
        FlowCard(icon: "text.quote", title: "Transcript") {
            if entry.status == .transcribing {
                if modelDownload.state == .ready {
                    HStack(spacing: 6) {
                        InlineSpinner()
                        Text("Transcribing…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let transcript = entry.transcript {
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
        } else if let transcript = entry.transcript {
            Text(transcript)
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if entry.status == .transcribing, modelDownload.state != .ready {
            downloadStatus
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("""
                The transcript will appear here in a moment. Longhand is turning the \
                recording into text right now, sentence by sentence.
                """)
                .lineSpacing(3)
                .redacted(reason: .placeholder)
        }
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
