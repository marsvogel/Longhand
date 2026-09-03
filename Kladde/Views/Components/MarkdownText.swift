//
//  MarkdownText.swift
//  Kladde
//
//  Renders the Markdown the rewrite agent produces. SwiftUI's `Text` only
//  interprets inline Markdown — bold, italic, code — and prints headings,
//  bullets and table pipes as literal characters. Foundation's parser does
//  understand the block structure and hands it over as `presentationIntent`
//  runs, so this view groups those runs back into blocks and lays them out.
//
//  The blocks become one attributed string in a single AppKit text view rather
//  than a SwiftUI stack of `Text`s, so that a selection can span the whole
//  document — see SelectableText for why that costs a text view.
//

import SwiftUI

/// Markdown as one selectable document: headings, paragraphs, lists and tables.
///
/// Parsing is lenient on purpose. The rewrite streams in token by token, so
/// most of the time this view is handed a half-finished document — an open
/// list, a table missing its last row — and still has to draw something.
struct MarkdownText: View {
    let markdown: String

    var body: some View {
        SelectableText(text: MarkdownBlock.attributedDocument(of: markdown))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Blocks

/// One laid-out block of the document. Inline formatting stays inside the
/// `AttributedString`s, where `Text` renders it without further help.
enum MarkdownBlock {
    case heading(level:
        Int, text: AttributedString)

    case list(items:
        [Item])

    case paragraph(text:
        AttributedString)

    case table(rows:
        [Row])

    struct Item {
        /// "•" for bullets, "1." and up for ordered lists.
        let marker: String
        let depth: Int
        let text: AttributedString
    }

    struct Row {
        let isHeader: Bool
        let cells: [AttributedString]
    }
}

extension MarkdownBlock {
    /// A run of text plus the intent chain it sits under, innermost first.
    private struct Line {
        let intents: [PresentationIntent.IntentType]
        var text: AttributedString
    }

    /// Parses `markdown` into blocks, falling back to a single paragraph of
    /// plain text if Foundation cannot make sense of it at all.
    static func blocks(of markdown: String) -> [MarkdownBlock] {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        guard let document = try? AttributedString(markdown: markdown, options: options) else {
            return [.paragraph(text: AttributedString(markdown))]
        }
        return assemble(lines(of: document))
    }

    /// Splits the document at every change of the innermost block, which is
    /// what separates one paragraph, heading or table cell from the next.
    private static func lines(of document: AttributedString) -> [Line] {
        var lines: [Line] = []
        for run in document.runs {
            let intents = run.presentationIntent?.components ?? []
            let slice = AttributedString(document[run.range])
            if let last = lines.last, last.intents.first?.identity == intents.first?.identity,
               !lines.isEmpty, intents.first != nil {
                lines[lines.count - 1].text += slice
            } else {
                lines.append(Line(intents: intents, text: slice))
            }
        }
        return lines
    }

    /// Folds the lines into blocks, gathering consecutive list items and table
    /// cells — which arrive one line each — back into a single list or table.
    ///
    /// A container closes as soon as its identity changes, so a bulleted list
    /// directly followed by a numbered one stays two lists rather than one.
    private static func assemble(_ lines: [Line]) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var items: [Item] = []
        var rows: [Row] = []
        var cells: [AttributedString] = []
        var rowIsHeader = false
        var openRow: Int?
        var openList: Int?

        func closeRow() {
            guard !cells.isEmpty else {
                return
            }
            rows.append(Row(isHeader: rowIsHeader, cells: cells))
            cells = []
            openRow = nil
        }
        func closeList() {
            guard !items.isEmpty else {
                return
            }
            blocks.append(.list(items: items))
            items = []
            openList = nil
        }
        func closeTable() {
            closeRow()
            guard !rows.isEmpty else {
                return
            }
            blocks.append(.table(rows: rows))
            rows = []
        }

        for line in lines {
            let text = line.text
            guard !text.characters.isEmpty else { continue }

            if line.intents.contains(where: \.isTableCell) {
                closeList()
                let row = line.intents.first(where: \.isTableRow)
                if row?.identity != openRow { closeRow() }
                openRow = row?.identity
                rowIsHeader = row?.isTableHeaderRow ?? false
                cells.append(text)
                continue
            }

            if let ordinal = line.intents.compactMap(\.listOrdinal).first {
                closeTable()
                // The innermost list decides the marker, the outermost decides
                // where one list ends and the next begins.
                if line.intents.last(where: \.isList)?.identity != openList { closeList() }
                openList = line.intents.last(where: \.isList)?.identity
                items.append(
                    Item(
                        marker: line.intents.first(where: \.isList)?.isOrderedList == true
                            ? "\(ordinal)." : "•",
                        depth: max(0, line.intents.count(where: \.isList) - 1),
                        text: text
                    )
                )
                continue
            }

            closeList()
            closeTable()

            if let level = line.intents.compactMap(\.headerLevel).first {
                blocks.append(.heading(level: level, text: text))
            } else {
                blocks.append(.paragraph(text: text))
            }
        }

        closeList()
        closeTable()
        return blocks
    }
}

// MARK: - Layout

/// The measurements mirror the SwiftUI stack this replaced: `.callout`
/// throughout, 3pt of line spacing, 10pt between blocks, and a heading barely
/// heavier than the body because the card header above already carries
/// `.subheadline` and a heading inside the text must not outweigh it.
extension MarkdownBlock {
    private static let bodyFont = NSFont.preferredFont(forTextStyle: .callout)

