//
//  RecordingCommands.swift
//  Longhand
//

import SwiftUI

/// Published by the focused window so the ⌘R recording command can start a
/// dictation in *that* window and select it there. Equatable so it slots into
/// any focused-value overload; the closure is always current, so every instance
/// compares equal.
struct NewDictationAction: Equatable {
    let perform: () -> Void

    static func == (_: Self, _: Self) -> Bool { true }
}

private struct NewDictationActionKey: FocusedValueKey {
    typealias Value = NewDictationAction
}

extension FocusedValues {
    var newDictation: NewDictationAction? {
        get { self[NewDictationActionKey.self] }
        set { self[NewDictationActionKey.self] = newValue }
    }
}

/// The File-menu recording command (⌘R): one shortcut that both starts a
/// dictation and stops the running one.
///
/// While a dictation runs, ⌘R stops it — whichever window is focused, and even
/// with none, since only one recording exists at a time. Otherwise it starts
/// one: with a window focused, through that window's action, so the new entry
/// is selected right there; with none — the app running, every window closed —
/// by starting the dictation and opening a window, which then selects the
/// just-created entry (the newest) as it appears. Always enabled, so ⌘R works
/// even from an empty, window-less state.
struct RecordingCommands: Commands {
    let store: DictationStore
    @Environment(\.openWindow)
    private var openWindow
    @FocusedValue(\.newDictation)
    private var newDictationInFocusedWindow

    var body: some Commands {
        CommandGroup(before: .newItem) {
            RecordingMenuItem(store: store, toggle: toggle)
        }
    }

    private func toggle() {
        if store.isRecording {
            store.stopRecording()
        } else if let newDictationInFocusedWindow {
            newDictationInFocusedWindow.perform()
        } else {
            Task { @MainActor in
                await store.startDictation()
                openWindow(id: "main")
            }
        }
    }
}

/// Only the item's *title* has to follow the store, and a `Commands` body is
/// not a view — its `@Observable` reads are not reliably tracked. The button
/// therefore lives in a view, while the focused value and the window opener
/// stay up in the command struct, the placement SwiftUI documents for them.
private struct RecordingMenuItem: View {
    let store: DictationStore
    let toggle: () -> Void

    var body: some View {
        Button(store.isRecording ? "Stop Dictation" : "New Dictation", action: toggle)
            .keyboardShortcut("r", modifiers: .command)
    }
}
