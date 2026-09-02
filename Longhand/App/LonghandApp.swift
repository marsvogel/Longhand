//
//  LonghandApp.swift
//  Longhand
//
//  The app's entry point: it builds the shared store, hands it to every
//  window, and installs the menu commands. The window/tab machinery lives in
//  WindowTabCommands, the ⌘R command in RecordingCommands, and the app-level
//  window lifecycle in AppDelegate.
//

import SwiftUI

@main
struct LonghandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    private var appDelegate
    @State private var modelDownload: ModelDownloadManager
    @State private var store: DictationStore

    init() {
        let modelDownload = ModelDownloadManager()
        _modelDownload = State(initialValue: modelDownload)
        _store = State(initialValue: DictationStore.live(modelDownload: modelDownload))
    }

    var body: some Scene {
        // A real multi-window app. WindowGroup gives us the File-menu "New
        // Window" (⌘N) command and the Window menu's open-window list for free,
        // and lets ⌘N open as many independent windows as the user wants. Each
        // window owns its own selection (ContentView holds it); they all browse
        // and record into the one shared store. "New Dictation" now lives on ⌘R.
        WindowGroup("Longhand", id: "main") {
            ContentView()
                .environment(store)
                .environment(modelDownload)
                .modifier(WindowOpenerBridge(delegate: appDelegate))
                .task {
                    // start() is idempotent — a no-op once downloading or ready —
                    // so a second window re-running this at appear costs nothing.
                    modelDownload.start()
                }
        }
        .defaultSize(width: 1_040, height: 660)
        .commands {
            WindowTabCommands()
            RecordingCommands(store: store)
        }
    }
}

/// Hands SwiftUI's `openWindow` action to the app delegate, which needs it for
/// the Dock-icon reopen path but cannot reach the environment on its own.
/// Applied here rather than inside ContentView so the view layer stays unaware
/// of the delegate — and so previews, which never install this modifier, never
/// touch it either.
private struct WindowOpenerBridge: ViewModifier {
    let delegate: AppDelegate
    @Environment(\.openWindow)
    private var openWindow

    func body(content: Content) -> some View {
        content.onAppear {
            delegate.openNewWindow = { openWindow(id: "main") }
        }
    }
}
