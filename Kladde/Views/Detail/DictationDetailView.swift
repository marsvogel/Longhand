//
//  DictationDetailView.swift
//  Kladde
//
//  Renders a dictation as a vertical flow diagram while it is still being
//  processed: audio at the top, then transcript, then the rewrite. Once the
//  rewrite exists, that card moves to the top — it is what the user came for —
//  and Audio and Transcript collapse so a long dictation is not a wall of text.
//

import SwiftUI

struct DictationDetailView: View {
    let entry: DictationEntry
    var onStop: () -> Void

    @State private var audioExpanded = true
    @State private var transcriptExpanded = true
    @State private var cleanedUpExpanded = true

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                    .padding(.bottom, 24)

                if resultFirst {
                    resultLayout
                } else {
                    pipelineLayout
                }
            }
            .padding(28)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
            .animation(.smooth, value: resultFirst)
        }
        .onChange(of: entry.id, initial: true) {
            resetExpansion(for: entry)
        }
        .onChange(of: entry.cleanedUp) {
            guard entry.cleanedUp != nil else {
                return
            }
            withAnimation(.smooth) {
                cleanedUpExpanded = true
                audioExpanded = false
                transcriptExpanded = false
            }
        }
    }

    /// The rewrite is ready (or finally failed). Pipeline order gives way to
    /// result-first so the user lands on the cleaned-up text, not the raw tape.
    private var resultFirst: Bool {
        entry.cleanedUp != nil
            || (entry.status == .complete && entry.cleanedUpError != nil)
    }

    private var showsVariants: Bool {
        entry.status == .generatingVariants || entry.status == .complete
    }

    private var isGenerating: Bool {
        entry.status == .generatingVariants
            && entry.cleanedUp == nil
            && entry.cleanedUpError == nil
    }

    @ViewBuilder private var resultLayout: some View {
        VariantCard(entry: entry, isExpanded: $cleanedUpExpanded)
        quietGap
        AudioCard(entry: entry, onStop: onStop, isExpanded: $audioExpanded)
        quietGap
        TranscriptCard(entry: entry, isExpanded: $transcriptExpanded)
    }

    @ViewBuilder private var pipelineLayout: some View {
        AudioCard(entry: entry, onStop: onStop, isExpanded: $audioExpanded)

        if entry.status != .recording {
            VStack(spacing: 0) {
                FlowConnector(isActive: entry.status == .transcribing)
                TranscriptCard(entry: entry, isExpanded: $transcriptExpanded)
            }
            .transition(.blurReplace)
        }

        if showsVariants {
            VStack(spacing: 0) {
                FlowConnector(isActive: isGenerating)
                VariantCard(entry: entry, isExpanded: $cleanedUpExpanded)
            }
            .transition(.blurReplace)
        }
    }

    /// Spacing between cards once the pipeline connectors no longer apply —
    /// the stages are no longer "next", just sections of the same document.
    private var quietGap: some View {
        Color.clear.frame(height: 12)
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

    private func resetExpansion(for entry: DictationEntry) {
        if entry.cleanedUp != nil
            || (entry.status == .complete && entry.cleanedUpError != nil) {
            cleanedUpExpanded = true
            audioExpanded = false
            transcriptExpanded = false
        } else {
            audioExpanded = true
            transcriptExpanded = true
            cleanedUpExpanded = true
        }
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
