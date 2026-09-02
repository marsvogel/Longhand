//
//  FlowCard.swift
//  Longhand
//
//  Shared chrome for the stations of the flow diagram: a rounded card with
//  an icon + title header, an optional caption, and a trailing accessory
//  (copy button, spinner, …).
//

import SwiftUI

struct FlowCard<Trailing: View, Content: View>: View {
    let icon: String
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    trailing
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 22)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .flowCardChrome()
    }
}

// MARK: - Chrome modifier

private struct FlowCardChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor))
            )
    }
}

extension View {
    /// Card background used by all stations of the flow diagram.
    func flowCardChrome() -> some View {
        modifier(FlowCardChrome())
    }
}
