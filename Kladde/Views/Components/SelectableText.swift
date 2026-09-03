//
//  SelectableText.swift
//  Kladde
//
//  SwiftUI cannot select across `Text` views: each one is its own selection
//  target, so a document laid out as a stack of blocks can only ever be
//  selected a block at a time — a single bullet, never the list. One AppKit
//  text view makes the whole document one selectable run, and brings the
//  standard text services (⌘C, Look Up, Services) with it.
//

import SwiftUI

/// A read-only, selectable text view sized to the width SwiftUI proposes.
struct SelectableText: NSViewRepresentable {
    let text: NSAttributedString

    func makeNSView(context _: Context) -> NSTextView {
        // An explicit TextKit 1 stack. `usedRect(for:)` in sizeThatFits is the
        // exact height SwiftUI has to reserve for the text, and reaching for
        // `layoutManager` on a TextKit 2 view would silently downgrade it to
        // this same stack anyway — better to ask for it outright.
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(
            size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        )
        container.lineFragmentPadding = 0
        // The view's width is owned by SwiftUI; the container follows that
        // frame so wrapping always uses the card's real width, never the
        // zero-sized frame makeNSView starts with.
        container.widthTracksTextView = true
        container.heightTracksTextView = false
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)

        let view = NSTextView(frame: .zero, textContainer: container)
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.textContainerInset = .zero
        // The view never scrolls itself — it is laid out at full height inside
        // SwiftUI's ScrollView, which owns the scrolling.
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.minSize = .zero
        view.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        view.linkTextAttributes = [
            NSAttributedString.Key.foregroundColor: NSColor.linkColor,
            NSAttributedString.Key.underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        return view
    }

    func updateNSView(_ view: NSTextView, context _: Context) {
        apply(to: view)
        relayout(view, width: view.bounds.width)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: NSTextView,
        context _: Context
    ) -> CGSize? {
        // Measure at the width SwiftUI is about to give us. An unspecified or
        // infinite proposal used to fall through to nil, which left the
        // container at the zero-sized frame from makeNSView — every word on
        // its own line, a thin strip down the middle of the card.
        apply(to: nsView)
        let width = proposal.width.flatMap { value in
            value.isFinite && value > 0 ? value : nil
        } ?? max(nsView.bounds.width, 1)
        let height = relayout(nsView, width: width)
        return CGSize(width: width, height: height)
    }

    /// Replacing the storage drops whatever the user had selected, so it only
    /// happens when the text actually differs. SwiftUI re-runs update and
    /// layout on any change to the entry, and a selection that vanished
    /// mid-drag because a sibling value moved would be its own bug.
    private func apply(to view: NSTextView) {
        guard view.textStorage?.isEqual(to: text) != true else {
            return
        }
        view.textStorage?.setAttributedString(text)
    }

    /// Pins the view (and, through `widthTracksTextView`, the container) to
    /// `width`, then returns the height the laid-out text actually needs.
    @discardableResult
    private func relayout(_ view: NSTextView, width: CGFloat) -> CGFloat {
        guard width > 0,
              let container = view.textContainer,
              let layout = view.layoutManager
        else { return 0 }
        view.frame.size.width = width
        container.size = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let height = ceil(layout.usedRect(for: container).height)
        view.frame.size.height = height
        return height
    }
}
