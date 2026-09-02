//
//  FlowConnectors.swift
//  Longhand
//
//  The lines between the stations of the flow diagram. While a stage is
//  active, its connector becomes a tinted line of dashes flowing
//  downstream; finished connectors are quiet solid lines.
//

import SwiftUI

/// Straight line from one card down to the next.
struct FlowConnector: View {
    var isActive: Bool

    var body: some View {
        Group {
            if isActive {
                TimelineView(.animation) { (timeline: TimelineViewDefaultContext) in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    VerticalLine()
                        .stroke(style: StrokeStyle(
                            lineWidth: 2,
                            lineCap: .round,
                            dash: [3, 6],
                            dashPhase: -CGFloat(time * 24).truncatingRemainder(dividingBy: 9)
                        ))
                        .foregroundStyle(.tint)
                }
            } else {
                VerticalLine()
                    .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .foregroundStyle(Color(nsColor: .separatorColor))
            }
        }
        .frame(height: 28)
    }
}

private struct VerticalLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}
