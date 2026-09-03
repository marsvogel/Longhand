//
//  FlowCard.swift
//  Kladde
//
//  Shared chrome for the stations of the flow diagram: a rounded card with
//  an icon + title header, an optional caption, and a trailing accessory
//  (copy button, spinner, …). When given an `isExpanded` binding the header
//  becomes a disclosure control, so a finished dictation can collapse the
//  stages the user is not reading.
//

import SwiftUI

struct FlowCard<Trailing: View, Content: View>: View {
    let icon: String
    let title: String
    var subtitle: String?
    /// `nil` keeps the card always open — recording chrome, short error states.
    var isExpanded: Binding<Bool>?
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: expanded ? 10 : 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let isExpanded {
                    Button {
                        withAnimation(.smooth) {
                            isExpanded.wrappedValue.toggle()
                        }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 16, alignment: .center)
                                .rotationEffect(.degrees(expanded ? 90 : 0))
                            label
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(title)
                    .accessibilityValue(expanded ? "Expanded" : "Collapsed")
                    .accessibilityHint(
                        expanded ? "Collapse this section" : "Expand this section"
                    )
                } else {
                    label
                }
                Spacer(minLength: 8)
                trailing
            }
            if expanded {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .flowCardChrome()
    }

    private var expanded: Bool {
        isExpanded?.wrappedValue ?? true
    }

    private var label: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                if let subtitle, expanded {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
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
