//
//  DictationListView.swift
//  Longhand
//
//  The dictation list, built like the Notes note list: date-bucketed
//  sections with sticky headers, rows of title / date + snippet / duration,
//  inset separators that step aside around the selection, and a rounded
//  accent tile for the selected row. A hand-rolled ScrollView instead of
//  List because SwiftUI's List cannot pin section headers on macOS.
//

import SwiftUI

struct DictationListView: View {
    @Environment(DictationStore.self)
    private var store
    /// Owned by the enclosing window's ContentView; each window drives its own.
    @Binding var selection: DictationEntry.ID?
    /// Whether the list is scrolled away from its resting position — while
    /// false, no sticky header is shown at all.
    @State private var isScrolled = false
    /// Which in-flow section headers have crossed the top edge, by title.
    /// The last section whose header is above the edge is the one the sticky
    /// overlay names. Entries persist after a header dematerializes far
    /// offscreen, which is exactly right: it is still above the edge.
    @State private var headerAboveTop: [String: Bool] = [:]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Deliberately not LazyVStack's pinnedViews: in the glass
                // sidebar those pin below the visible edge and render under
                // the row tiles. The sticky header is an overlay instead —
                // always topmost, exactly at the visible edge — and the
                // in-flow headers just report when they cross it.
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sections, id: \.title) { section in
                        Section {
                            rows(for: section.entries)
                        } header: {
                            // The 12pt below the hairline separates it from
                            // the group's first row. Only here in the flow —
                            // the sticky overlay ends with its hairline so
                            // rows pass directly beneath it.
                            headerLabel(section.title)
                                .overlay(alignment: .bottom) { Divider() }
                                .padding(.bottom, 12)
                                .onGeometryChange(for: Bool.self) { proxy in
                                    proxy.frame(in: .scrollView).minY <= 1
                                } action: { aboveTop in
                                    headerAboveTop[section.title] = aboveTop
                                }
                        }
                    }
                }
                .padding(.bottom, 8)
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y > 2
            } action: { _, newValue in
                isScrolled = newValue
            }
            .overlay(alignment: .top) {
                // The sticky header: the same label layout as the in-flow
                // header it covers, so taking over is pixel-invisible, plus
                // the glass that keeps it readable over passing rows.
                if isScrolled, let pinnedTitle {
                    headerLabel(pinnedTitle)
                        .background(.ultraThinMaterial)
                        .overlay(alignment: .bottom) { Divider() }
                }
            }
            .onChange(of: selection) { _, newValue in
                // Keeps a selection made elsewhere — a new recording, delete
                // reconciliation, ⌘R in another window — in view. A click on
                // a visible row scrolls by nothing.
                if let newValue {
                    withAnimation(.smooth) { proxy.scrollTo(newValue) }
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onMoveCommand(perform: moveSelection)
        .navigationSplitViewColumnWidth(min: 180, ideal: 270, max: 340)
        .onDeleteCommand {
            if let selection { delete(selection) }
        }
    }

    // MARK: - Pieces

    /// The section the sticky overlay currently stands in for: the last one
    /// whose in-flow header has scrolled past the top edge. Stale titles of
    /// deleted sections linger in the dictionary harmlessly — the walk only
    /// consults sections that still exist.
    private var pinnedTitle: String? {
        sections.last { headerAboveTop[$0.title] == true }?.title
    }

    /// The entries grouped into Notes-style date buckets, in store order.
    /// Entries are newest-first, so one pass with consecutive grouping yields
    /// the sections already sorted from Today downwards.
    private var sections: [(title: String, entries: [DictationEntry])] {
        var result: [(title: String, entries: [DictationEntry])] = []
        for entry in store.entries {
            let title = DictationDate.sectionTitle(for: entry.createdAt)
            if result.last?.title == title {
                result[result.count - 1].entries.append(entry)
            } else {
                result.append((title, [entry]))
            }
        }
        return result
    }

    /// The shared header layout — Notes-style prominent group title. Used
    /// verbatim by both the in-flow headers and the sticky overlay so the
    /// hand-off between them is seamless.
    private func headerLabel(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 7)
    }

    /// The rows of one section. Separators are inset to the text edge and —
    /// the Notes detail — dropped on the selected row and its predecessor,
    /// so the accent tile floats free; the last row needs no separator
    /// because the next section header brings its own.
    @ViewBuilder
    private func rows(for entries: [DictationEntry]) -> some View {
        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
            let neighborsSelection = entry.id == selection
                || (index + 1 < entries.count && entries[index + 1].id == selection)
            DictationRow(entry: entry, isSelected: entry.id == selection)
                .contentShape(.rect)
                .onTapGesture { selection = entry.id }
                .accessibilityAddTraits(.isButton)
                .contextMenu { entryMenu(for: entry) }
                .overlay(alignment: .bottom) {
                    if index < entries.count - 1, !neighborsSelection {
                        Divider().padding(.leading, 12)
                    }
                }
                .padding(.horizontal, 10)
                .id(entry.id)
        }
    }

    /// Arrow-key navigation over the flat entry order, which matches the
    /// rendered order because sections group consecutively.
    private func moveSelection(_ direction: MoveCommandDirection) {
        let ids = store.entries.map(\.id)
        guard !ids.isEmpty else {
            return
        }
        let step: Int
        switch direction {
        case .down:
            step = 1

        case .up:
            step = -1

        default:
            return
        }
        if let selection, let index = ids.firstIndex(of: selection) {
            self.selection = ids[max(0, min(ids.count - 1, index + step))]
        } else {
            self.selection = ids.first
        }
    }

    // MARK: - Grouping

    // MARK: - Actions

    /// Deletes an entry and, when it was the selected one, moves the selection
    /// to a neighbouring row so the detail pane never blanks out mid-list — the
    /// classic Mail/Notes behaviour after a delete. Deleting an unselected row
    /// leaves this window's selection untouched.
    private func delete(_ id: DictationEntry.ID) {
        if selection == id {
            let ids = store.entries.map(\.id)
            if let index = ids.firstIndex(of: id) {
                selection = index + 1 < ids.count ? ids[index + 1]
                    : index > 0 ? ids[index - 1]
                    : nil
            }
        }
        store.delete(id)
    }

    /// Right-click menu for a sidebar entry: a Copy submenu holding whichever
    /// artifacts already exist — the audio file, the transcript, and the
    /// cleaned-up rewrite — followed by the destructive Delete. The submenu and
    /// its divider drop out entirely while nothing is copyable yet, e.g. during
    /// recording.
    @ViewBuilder
    private func entryMenu(for entry: DictationEntry) -> some View {
        let audioAvailable = entry.status != .recording
            && DictationArchive.hasRecording(for: entry.id)

        if audioAvailable || entry.transcript != nil || entry.cleanedUp != nil {
            Menu("Copy", systemImage: "doc.on.doc") {
                if audioAvailable {
                    Button("Audio", systemImage: "waveform") {
                        Pasteboard.copy(file: entry.audioURL)
                    }
                }
                if let transcript = entry.transcript {
                    Button("Transcript", systemImage: "text.quote") {
                        Pasteboard.copy(transcript)
                    }
                }
                if let cleanedUp = entry.cleanedUp {
                    Button("Cleaned Up", systemImage: "wand.and.stars") {
                        Pasteboard.copy(cleanedUp)
                    }
                }
            }
            Divider()
        }
        Button("Delete", systemImage: "trash", role: .destructive) {
            delete(entry.id)
        }
    }
}

// MARK: - Previews

#Preview("Sidebar") {
    @Previewable @State var selection: DictationEntry.ID? = DictationEntry.samples.first?.id
    NavigationSplitView {
        DictationListView(selection: $selection)
    } detail: {
        Color.clear
    }
    .frame(width: 300, height: 640)
    .environment(DictationStore(entries: DictationEntry.samples))
}
