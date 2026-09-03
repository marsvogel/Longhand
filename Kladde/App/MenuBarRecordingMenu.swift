//
//  MenuBarRecordingMenu.swift
//  Kladde
//
//  The status-item half of the recording intent. ⌘R in RecordingCommands needs
//  Kladde to be the active app; this needs nothing at all, so a dictation can
//  start mid-meeting from whatever app is in front.
//

import SwiftUI

/// The menu bar item's menu. Both titles follow the store, which is why they
/// live in a view: a `Scene` body's `@Observable` reads are not reliably
/// tracked, a view's are.
///
/// Starting from here deliberately opens nothing. The entry lands in the store
/// and appears in every window that is already open or opened later, so the
/// recording never interrupts what the user was looking at.
struct MenuBarRecordingMenu: View {
    let store: DictationStore
    let appDelegate: AppDelegate

    var body: some View {
        Button(store.isRecording ? "Stop Dictation" : "New Dictation") {
            if store.isRecording {
                store.stopRecording()
            } else {
                Task { @MainActor in
                    await store.startDictation()
                }
            }
        }
        Divider()
        Button("Open Kladde") {
            appDelegate.showMainWindow()
        }
    }
}

/// The status item's icon: a record dot while a dictation runs, so the menu bar
/// itself carries the one piece of state a window-less recording has.
struct MenuBarRecordingLabel: View {
    let store: DictationStore

    var body: some View {
        Image(systemName: store.isRecording ? "record.circle" : "waveform")
            .accessibilityLabel(store.isRecording ? "Kladde, recording" : "Kladde")
    }
}