    private var attributed: NSAttributedString {
        switch self {
        case let .heading(level, text):
            Self.styled(
                text,
                font: .systemFont(ofSize: Self.bodyFont.pointSize, weight: level <= 2 ? .semibold : .medium),
                style: Self.paragraphStyle(before: 8, after: 4)
            )

        case let .list(items):
            Self.attributedList(items)

        case let .paragraph(text):
            Self.styled(text, font: Self.bodyFont, style: Self.paragraphStyle())

        case let .table(rows):
            Self.attributedTable(rows)
        }
    }

    /// The whole document as one string. Blocks are joined by a single newline
    /// and kept apart by the paragraph spacing in their styles, so no blank
    /// line ends up in what the user copies.
    static func attributedDocument(of markdown: String) -> NSAttributedString {
        let document = NSMutableAttributedString()
        for block in blocks(of: markdown) {
            if document.length > 0 {
                document.append(NSAttributedString(string: "\n"))
            }
            document.append(block.attributed)
        }
        return document
    }

    private static func paragraphStyle(
        before: CGFloat = 0,
        after: CGFloat = 10,
        indent: CGFloat = 0,
        hanging: CGFloat = 0
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        style.paragraphSpacingBefore = before
        style.paragraphSpacing = after
        style.firstLineHeadIndent = indent
        // A wrapped list item lines up under its own text rather than running
        // back under the bullet, which is what the HStack used to do for free.
        style.headIndent = indent + hanging
        if hanging > 0 {
            style.tabStops = [NSTextTab(textAlignment: .left, location: indent + hanging)]
        }
        return style
    }

