//
//  CopyButton.swift
//  Kladde
//

import SwiftUI

/// Borderless copy button that briefly morphs into a checkmark after use.
struct CopyButton: View {
    var help: String
    var action: () -> Void
    @State private var didCopy = false

    var body: some View {
        Button {
            action()
            didCopy = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                didCopy = false
            }
        } label: {
            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                .foregroundStyle(.secondary)
                .accessibilityLabel(help)
        }
        .buttonStyle(.borderless)
        .contentTransition(.symbolEffect(.replace))
        .help(help)
    }
}
