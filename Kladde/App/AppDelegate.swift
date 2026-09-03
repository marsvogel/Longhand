//
//  AppDelegate.swift
//  Kladde
//

import AppKit

/// Owns the app-level window lifecycle that makes Kladde feel like a classic
/// macOS app: closing the last window doesn't quit, and a Dock-icon reopen with
/// no window on screen brings one back — while a ⌘-Tab switch never does.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// SwiftUI's `openWindow` action, handed over by `WindowOpenerBridge` from a
    /// live window's environment so the AppKit reopen path below can open a
    /// window — the action isn't reachable from an `NSApplicationDelegate` on
    /// its own.
    var openNewWindow: (() -> Void)?

    /// Kladde owns its window/tab behaviour Safari-and-Finder style instead of
    /// riding macOS's automatic tabbing. That automatic mode is the document-app
    /// convenience wired to the "Prefer tabs when opening documents" setting —
    /// and a `WindowGroup`'s windows default into it, which is why a non-document
    /// app like this one was tabbing on ⌘N under "Always". Turning it off frees
    /// ⌘N to always open a real window; the explicit ⌘T "New Tab" command and the
    /// tab-management menu items in `WindowTabCommands` restore the tab half. Set
    /// before any window exists, so the very first ⌘N already obeys it.
    func applicationWillFinishLaunching(_: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    /// Keeps Kladde running when its last window closes, instead of quitting.
    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }

    /// Fires on a Dock-icon click or Finder reopen — but never on a ⌘-Tab
    /// switch, which only activates the app. With nothing on screen we bring a
    /// window back; a merely minimized one is left for AppKit to deminiaturize
    /// so we don't stack a duplicate on top of it.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, !sender.windows.contains(where: \.isMiniaturized) {
            openNewWindow?()
        }
        return true
    }

    /// The reopen path for callers that are not AppKit — the menu bar item,
    /// which stays reachable with every window closed. It cannot use SwiftUI's
    /// `openWindow`: on a `WindowGroup` that opens an additional window rather
    /// than raising the one already there. The style mask keeps the search off
    /// the borderless status-item window, which is in `windows` too.
    func showMainWindow() {
        let app = NSApplication.shared
        app.activate()
        guard let window = app.windows.first(where: { $0.canBecomeMain && $0.styleMask.contains(.titled) }) else {
            openNewWindow?()
            return
        }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
    }

    /// whisper.cpp's Metal backend aborts on the way out: a C++ static destructor
    /// runs `ggml_metal_device_free`, which asserts its residency sets are empty —
    /// but the still-live whisper context holds them, and Swift never runs the
    /// transcriber actor's `deinit` at process exit to release it. A real quit
    /// (⌘Q or the menu — closing a window no longer terminates the app) routes
    /// through AppKit's normal `exit(0)`, which runs those destructors and crashes.
    ///
    /// Freeing the context first is not viable here: it lives inside an actor
    /// (async access) and freeing it mid-transcription would be a use-after-free.
    /// So we bypass the C runtime's atexit/static-destructor teardown entirely with
    /// `_exit`; the OS reclaims every Metal and file resource on process death
    /// regardless. Persisted state is unaffected — entries are written synchronously
    /// with atomic writes, and user defaults flush through cfprefsd out of process.
    func applicationWillTerminate(_: Notification) {
        _exit(EXIT_SUCCESS)
    }
}
