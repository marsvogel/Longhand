//
//  WindowTabCommands.swift
//  Longhand
//

import SwiftUI

/// The native tab commands, placed by hand because Longhand manages its own
/// tabbing (see `AppDelegate.applicationWillFinishLaunching`). "New Tab" (⌘T)
/// opens a window from the group and folds it into the frontmost window; the
/// rest forward to the key window's built-in `NSWindow` tab methods through the
/// responder chain, so the real tab bar, tab overview (⇧⌘\) and window-merging
/// all behave exactly as in Safari and Finder.
struct WindowTabCommands: Commands {
    @Environment(\.openWindow)
    private var openWindow

    var body: some Commands {
        // "New Tab" and "Close Window" sit next to "New Window" in the File
        // menu. The default ⌘W "Close" already shuts just the current tab
        // (Finder/Safari style, since `performClose` on a tab closes only it);
        // ⇧⌘W closes the whole window with all of its tabs.
        CommandGroup(after: .newItem) {
            Button("New Tab") { newTab() }
                .keyboardShortcut("t", modifiers: .command)
            Button("Close Window") { closeWindow() }
                .keyboardShortcut("w", modifiers: [.command, .shift])
        }
        // Tab bar + overview live in the View menu, as macOS places them.
        CommandGroup(after: .toolbar) {
            Button("Show Tab Bar") { relayToKeyWindow(#selector(NSWindow.toggleTabBar(_:))) }
            Button("Show All Tabs") { relayToKeyWindow(#selector(NSWindow.toggleTabOverview(_:))) }
                .keyboardShortcut("\\", modifiers: [.command, .shift])
        }
        // Moving and merging tabs live in the Window menu.
        CommandGroup(after: .windowArrangement) {
            Button("Move Tab to New Window") { relayToKeyWindow(#selector(NSWindow.moveTabToNewWindow(_:))) }
            Button("Merge All Windows") { relayToKeyWindow(#selector(NSWindow.mergeAllWindows(_:))) }
        }
    }

    /// Opens a new window from the group and adopts it as a tab of whichever
    /// window was frontmost when ⌘T was pressed. With nothing open it simply
    /// stays a standalone window.
    private func newTab() {
        guard let host = NSApp.keyWindow else {
            openWindow(id: "main")
            return
        }
        let existing = Set(NSApp.windows.map(ObjectIdentifier.init))
        openWindow(id: "main")
        // Fold the new window into the tab group in this same runloop turn —
        // before it is drawn — so it never flashes as a standalone window first.
        // openWindow creates the NSWindow synchronously; the window only paints
        // at the end of the turn, so reparenting it now beats the first frame.
        if let tab = newWindow(notIn: existing) {
            host.addTabbedWindow(tab, ordered: .above)
            tab.makeKeyAndOrderFront(nil)
        } else {
            // Rare fallback: it wasn't created synchronously; adopt it next turn
            // (this path may still flash briefly).
            DispatchQueue.main.async {
                guard let tab = newWindow(notIn: existing) else {
                    return
                }
                host.addTabbedWindow(tab, ordered: .above)
                tab.makeKeyAndOrderFront(nil)
            }
        }
    }

    /// The content window that has appeared since `existing` was captured.
    private func newWindow(notIn existing: Set<ObjectIdentifier>) -> NSWindow? {
        NSApp.windows.first { !existing.contains(ObjectIdentifier($0)) && $0.canBecomeMain }
    }

    /// Closes the frontmost window and every tab in its group; a lone, untabbed
    /// window just closes. The plain ⌘W "Close" already handles a single tab.
    private func closeWindow() {
        guard let key = NSApp.keyWindow else {
            return
        }
        for window in key.tabGroup?.windows ?? [key] {
            window.performClose(nil)
        }
    }

    /// Sends a standard tab action down the responder chain to the key window,
    /// which implements these natively regardless of the automatic-tabbing flag.
    private func relayToKeyWindow(_ selector: Selector) {
        NSApp.sendAction(selector, to: nil, from: nil)
    }
}
