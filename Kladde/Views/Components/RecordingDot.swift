//
//  RecordingDot.swift
//  Kladde
//

import SwiftUI

/// Pulsing red dot shown while a dictation is being recorded.
struct RecordingDot: View {
    var diameter: CGFloat = 8

    var body: some View {
        Circle()
            .fill(.red)
            .frame(width: diameter, height: diameter)
            .phaseAnimator([1.0, 0.3]) { view, opacity in
                view.opacity(opacity)
            } animation: { _ in
                .easeInOut(duration: 0.7)
            }
    }
}
