import SwiftUI
import AppKit

struct FolderBreakdownView: View {
    let node: FileNode
    @ObservedObject var actionQueueVM: ActionQueueViewModel
    var onMove: (FileNode) -> Void = { _ in }
    /// Multi-select is owned by the parent (ContentView) so the batch action bar can live
    /// pinned at the bottom of the whole tab instead of scrolling away inside the list.
    @Binding var selection: Set<String>
    @State private var searchText = ""
    /// Filter the list by the classifier's tag (Keep / Clearable / Archive / System) — this is
    /// what makes those colored dots actionable: filter to "Clearable", then select & delete.
    @State private var tagFilter: NodeTag?

    private var filteredChildren: [FileNode] {
        var list = node.sortedChildren
        if let tagFilter { list = list.filter { $0.tag == tagFilter } }
        if !searchText.isEmpty { list = list.filter { matches($0, query: searchText.lowercased()) } }
        return list
    }

    private func tagChip(_ tag: NodeTag?, label: String, color: Color) -> some View {
        let active = tagFilter == tag
        return Button {
            tagFilter = (tagFilter == tag) ? nil : tag
        } label: {
            HStack(spacing: 4) {
                if tag != nil { Circle().fill(color).frame(width: 6, height: 6) }
                Text(label).font(.system(size: 10, weight: .medium))
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(active ? color.opacity(0.25) : Color.white.opacity(0.05)))
            .foregroundColor(active ? .primary : .secondary)
        }
        .buttonStyle(.plain)
    }

    /// Recursively checks whether this node or any descendant matches, so a search
    /// for e.g. "target" still surfaces the parent row even if the row itself isn't collapsed.
    private func matches(_ node: FileNode, query: String) -> Bool {
        if node.name.lowercased().contains(query) { return true }
        return node.children.contains { matches($0, query: query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    SectionEyebrow(title: "Breakdown")
                    Text(node.path)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    TextField("Filter by name…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .frame(width: 180)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.05)))
            }

            // Tag filter chips — double as a legend for the colored dots on each row.
            HStack(spacing: 6) {
                tagChip(nil, label: "All", color: .secondary)
                ForEach(NodeTag.allCases) { tag in
                    tagChip(tag, label: tag.label, color: Theme.tagColor(tag))
                }
                Spacer()
            }

            VStack(spacing: 0) {
                ForEach(filteredChildren) { child in
                    FolderRow(node: child, parentSize: node.sizeBytes, actionQueueVM: actionQueueVM,
                              onMove: onMove, searchQuery: searchText, selection: $selection)
                    if child.id != filteredChildren.last?.id {
                        Divider()
                    }
                }
            }
        }
    }
}

private struct FolderRow: View {
    let node: FileNode
    let parentSize: Int64
    @ObservedObject var actionQueueVM: ActionQueueViewModel
    var onMove: (FileNode) -> Void = { _ in }
    var searchQuery: String = ""
    @Binding var selection: Set<String>
    @State private var expanded = false
    /// `FileNode` is a plain (non-Observable) class — see FileNode.swift for why. Bumping
    /// this forces this row to redraw and re-read `node.tag` after the rare user re-tag action.
    @State private var tagVersion = 0

    private var fraction: Double {
        parentSize > 0 ? Double(node.sizeBytes) / Double(parentSize) : 0
    }
    private var isChecked: Bool { selection.contains(node.path) }
    private var isQueued: Bool { actionQueueVM.isQueued(node) }

    private var visibleChildren: [FileNode] {
        guard !searchQuery.isEmpty else { return node.sortedChildren }
        let query = searchQuery.lowercased()
        return node.sortedChildren.filter { matches($0, query: query) }
    }

    private func matches(_ node: FileNode, query: String) -> Bool {
        if node.name.lowercased().contains(query) { return true }
        return node.children.contains { matches($0, query: query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    if isChecked { selection.remove(node.path) } else { selection.insert(node.path) }
                } label: {
                    Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15))
                        .foregroundColor(isChecked ? Theme.moduleColor(.scan) : .secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help("Select for batch move or delete")

                ZStack(alignment: .bottomTrailing) {
                    FileIconView(url: node.url, size: 20)
                    Circle()
                        .fill(Theme.tagColor(node.tag))
                        .id(tagVersion)
                        .frame(width: 7, height: 7)
                        .overlay(Circle().stroke(Theme.panelBackground, lineWidth: 1.5))
                }
                .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(node.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                            .strikethrough(isQueued, color: Theme.moduleColor(.uninstaller))
                            .foregroundColor(isQueued ? .secondary : .primary)
                        if isQueued {
                            Text("TO DELETE").font(.system(size: 7, weight: .bold))
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Theme.moduleColor(.uninstaller).opacity(0.2))
                                .foregroundColor(Theme.moduleColor(.uninstaller))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    Text(node.path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Text(node.sizeBytes.formattedBytes)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .frame(width: 70, alignment: .trailing)

                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.tagColor(node.tag))
                        .frame(width: max(geo.size.width * fraction, 2), height: 5)
                        .frame(maxHeight: .infinity, alignment: .center)
                }
                .frame(width: 60, height: 5)

                inlineActions

                if node.isDirectory && !node.children.isEmpty {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 12)
                } else {
                    Color.clear.frame(width: 12)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 8).fill(isQueued ? Theme.moduleColor(.uninstaller).opacity(0.10) : .clear))
            .contentShape(Rectangle())
            .onTapGesture {
                if node.isDirectory && !node.children.isEmpty {
                    withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                }
            }

            if expanded || !searchQuery.isEmpty {
                Divider().padding(.leading, 34)
                VStack(spacing: 0) {
                    ForEach(visibleChildren.prefix(200)) { child in
                        FolderRow(node: child, parentSize: node.sizeBytes, actionQueueVM: actionQueueVM,
                                  onMove: onMove, searchQuery: searchQuery, selection: $selection)
                            .padding(.leading, 20)
                        if child.id != visibleChildren.prefix(200).last?.id {
                            Divider().padding(.leading, 54)
                        }
                    }
                }
            }
        }
    }

    /// Visible, one-click actions — no more hunting through a "…" menu. Open (preview in the
    /// default app), Reveal in Finder, Move, and queue-to-Trash are all right there on the row.
    private var inlineActions: some View {
        HStack(spacing: 8) {
            if !node.isDirectory {
                Button { NSWorkspace.shared.open(node.url) } label: {
                    Image(systemName: "eye").font(.system(size: 11))
                }
                .buttonStyle(.plain).foregroundColor(.secondary).help("Open / preview")
            }
            Button { NSWorkspace.shared.activateFileViewerSelecting([node.url]) } label: {
                Image(systemName: "folder").font(.system(size: 11))
            }
            .buttonStyle(.plain).foregroundColor(.secondary).help("Show in Finder")
            Button { onMove(node) } label: {
                Image(systemName: "arrow.right.circle").font(.system(size: 11))
            }
            .buttonStyle(.plain).foregroundColor(.secondary).help("Move to…")
            Button {
                if isQueued { actionQueueVM.unqueue(node) } else { actionQueueVM.queue(node, kind: .trash) }
                tagVersion += 1
            } label: {
                Image(systemName: isQueued ? "arrow.uturn.backward" : "trash").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundColor(isQueued ? Theme.moduleColor(.uninstaller) : .secondary)
            .help(isQueued ? "Remove from delete queue" : "Queue for deletion")
        }
    }
}
