import SwiftUI

/// Interactive squarified treemap with click-to-zoom and a breadcrumb trail back to root.
/// This is the hero of the Scan view — full-bleed, dominant, rendered before any stat
/// chrome, DaisyDisk-style: the visualization IS the interface, not one card among many.
struct TreemapView: View {
    let root: FileNode
    @State private var zoomStack: [FileNode] = []
    @State private var hoveredNode: FileNode?

    private var currentNode: FileNode {
        zoomStack.last ?? root
    }

    private var breadcrumb: [FileNode] {
        [root] + zoomStack
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                breadcrumbBar
                Spacer()
                if let hovered = hoveredNode {
                    Text("\(hovered.name)  ·  \(hovered.sizeBytes.formattedBytes)")
                        .font(Theme.TypeScale.mono)
                        .foregroundColor(.secondary)
                        .transition(.opacity)
                }
            }

            GeometryReader { geo in
                let layout = SquarifiedTreemap.layout(
                    nodes: currentNode.sortedChildren,
                    in: CGRect(origin: .zero, size: geo.size)
                )

                ZStack(alignment: .topLeading) {
                    ForEach(layout, id: \.node.id) { item in
                        TreemapCell(node: item.node, rect: item.rect)
                            .onTapGesture {
                                if item.node.isDirectory && !item.node.children.isEmpty {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        zoomStack.append(item.node)
                                    }
                                }
                            }
                            .onHover { isHovering in
                                if isHovering {
                                    hoveredNode = item.node
                                } else if hoveredNode?.id == item.node.id {
                                    hoveredNode = nil
                                }
                            }
                    }
                }
            }
            .frame(minHeight: 420, idealHeight: 520, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .onChange(of: root.id) {
            zoomStack.removeAll()
        }
    }

    private var breadcrumbBar: some View {
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

private struct TreemapCell: View {
    let node: FileNode
    let rect: CGRect

    private var base: Color { Theme.tagColor(node.tag) }

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(
                LinearGradient(
                    colors: [base.opacity(0.98), base.opacity(0.72)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.black.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1)
            .overlay(labelOverlay)
            .frame(width: max(rect.width - 2, 0), height: max(rect.height - 2, 0))
            .position(x: rect.midX, y: rect.midY)
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private var labelOverlay: some View {
        if rect.width > 50 && rect.height > 28 {
            VStack(spacing: 2) {
                Text(node.name)
                    .font(.system(size: 11, weight: .bold))
                    .lineLimit(1)
                if rect.height > 42 {
                    Text(node.sizeBytes.formattedBytes)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .opacity(0.85)
                }
            }
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
            .padding(4)
            .frame(width: max(rect.width - 6, 0), height: max(rect.height - 6, 0))
            .lineLimit(1)
        }
    }
}
