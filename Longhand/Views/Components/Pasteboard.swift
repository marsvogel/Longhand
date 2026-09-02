//
//  Pasteboard.swift
//  Longhand
//

import AppKit

/// Puts a dictation's artifacts on the general pasteboard. Lives with the view
/// components because copying is only ever triggered from the UI — the copy
/// buttons on the flow cards and the sidebar's context menu.
enum Pasteboard {
    static func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    static func copy(file url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([url as NSURL])
    }
}
