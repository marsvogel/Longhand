//
//  MarkdownText.swift
//  Longhand
//
//  Renders the Markdown the rewrite agent produces. SwiftUI's `Text` only
//  interprets inline Markdown — bold, italic, code — and prints headings,
//  bullets and table pipes as literal characters. Foundation's parser does
//  understand the block structure and hands it over as `presentationIntent`
//  runs, so this view groups those runs back into blocks and lays them out.
//

import SwiftUI

/// Markdown as a stack of blocks: headings, paragraphs, lists and tables.
///
/// Parsing is lenient on purpose. The rewrite streams in token by token, so
/// most of the time this view is handed a half-finished document — an open
/// list, a table missing its last row — and still has to draw something.
struct MarkdownText: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(MarkdownBlock.blocks(of: markdown).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case let .heading(level, text):
            // Deliberately close to body size: the card header above already
            // carries `.subheadline`, and a heading inside the text must not
            // outweigh it.
            Text(text)
                .font(.callout.weight(level <= 2 ? .semibold : .medium))
                .padding(.top, 2)

        case let .paragraph(text):
            Text(text)
                .font(.callout)
                .lineSpacing(3)

        case let .list(items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(item.marker)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 14, alignment: .trailing)
                        Text(item.text)
                            .font(.callout)
                            .lineSpacing(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.leading, CGFloat(item.depth) * 16)
                }
            }

        case let .table(rows):
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.cells.enumerated()), id: \.offset) { _, cell in
                            Text(cell)
                                .font(.callout)
                                .fontWeight(row.isHeader ? .semibold : .regular)
                        }
                    }
                    if row.isHeader {
                        Divider().gridCellUnsizedAxes(.horizontal)
                    }
                }
            }
        }
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
