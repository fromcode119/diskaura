import SwiftUI

/// One slice of the category donut — a labelled, colored proportion of the whole. `valueText`
/// overrides how the legend prints the value (default is a byte size); non-size donuts (e.g.
/// counts of login items) pass their own string so the legend doesn't say "5 bytes".
struct DonutSegment: Identifiable {
    let id: String
    let label: String
    let sizeBytes: Int64
    let color: Color
    var valueText: String? = nil
}

/// Multi-segment donut with a value in the middle — the signature visual of CleanMyMac's
/// Memory widget (Active / Wired / Compressed arcs), reused here for disk categories. Pairs
/// with `DonutLegend` for the colored-dot list beside it.
struct CategoryDonut: View {
    let segments: [DonutSegment]
    let centerValue: String
    let centerLabel: String
    var size: CGFloat = 156
    var lineWidth: CGFloat = 20

    private var total: Double {
        max(1, segments.reduce(0) { $0 + Double(max(0, $1.sizeBytes)) })
    }

    private struct Arc: Identifiable {
        let id: String
        let start: Double
        let end: Double
        let color: Color
    }

    private var arcs: [Arc] {
        var running = 0.0
        return segments.map { seg in
            let frac = Double(max(0, seg.sizeBytes)) / total
            let arc = Arc(id: seg.id, start: running, end: running + frac, color: seg.color)
            running += frac
            return arc
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.06), lineWidth: lineWidth)
            ForEach(arcs) { arc in
                Circle()
                    .trim(from: arc.start, to: max(arc.start + 0.002, arc.end))
                    .stroke(arc.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 1) {
                Text(centerValue)
                    .font(.system(size: size * 0.17, weight: .bold, design: .rounded))
                Text(centerLabel)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}

/// The colored-dot legend beside the donut — one row per segment: dot, label, size, and a
/// thin proportion bar, exactly like CleanMyMac's memory breakdown list.
struct DonutLegend: View {
    let segments: [DonutSegment]
    /// Cap the number of rows so the legend always fits the fixed-height hero card; anything past
    /// the cap is aggregated into a single "Others" row instead of overflowing / being clipped.
    var maxRows: Int = 6

    private var total: Int64 {
        max(1, segments.reduce(0) { $0 + max(0, $1.sizeBytes) })
    }

    private var displayed: [DonutSegment] {
        guard segments.count > maxRows else { return segments }
        let sorted = segments.sorted { $0.sizeBytes > $1.sizeBytes }
        let head = Array(sorted.prefix(maxRows - 1))
        let rest = sorted.dropFirst(maxRows - 1)
        let othersBytes = rest.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let others = DonutSegment(id: "__others", label: "\(rest.count) others",
                                  sizeBytes: othersBytes, color: Color.secondary)
        return head + [others]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            ForEach(displayed) { seg in
                HStack(spacing: 10) {
                    Circle().fill(seg.color).frame(width: 9, height: 9)
                    Text(seg.label)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 12)
                    Text(seg.valueText ?? seg.sizeBytes.formattedBytes)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Text("\(Int((Double(seg.sizeBytes) / Double(total) * 100).rounded()))%")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .frame(width: 30, alignment: .trailing)
                }
            }
        }
    }
}
