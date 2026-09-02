//
//  InlineSpinner.swift
//  Longhand
//

import SwiftUI

/// A small indeterminate spinner backed directly by `NSProgressIndicator`.
///
/// SwiftUI's own `ProgressView` (spinning style) bridges to an internal
/// `AppKitProgressView` whose auto-layout emits a stream of "maximum length …
/// doesn't satisfy min <= max" warnings whenever the surrounding row animates
/// to a sub-pixel height — which is exactly what happens while a card slides
/// in next to "Transcribing…". Wrapping `NSProgressIndicator` ourselves with
/// fixed integer size constraints keeps the layout exact and the console clean.
struct InlineSpinner: NSViewRepresentable {
    /// Side length in points; 16 matches `.controlSize(.small)`.
    var size: CGFloat = 16

    func makeNSView(context _: Context) -> NSProgressIndicator {
        let indicator = NSProgressIndicator()
        indicator.style = .spinning
        indicator.controlSize = .small
        indicator.isIndeterminate = true
        indicator.usesThreadedAnimation = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            indicator.widthAnchor.constraint(equalToConstant: size),
            indicator.heightAnchor.constraint(equalToConstant: size)
        ])
        indicator.startAnimation(nil)
        return indicator
    }

    func updateNSView(_: NSProgressIndicator, context _: Context) {
        // The indicator animates itself; no state flows back into it.
    }
}
