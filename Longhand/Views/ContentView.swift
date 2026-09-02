//
//  ContentView.swift
//  Longhand
//

import SwiftUI

struct ContentView: View {
    @Environment(DictationStore.self)
    private var store
    /// This window's own selection. It deliberately lives here, not in the
    /// shared store, so each window navigates the common dictation list
    /// independently.
    @State private var selection: DictationEntry.ID?
    /// Whether this window shows only the detail column. Owned here (instead
    /// of leaving the split view to manage itself) because the window's
    /// minimum width depends on it; per-window scene storage keeps a restored
    /// window in the shape it was closed in.
    @SceneStorage("hidesSidebar")
    private var hidesSidebar = false

    var body: some View {
        @Bindable var store = store
        NavigationSplitView(columnVisibility: columnVisibility) {
            DictationListView(selection: $selection)
        } detail: {
            // The detail column never renders narrower than the 390pt minimal
            // window, so the content looks the same at the floor with or
            // without the sidebar. Ideal matches the 1040pt default window
            // minus the sidebar's ideal 270.
            detail
                .navigationSplitViewColumnWidth(min: 390, ideal: 770)
        }
        .navigationTitle("Longhand")
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // The same toggle ⌘R performs, so the window's most prominent
                // recording control never disagrees with the shortcut. The
                // label — not just the tooltip — carries the state, since the
                // overflow menu, the icon-and-text toolbar and VoiceOver all
                // read it and none of them surface `help`.
                let isRecording = store.isRecording
                Button {
                    if isRecording {
                        store.stopRecording()
                    } else {
                        startNewDictation()
                    }
                } label: {
                    Label(
                        isRecording ? "Stop Dictation" : "New Dictation",
                        systemImage: isRecording ? "stop.fill" : "mic"
                    )
                }
                .tint(isRecording ? .red : nil)
                .help(isRecording ? "Stop and transcribe (⌘R)" : "Start a new dictation (⌘R)")
            }
        }
        .alert("Microphone Access Needed", isPresented: $store.micPermissionDenied) {
            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text("Longhand needs the microphone to record dictations. Grant access in System Settings, then try again.")
        }
        .alert(
            "Recording Failed",
            isPresented: Binding(
                get: { store.recordingError != nil },
                set: { if !$0 { store.recordingError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.recordingError ?? "")
        }
        // Mail-style resizing: the window's minimum depends on the sidebar.
        // With it open the floor is its 180pt minimum plus the 8pt gutter the
        // floating sidebar keeps beside the content plus the detail's 390 —
        // the squeezed-in-between states simply don't exist. Hiding the
        // sidebar (⌃⌘S) unlocks the true 390pt minimum.
        .frame(minWidth: hidesSidebar ? 390 : 578, minHeight: 500)
        .onAppear {
            // A fresh window lands on the most recent dictation, matching the
            // old single-window launch; afterwards its navigation is its own.
            if selection == nil { selection = store.entries.first?.id }
        }
        .onChange(of: store.entries.map(\.id)) { _, ids in
            // Reconcile after a delete — including one made in another window —
            // so this window never points at an entry that is gone.
            if let selection, !ids.contains(selection) { self.selection = nil }
        }
        // Hand this window's "start + select" to the ⌘R menu command so, when
        // this window is focused, its start half records right here. The stop
        // half needs no window — the command reaches the store directly.
        .focusedSceneValue(\.newDictation, NewDictationAction(perform: startNewDictation))
    }

    /// The split view's column visibility, backed by `hidesSidebar` so the
    /// toolbar toggle and ⌃⌘S drive the window-minimum switch above.
    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { hidesSidebar ? .detailOnly : .all },
            set: { hidesSidebar = $0 == .detailOnly }
        )
    }

    private var subtitle: String {
        let count = store.entries.count
        return count == 1 ? "1 Dictation" : "\(count) Dictations"
    }

    @ViewBuilder private var detail: some View {
        if let entry = store.entries.first(where: { $0.id == selection }) {
            DictationDetailView(entry: entry) {
                store.finishDictation(entry.id)
            }
        } else if store.entries.isEmpty {
            ContentUnavailableView {
                Label("No Dictations", systemImage: "waveform.badge.mic")
            } description: {
                Text("Click the microphone in the toolbar — or press ⌘R — to record your first dictation.")
            }
        } else {
            ContentUnavailableView {
                Label("No Dictation Selected", systemImage: "waveform")
            } description: {
                Text("Choose a dictation from the list to see its transcript and variants.")
            }
        }
    }

    /// Starts a recording and selects it in this window.
    private func startNewDictation() {
        Task { @MainActor in
            if let id = await store.startDictation() { selection = id }
        }
    }
}

// MARK: - Previews

#Preview("Longhand") {
    ContentView()
        .environment(DictationStore(entries: DictationEntry.samples))
        .environment(ModelDownloadManager(state: .ready))
}

#Preview("Recording") {
    // The recording state of the window chrome: the toolbar's mic has turned
    // into the red stop control, while the detail column shows the live audio
    // card.
    ContentView()
        .environment(DictationStore(entries: [.previewRecording] + DictationEntry.samples))
        .environment(ModelDownloadManager(state: .ready))
}

#Preview("Empty") {
    ContentView()
        .environment(DictationStore())
        .environment(ModelDownloadManager(state: .ready))
}

#Preview("Narrow Window") {
    // The window floor while the sidebar is open: 180 sidebar + 8 gutter +
    // 390 detail. (The 390pt sidebar-hidden floor is DictationDetailView's
    // "Narrow" preview — scene storage defaults the sidebar to visible here.)
    ContentView()
        .environment(DictationStore(entries: DictationEntry.samples))
        .environment(ModelDownloadManager(state: .ready))
        .frame(width: 578, height: 620)
}
