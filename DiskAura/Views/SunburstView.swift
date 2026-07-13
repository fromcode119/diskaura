import SwiftUI

/// DaisyDisk-style sunburst ring — the primary visualization for the Scan tab. Click a
/// segment to re-center the ring on it (same zoom-stack semantics as the old treemap,
/// different geometry). Rendered with Canvas since a full tree can produce hundreds of
/// arcs — the treemap used stacked SwiftUI shapes fine at its scale, Canvas is the safer
/// default here given the segment count can be much higher near the outer rings.
struct SunburstView: View {
    let root: FileNode
    /// Owned by the parent (`ScanView`) and shared with `FolderBreakdownView` — clicking a
    /// ring segment used to only update this view's own private state, leaving the file
    /// list below permanently stuck on the root's children. A `Binding` keeps both in sync.
    @Binding var zoomStack: [FileNode]
    @State private var hoveredSegment: SunburstLayout.Segment?

    /// Cached separately from `body` — recomputing the recursive layout on every hover
    /// event (which happens once per mouse-move pixel) pegged CPU at 100% and froze the
    /// main thread, confirmed live via Activity Monitor-style sampling. `layout()` only
    /// depends on `currentNode`, never on view geometry, so it's safe to compute once per
    /// zoom level and reuse across every redraw/hover/hit-test.
    @State private var segments: [SunburstLayout.Segment]

    /// Computes the first frame's segments synchronously at init instead of relying on
    /// `.onAppear` — that fired too late relative to first paint and produced an empty
    /// (colorless, spike-less) ring on first load.
    init(root: FileNode, zoomStack: Binding<[FileNode]>) {
        self.root = root
        self._zoomStack = zoomStack
        _segments = State(initialValue: SunburstLayout.layout(root: zoomStack.wrappedValue.last ?? root, maxRadius: 1))
    }

    private var currentNode: FileNode {
        zoomStack.last ?? root
    }

    private var breadcrumb: [FileNode] {
        [root] + zoomStack
    }

    var body: some View {
        VStack(spacing: 14) {
            breadcrumbBar

            GeometryReader { geo in
                let maxRadius = min(geo.size.width, geo.size.height) / 2 - 4
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                let scale = maxRadius / SunburstLayout.totalRadius

                ZStack {
                    Canvas { context, _ in
                        for segment in segments {
                            drawSegment(segment, scale: scale, center: center, in: &context)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        if let hit = segment(at: location, center: center, scale: scale) {
                            handleTap(hit.node)
                        }
                    }
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            let hit = segment(at: location, center: center, scale: scale)
                            if hit?.node.id != hoveredSegment?.node.id {
                                hoveredSegment = hit
                            }
                        case .ended:
                            hoveredSegment = nil
                        }
                    }

                    centerLabel
                }
            }
            // Flexible — let the container decide the height. The old minHeight:420 forced
            // the ring taller than a shorter container (e.g. 320 in Large & Old), so the
            // bottom of the ring got clipped.
            .frame(minHeight: 180, maxHeight: .infinity)
        }
        .onAppear { recomputeSegments() }
        .onChange(of: currentNode.id) { recomputeSegments() }
    }

    private func recomputeSegments() {
        segments = SunburstLayout.layout(root: currentNode, maxRadius: 1)
    }

    private func handleTap(_ node: FileNode) {
        guard node.isDirectory, !node.children.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.22)) {
            zoomStack.append(node)
        }
    }

    private func drawSegment(_ segment: SunburstLayout.Segment, scale: CGFloat, center: CGPoint, in context: inout GraphicsContext) {
        let inner = segment.innerRadius * scale
        let outer = segment.outerRadius * scale
        let isHovered = hoveredSegment?.node.id == segment.node.id

        var path = Path()
        path.addArc(center: center, radius: outer, startAngle: angle(segment.startAngle), endAngle: angle(segment.endAngle), clockwise: false)
        path.addArc(center: center, radius: inner, startAngle: angle(segment.endAngle), endAngle: angle(segment.startAngle), clockwise: true)
        path.closeSubpath()

        let base = FileKindColor.color(for: segment.node)
        let opacity = isHovered ? 1.0 : max(0.55, 1.0 - Double(segment.depth - 1) * 0.16)
        context.fill(path, with: .color(base.opacity(opacity)))
        context.stroke(path, with: .color(.black.opacity(0.35)), lineWidth: 1)

        // Only label the innermost ring (depth 1) — deeper rings get crowded fast with
        // overlapping text; hovering surfaces the name/size in the center label instead.
        let sweep = segment.endAngle - segment.startAngle
        let midRadius = (inner + outer) / 2
        if segment.depth == 1 && sweep > 0.28 && (outer - inner) > 20 {
            let mid = segment.startAngle + sweep / 2
            let labelPoint = CGPoint(
                x: center.x + midRadius * CGFloat(sin(mid)),
                y: center.y - midRadius * CGFloat(cos(mid))
            )
            context.draw(
                Text(segment.node.name).font(.system(size: 9, weight: .semibold)).foregroundColor(.white),
                at: labelPoint
            )
        }
    }

    private func angle(_ radians: Double) -> Angle {
        // Sunburst 0 is "up" (12 o'clock); Canvas arcs measure from 3 o'clock, so shift by -90°.
        .radians(radians - .pi / 2)
    }

    private func segment(at point: CGPoint, center: CGPoint, scale: CGFloat) -> SunburstLayout.Segment? {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = sqrt(dx * dx + dy * dy)
        var theta = atan2(dx, -dy) // matches the "up = 0, clockwise" convention used in layout
        if theta < 0 { theta += .pi * 2 }

        for segment in segments {
            let inner = segment.innerRadius * scale
            let outer = segment.outerRadius * scale
            guard distance >= inner && distance <= outer else { continue }
            if theta >= segment.startAngle && theta <= segment.endAngle {
                return segment
            }
        }
        return nil
    }

    private var centerLabel: some View {
        VStack(spacing: 3) {
            Text(hoveredSegment?.node.name ?? (currentNode.name.isEmpty ? "/" : currentNode.name))
                .font(.system(size: 13, weight: .bold))
                .lineLimit(1)
                .frame(maxWidth: SunburstLayout.holeRadius * 1.8)
                .multilineTextAlignment(.center)
            Text((hoveredSegment?.node.sizeBytes ?? currentNode.sizeBytes).formattedBytes)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(Theme.accent)
        }
    }

    private var breadcrumbBar: some View {
        HStack(spacing: 8) {
            // Explicit Back (up one level) — the breadcrumb was the only way to navigate
            // out before, which wasn't obvious. Disabled at the root.
            Button {
                guard !zoomStack.isEmpty else { return }
                withAnimation(.easeInOut(duration: 0.2)) { _ = zoomStack.removeLast() }
            } label: {
                Image(systemName: "chevron.backward.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(zoomStack.isEmpty ? .secondary.opacity(0.35) : Theme.accent)
            }
            .buttonStyle(.plain)
            .disabled(zoomStack.isEmpty)
            .help("Back — up one level")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(breadcrumb.enumerated()), id: \.element.id) { index, node in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                zoomStack = Array(breadcrumb.prefix(index + 1).dropFirst())
                            }
                        } label: {
                            Text(node.name.isEmpty ? "/" : node.name)
                                .font(.system(size: 13, weight: index == breadcrumb.count - 1 ? .bold : .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(index == breadcrumb.count - 1 ? Theme.accent : .secondary)
                    }
                }
            }
        }
    }
}