    private static func attributedList(_ items: [Item]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, item) in items.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "\n"))
            }
            let style = paragraphStyle(
                after: index == items.count - 1 ? 10 : 4,
                indent: CGFloat(item.depth) * 16,
                hanging: 20
            )
            result.append(
                NSAttributedString(
                    string: "\(item.marker)\t",
                    attributes: [
                        .font: bodyFont,
                        .paragraphStyle: style,
                        .foregroundColor: NSColor.secondaryLabelColor
                    ]
                )
            )
            result.append(styled(item.text, font: bodyFont, style: style))
        }
        return result
    }

    /// Columns are tab stops, not a grid: a cell wider than its column pushes
    /// the rest of the row right instead of wrapping. The rewrite only tabulates
    /// short values, and a text view that can be selected as one document is
    /// worth more here than a table that always lines up.
    private static func attributedTable(_ rows: [Row]) -> NSAttributedString {
        let columns = max(rows.map(\.cells.count).max() ?? 1, 2)
        let result = NSMutableAttributedString()
        for (index, row) in rows.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "\n"))
            }
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 3
            style.paragraphSpacing = index == rows.count - 1 ? 10 : 4
            style.tabStops = (1..<columns).map { column in
                NSTextTab(textAlignment: .left, location: CGFloat(column) * 120)
            }
            let font: NSFont = row.isHeader
                ? .systemFont(ofSize: bodyFont.pointSize, weight: .semibold)
                : bodyFont
            for (column, cell) in row.cells.enumerated() {
                if column > 0 {
                    result.append(
                        NSAttributedString(string: "\t", attributes: [.paragraphStyle: style])
                    )
                }
                result.append(styled(cell, font: font, style: style))
            }
        }
        return result
    }

    /// Foundation's parser records inline emphasis as `inlinePresentationIntent`
    /// and leaves the font alone: `Text` resolves those runs itself, AppKit does
    /// not, so they are mapped onto the block's font here.
    private static func styled(
        _ text: AttributedString,
        font: NSFont,
        style: NSParagraphStyle
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for run in text.runs {
            let intent = run.inlinePresentationIntent ?? []
            var runFont = font
            if intent.contains(.stronglyEmphasized) {
                runFont = .systemFont(ofSize: font.pointSize, weight: .semibold)
            }
            if intent.contains(.emphasized) {
                runFont = NSFontManager.shared.convert(runFont, toHaveTrait: .italicFontMask)
            }
            if intent.contains(.code) {
                runFont = .monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
            }
            var attributes: [NSAttributedString.Key: Any] = [
                .font: runFont,
                .paragraphStyle: style,
                .foregroundColor: NSColor.labelColor
            ]
            if intent.contains(.strikethrough) {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            if let link = run.link {
                attributes[.link] = link
            }
            result.append(
                NSAttributedString(
                    string: String(text[run.range].characters),
                    attributes: attributes
                )
            )
        }
        return result
    }
}

// MARK: - Intent predicates

/// Reading `PresentationIntent.IntentType` means pattern-matching an enum with
/// associated values, which does not compose into conditions. These wrap the
/// handful of kinds this view cares about into plain properties.
private extension PresentationIntent.IntentType {
    var isList: Bool {
        switch kind {
        case .orderedList, .unorderedList:
            true

        default:
            false
        }
    }

    var isOrderedList: Bool {
        if case .orderedList = kind {
            return true
        }
        return false
    }

    var isTableCell: Bool {
        if case .tableCell = kind {
            return true
        }
        return false
    }

    var isTableRow: Bool {
        switch kind {
        case .tableRow, .tableHeaderRow:
            true

        default:
            false
        }
    }

    var isTableHeaderRow: Bool {
        if case .tableHeaderRow = kind {
            return true
        }
        return false
    }

    var listOrdinal: Int? {
        if case let .listItem(ordinal) = kind {
            return ordinal
        }
        return nil
    }

    var headerLevel: Int? {
        if case let .header(level) = kind {
            return level
        }
        return nil
    }
}

// MARK: - Previews

#Preview("Structured") {
    MarkdownText(
        markdown: """
            Der Termin verschiebt sich auf Dienstag, weil die Migration \
            länger braucht als geplant.

            ## Offene Punkte

            - Der Cache läuft nach dem Deployment **zu früh** ab
            - Rollback der Postgres-Migration ist ungetestet

            ## Reihenfolge

            1. Erst deployen
            2. Dann messen

            | Umgebung | Status |
            | -------- | ------ |
            | Staging  | grün   |
            | Prod     | rot    |
            """
    )
    .padding(24)
    .frame(width: 360)
    .background(Color(nsColor: .windowBackgroundColor))
}

#Preview("Plain paragraph") {
    MarkdownText(markdown: "Der Termin verschiebt sich auf Dienstag.")
        .padding(24)
        .frame(width: 360)
        .background(Color(nsColor: .windowBackgroundColor))
}

#Preview("Mid-stream") {
    MarkdownText(
        markdown: """
            ## Offene Punkte

            - Der Cache läuft zu früh ab
            - Rollback der Postgres-Mig
            """
    )
    .padding(24)
    .frame(width: 360)
    .background(Color(nsColor: .windowBackgroundColor))
}
