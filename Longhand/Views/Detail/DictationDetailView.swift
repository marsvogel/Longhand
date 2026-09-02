//
//  DictationDetailView.swift
//  Longhand
//
//  Renders a dictation as a vertical flow diagram: audio at the top, a
//  connector down to the transcript, then another down to the generated
//  variant. While the entry is still being processed, the connectors
//  animate and the pending card shows a placeholder, so the pipeline reads
//  like a small live infographic.
//

import SwiftUI

struct DictationDetailView: View {
    let entry: DictationEntry
    var onStop: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                    .padding(.bottom, 24)

                AudioCard(entry: entry, onStop: onStop)

                if entry.status != .recording {
                    VStack(spacing: 0) {
                        FlowConnector(isActive: entry.status == .transcribing)
                        TranscriptCard(entry: entry)
                    }
                    .transition(.blurReplace)
                }

                if showsVariants {
                    VStack(spacing: 0) {
                        FlowConnector(isActive: isGenerating)
                        VariantCard(entry: entry)
                    }
                    .transition(.blurReplace)
                }
            }
            .padding(28)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
    }

    private var showsVariants: Bool {
        entry.status == .generatingVariants || entry.status == .complete
    }

    private var isGenerating: Bool {
        entry.status == .generatingVariants
            && entry.cleanedUp == nil
            && entry.cleanedUpError == nil
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.title)
                .font(.title2.weight(.semibold))
            Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Previews

#Preview("Complete") {
    DictationDetailView(entry: DictationEntry.samples[0]) {}
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(width: 720, height: 820)
        .environment(DictationStore(entries: DictationEntry.samples))
        .environment(ModelDownloadManager(state: .ready))
}

#Preview("Narrow") {
    // The tightest layout that can occur: the detail column's 390pt minimum,
    // the same width the collapsed-sidebar minimal window provides.
    DictationDetailView(entry: DictationEntry.samples[0]) {}
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(width: 390, height: 820)
        .environment(DictationStore(entries: DictationEntry.samples))
        .environment(ModelDownloadManager(state: .ready))
}

#Preview("Recording") {
    DictationDetailView(entry: .previewRecording) {}
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(width: 720, height: 480)
        .environment(DictationStore())
        .environment(ModelDownloadManager(state: .ready))
}

#Preview("Transcribing") {
    DictationDetailView(entry: .previewTranscribing) {}
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(width: 720, height: 560)
        .environment(DictationStore())
        .environment(ModelDownloadManager(state: .ready))
}

#Preview("Generating Variants") {
    DictationDetailView(entry: .previewGenerating) {}
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(width: 720, height: 820)
        .environment(DictationStore())
        .environment(ModelDownloadManager(state: .ready))
}

#Preview("Transcription Failed") {
    DictationDetailView(entry: .previewTranscriptionFailed) {}
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(width: 720, height: 560)
        .environment(DictationStore())
        .environment(ModelDownloadManager(state: .ready))
}
