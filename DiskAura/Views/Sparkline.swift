import SwiftUI

/// A tiny filled line chart for a rolling series (CPU%, etc.) — the little "over time"
/// graph the reference apps (iStat, Stats) put next to every live metric.
struct Sparkline: View {
    let values: [Double]
    var color: Color = Theme.accent
    var maxValue: Double? = nil

    var body: some View {
        GeometryReader { geo in
            let vals = values.isEmpty ? [0] : values
            let peak = max(maxValue ?? (vals.max() ?? 1), 1)
            let stepX = vals.count > 1 ? geo.size.width / CGFloat(vals.count - 1) : geo.size.width
            let points = vals.enumerated().map { i, v in
                CGPoint(x: CGFloat(i) * stepX,
                        y: geo.size.height - CGFloat(min(v / peak, 1)) * geo.size.height)
            }

            ZStack {
                // filled area
                Path { p in
                    guard let first = points.first else { return }
                    p.move(to: CGPoint(x: first.x, y: geo.size.height))
                    p.addLine(to: first)
                    for pt in points.dropFirst() { p.addLine(to: pt) }
                    p.addLine(to: CGPoint(x: points.last!.x, y: geo.size.height))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [color.opacity(0.35), color.opacity(0.02)],
                                     startPoint: .top, endPoint: .bottom))
                // line
                Path { p in
                    guard let first = points.first else { return }
                    p.move(to: first)
                    for pt in points.dropFirst() { p.addLine(to: pt) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }
        }
    }
}
