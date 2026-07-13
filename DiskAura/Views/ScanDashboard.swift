import SwiftUI
import AppKit

/// The Disk Scan hero — reproduced from CleanMyMac's widget layout: a big category donut
/// with a colored-dot legend, a row of sub-pills for headline stats, then a "Largest items"
/// list (their "Top Consumers") with per-row actions. Dark purple-gradient panels.
struct ScanDashboard: View {
    let root: FileNode
    let volume: VolumeStats?
    @ObservedObject var actionQueueVM: ActionQueueViewModel
    var onMove: (FileNode) -> Void = { _ in }

    @State private var trashBytes: Int64 = 0
    @State private var trashItems = 0
    @State private var confirmEmpty = false

    private var palette: [Color] {
        [Theme.moduleColor(.scan), Theme.moduleColor(.processes), Theme.moduleColor(.largeOldFiles),
         Theme.moduleColor(.duplicates), Theme.moduleColor(.uninstaller), Color(red: 0.55, green: 0.6, blue: 0.7)]
    }

    /// Top children of the scanned folder become the donut slices + legend rows, with the
    /// long tail folded into "Other" — same idea as CleanMyMac's Active/Wired/Compressed.
    private var segments: [DonutSegment] {
        let children = root.sortedChildren
        let top = Array(children.prefix(5))
        var segs: [DonutSegment] = top.enumerated().map { i, node in
            DonutSegment(id: node.id, label: node.name, sizeBytes: node.sizeBytes,
                         color: palette[i % palette.count])
        }
        let rest = children.dropFirst(5).reduce(Int64(0)) { $0 + $1.sizeBytes }
        if rest > 0 {
            segs.append(DonutSegment(id: "__other", label: "Other", sizeBytes: rest,
                                     color: palette[5]))
        }
        return segs
    }

    private var largestFiles: [FileNode] {
        Array(root.flattenFiles().sorted { $0.sizeBytes > $1.sizeBytes }.prefix(6))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            usagePanel
            largestPanel
        }
        .onAppear(perform: refreshTrash)
        .alert("Empty Trash?", isPresented: $confirmEmpty) {
            Button("Cancel", role: .cancel) {}
            Button("Empty Trash", role: .destructive) {
                TrashService.empty()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { refreshTrash() }
            }
        } message: {
            Text("This permanently deletes \(trashItems) item(s) in Trash (\(trashBytes.formattedBytes)).")
        }
    }

    private var usagePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Disk usage").font(.system(size: 15, weight: .semibold))

            HStack(alignment: .center, spacing: 26) {
                CategoryDonut(
                    segments: segments,
                    centerValue: root.sizeBytes.formattedBytes,
                    centerLabel: "in \(root.name)",
                    size: 156
                )
                DonutLegend(segments: segments)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                subPill(icon: "checkmark.circle.fill", label: "Available",
                        value: volume?.freeBytes.formattedBytes ?? "—",
                        color: Theme.moduleColor(.processes), action: nil)
                subPill(icon: "trash.fill", label: "Trash", value: trashBytes.formattedBytes,
                        color: Theme.moduleColor(.uninstaller),
                        action: trashItems > 0 ? { confirmEmpty = true } : nil)
                if let volume {
                    subPill(icon: "externaldrive.fill", label: "Disk used",
                            value: volume.usedBytes.formattedBytes,
                            color: Theme.moduleColor(.scan), action: nil)
                }
            }
        }
        .padding(18)
        .glassCard()
    }

    private func subPill(icon: String, label: String, value: String, color: Color, action: (() -> Void)?) -> some View {
        let content = HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 12)).foregroundColor(color)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.system(size: 10)).foregroundColor(.secondary)
                Text(value).font(.system(size: 13, weight: .semibold, design: .rounded))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))

        return Group {
            if let action {
                Button(action: action) { content }.buttonStyle(.plain)
            } else {
                content
            }
        }
    }

    private var largestPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Largest items").font(.system(size: 15, weight: .semibold))
            VStack(spacing: 0) {
                ForEach(largestFiles) { file in
                    LargestRow(file: file, actionQueueVM: actionQueueVM, onMove: onMove)
                    if file.id != largestFiles.last?.id {
                        Divider().padding(.leading, 44)
                    }
                }
                if largestFiles.isEmpty {
                    Text("No files found in this folder.")
                        .font(.system(size: 12)).foregroundColor(.secondary)
                        .padding(.vertical, 10)
                }
            }
        }
        .padding(18)
        .glassCard()
    }

    private func refreshTrash() {
        trashBytes = TrashService.size()
        trashItems = TrashService.itemCount()
    }
}

/// A "Top Consumers" style row — icon, name, path, size, and inline Reveal / Delete.
private struct LargestRow: View {
    let file: FileNode
    @ObservedObject var actionQueueVM: ActionQueueViewModel
    var onMove: (FileNode) -> Void = { _ in }

    private var isQueued: Bool { actionQueueVM.isQueued(file) }

    var body: some View {
        HStack(spacing: 11) {
            FileIconView(url: file.url, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(file.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                        .strikethrough(isQueued, color: Theme.moduleColor(.uninstaller))
                        .foregroundColor(isQueued ? .secondary : .primary)
                    if isQueued {
                        Text("TO DELETE").font(.system(size: 7, weight: .bold))
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Theme.moduleColor(.uninstaller).opacity(0.2)).foregroundColor(Theme.moduleColor(.uninstaller))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                Text(shortDir).font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 12)
            Text(file.sizeBytes.formattedBytes)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .frame(width: 78, alignment: .trailing)
            Button { NSWorkspace.shared.activateFileViewerSelecting([file.url]) } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.plain).foregroundColor(.secondary).help("Show in Finder")
            Button { onMove(file) } label: {
                Image(systemName: "arrow.right.circle")
            }
            .buttonStyle(.plain).foregroundColor(Theme.moduleColor(.scan)).help("Move to another folder / drive")
            Button {
                if isQueued { actionQueueVM.unqueue(file) } else { actionQueueVM.queue(file, kind: .trash) }
            } label: {
                Image(systemName: isQueued ? "arrow.uturn.backward" : "trash")
            }
            .buttonStyle(.plain).foregroundColor(Theme.moduleColor(.uninstaller))
            .help(isQueued ? "Remove from delete queue" : "Queue for deletion")
        }
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(isQueued ? Theme.moduleColor(.uninstaller).opacity(0.08) : .clear))
    }

    private var shortDir: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dir = file.url.deletingLastPathComponent().path
        if dir == home { return "~" }
        if dir.hasPrefix(home + "/") { return "~/" + dir.dropFirst(home.count + 1) }
        return dir
    }
}
