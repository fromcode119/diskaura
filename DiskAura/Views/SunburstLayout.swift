import Foundation
import CoreGraphics

/// Ring-segment geometry for a DaisyDisk-style sunburst — each depth level is an annulus,
/// each child within it is an arc sized proportionally to its byte size. Mirrors
/// `SquarifiedTreemap`'s shape (a pure `layout` function) but computes angles/radii
/// instead of rectangles.
enum SunburstLayout {
    struct Segment {
        let node: FileNode
        let startAngle: Double // radians, 0 = up (12 o'clock), clockwise
        let endAngle: Double
        let innerRadius: CGFloat
        let outerRadius: CGFloat
        let depth: Int
    }

    /// Caps rendered depth — DaisyDisk doesn't draw the whole tree at once, only a few
    /// rings; deeper levels appear after clicking to re-center.
    static let maxDepth = 3
    private static let ringThickness: CGFloat = 46
    private static let innerHoleRadius: CGFloat = 44

    static func layout(root: FileNode, maxRadius: CGFloat) -> [Segment] {
        var segments: [Segment] = []
        layoutLevel(
            nodes: root.sortedChildren.filter { $0.sizeBytes > 0 },
            depth: 1,
            startAngle: 0,
            endAngle: .pi * 2,
            innerRadius: innerHoleRadius,
            segments: &segments
        )
        return segments
    }

    private static func layoutLevel(
        nodes: [FileNode],
        depth: Int,
        startAngle: Double,
        endAngle: Double,
        innerRadius: CGFloat,
        segments: inout [Segment]
    ) {
        guard depth <= maxDepth, !nodes.isEmpty else { return }

        let total = nodes.reduce(0.0) { $0 + Double($1.sizeBytes) }
        guard total > 0 else { return }

        let outerRadius = innerRadius + ringThickness
        let angularSpan = endAngle - startAngle
        var cursor = startAngle

        for node in nodes {
            let fraction = Double(node.sizeBytes) / total
            let sweep = angularSpan * fraction
            // Skip slivers too thin to see or tap — matches the treemap's minWidth guard.
            guard sweep > 0.008 else { cursor += sweep; continue }

            let segment = Segment(
                node: node,
                startAngle: cursor,
                endAngle: cursor + sweep,
                innerRadius: innerRadius,
                outerRadius: outerRadius,
                depth: depth
            )
            segments.append(segment)

            if node.isDirectory && !node.children.isEmpty {
                layoutLevel(
                    nodes: node.sortedChildren.filter { $0.sizeBytes > 0 },
                    depth: depth + 1,
                    startAngle: cursor,
                    endAngle: cursor + sweep,
                    innerRadius: outerRadius,
                    segments: &segments
                )
            }

            cursor += sweep
        }
    }

    /// Total radius the ring occupies at full depth — used to size/center the view.
    static var totalRadius: CGFloat {
        innerHoleRadius + ringThickness * CGFloat(maxDepth)
    }

    static var holeRadius: CGFloat { innerHoleRadius }
}
