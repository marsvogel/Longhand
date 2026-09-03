//
//  VariantCard.swift
//  Kladde
//

import SwiftUI

/// Leaf station of the flow diagram: the cleaned-up rewrite of the
/// transcript, a placeholder while it is being written, or the failure
/// state with a retry.
struct VariantCard: View {
    @Environment(DictationStore.self)
    private var store
    let entry: DictationEntry
    var isExpanded: Binding<Bool>?

    var body: some View {
        FlowCard(
            icon: "wand.and.stars",
            title: "Cleaned Up",
            subtitle: "Written down, with decisions, questions and next steps",
            isExpanded: isExpanded
        ) {
            if let text = entry.cleanedUp {
                HStack(spacing: 10) {
                    // The agent prompt changes more often than the transcript
                    // does, so a finished rewrite needs a way to be asked for
                    // again — the Retry below only ever appears after a failure.
                    Button {
                        store.regenerateVariant(entry.id)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Rewrite again")
                    }
                    .buttonStyle(.borderless)
                    .help("Rewrite again")
                    CopyButton(help: "Copy cleaned up text") {
                        Pasteboard.copy(text)
                    }
                }
            } else if entry.cleanedUpError == nil {
                InlineSpinner()
            }
        } content: {
            if let text = entry.cleanedUp {
                MarkdownText(markdown: text)
            } else if let error = entry.cleanedUpError {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        store.regenerateVariant(entry.id)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let draft = entry.cleanedUpDraft, !draft.isEmpty {
                // The rewrite as it streams in, re-parsed on every update: the
                // Markdown is still half-written, so blocks appear and reflow
                // as they close. A selection made here is dropped by the next
                // partial, and the spinner above still marks it live.
                MarkdownText(markdown: draft)
            } else {
                Text("This variant is being written from the transcript and will show up here shortly.")
                    .font(.callout)
                    .lineSpacing(3)
                    .redacted(reason: .placeholder)
            }
        }
    }
}

// MARK: - Previews

#Preview("Generated") {
    VariantCard(entry: DictationEntry.samples[0])
        .padding(24)
        .frame(width: 360)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(DictationStore())
}

#Preview("Writing") {
    VariantCard(entry: .previewGenerating)
        .padding(24)
        .frame(width: 360)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(DictationStore())
}

#Preview("Streaming") {
    VariantCard(entry: .previewStreaming)
        .padding(24)
        .frame(width: 360)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(DictationStore())
}

#Preview("Failed") {
    VariantCard(entry: .previewVariantFailed)
        .padding(24)
        .frame(width: 360)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(DictationStore())
}
