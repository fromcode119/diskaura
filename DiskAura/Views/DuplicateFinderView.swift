import SwiftUI
import AppKit

struct DuplicateFinderView: View {
    @StateObject private var viewModel = DuplicateFinderViewModel()
    @ObservedObject var actionQueueVM: ActionQueueViewModel
    /// The folder from the last Disk Scan — auto-used here (and by Large & Old Files)
    /// so picking a folder once covers all three views instead of re-selecting per tab.
    let sharedRootURL: URL?
    @State private var keepStrategy: DuplicateKeepStrategy = .smart

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            if viewModel.isScanning {
                VStack(spacing: 14) {
                    if viewModel.progressFraction > 0 {
                        ProgressView(value: viewModel.progressFraction)
                            .frame(width: 260)
                    } else {
                        ProgressView()
                    }
                    Text(viewModel.progressText.isEmpty
                        ? "Scanning \(viewModel.scannedRoot?.lastPathComponent ?? "")…"
                        : viewModel.progressText)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Button("Cancel") { viewModel.cancel() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.groups.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text(viewModel.scannedRoot == nil
                        ? "Choose a folder to scan for duplicate files"
                        : "No duplicates found")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        heroRow
                        HStack(spacing: 12) {
                            Text("\(viewModel.groups.count) duplicate groups")
                                .font(.system(size: 12, weight: .semibold))
                            Spacer()
                            HStack(spacing: 5) {
                                Text("Auto-keep").font(.system(size: 10)).foregroundColor(.secondary)
                                Picker("", selection: $keepStrategy) {
                                    ForEach(DuplicateKeepStrategy.allCases) { Text($0.rawValue).tag($0) }
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                                .frame(width: 240)
                            }
                            Text("Reclaimable: \(viewModel.totalReclaimable.formattedBytes)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Theme.moduleColor(.processes))
                        }

                        // One-click across EVERY group — including ones scrolled off-screen that
                        // the lazy per-card onAppear hasn't queued yet.
                        HStack(spacing: 10) {
                            Button {
                                queueAllDuplicates()
                            } label: {
                                Label("Smart Clean — queue \(nonKeeperCount) extra copies", systemImage: "wand.and.stars")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .buttonStyle(.pill(Theme.moduleColor(.duplicates)))
                            Text("Keeps the “\(keepStrategy.rawValue.lowercased())” copy in each group. Review the queue before anything is deleted.")
                                .font(.system(size: 11)).foregroundColor(.secondary)
                            Spacer()
                        }

                        ForEach(viewModel.groups) { group in
                            DuplicateGroupCard(group: group, actionQueueVM: actionQueueVM, keepStrategy: keepStrategy)
                        }
                    }
                    .padding(Theme.Spacing.lg)
                }
            }
        }
        .onAppear { autoScanIfNeeded() }
        .onChange(of: sharedRootURL) { autoScanIfNeeded() }
        // After the delete queue runs, re-scan so removed duplicates disappear from the list.
        .onChange(of: actionQueueVM.executedGeneration) {
            if let root = viewModel.scannedRoot { viewModel.scan(url: root) }
        }
    }

    /// Total non-keeper copies across every group under the current strategy — what a
    /// Smart Clean would queue.
    private var nonKeeperCount: Int {
        viewModel.groups.reduce(0) { $0 + max($1.files.count - 1, 0) }
    }

    private static let donutPalette: [Color] = [
        Theme.moduleColor(.duplicates), Theme.moduleColor(.scan), Theme.moduleColor(.largeOldFiles),
        Theme.moduleColor(.processes), Theme.moduleColor(.uninstaller), Color(red: 0.31, green: 0.84, blue: 0.90),
    ]

    /// Reclaimable space grouped by file kind (Images / Videos / Documents / …) — the same
    /// circular breakdown used elsewhere, so you see WHAT the duplicates are at a glance.
    private var kindSegments: [DonutSegment] {
        var byKind: [String: Int64] = [:]
        for group in viewModel.groups {
            guard let first = group.files.first else { continue }
            byKind[MoveService.category(for: first.url), default: 0] += group.reclaimableBytes
        }
        return byKind.sorted { $0.value > $1.value }.enumerated().map { i, kv in
            DonutSegment(id: kv.key, label: kv.key, sizeBytes: kv.value, color: Self.donutPalette[i % Self.donutPalette.count])
        }
    }

    private var heroRow: some View {
        StatHero(
            segments: kindSegments,
            centerValue: viewModel.totalReclaimable.formattedBytes,
            centerLabel: "reclaimable",
            tiles: [
                StatTileData(title: "Duplicate groups", value: "\(viewModel.groups.count)", glow: Theme.moduleColor(.scan), icon: "square.stack.3d.up.fill"),
                StatTileData(title: "Extra copies", value: "\(nonKeeperCount)", glow: Theme.moduleColor(.duplicates), icon: "doc.on.doc.fill"),
                StatTileData(title: "Reclaimable", value: viewModel.totalReclaimable.formattedBytes, glow: Theme.moduleColor(.processes), icon: "arrow.down.circle.fill", valueColor: Theme.moduleColor(.processes)),
                StatTileData(title: "Queued", value: "\(actionQueueVM.pendingActions.count)", glow: Theme.moduleColor(.uninstaller), icon: "trash.fill"),
            ]
        )
    }

    /// Queues every non-keeper copy across ALL groups (keeping the strategy's chosen copy),
    /// so a single click covers groups that were never scrolled into view.
    private func queueAllDuplicates() {
        for group in viewModel.groups {
            guard let keeper = group.keeper(keepStrategy) else { continue }
            for file in group.files {
                let node = FileNode(url: file.url, isDirectory: false, sizeBytes: file.sizeBytes, tag: .clean)
                if file.id == keeper.id { actionQueueVM.unqueue(node) }
                else { actionQueueVM.queue(node, kind: .trash) }
            }
        }
    }

    /// Uses the same folder as the last Disk Scan automatically — only if the user
    /// hasn't explicitly picked a different folder here already.
    private func autoScanIfNeeded() {
        guard viewModel.scannedRoot == nil, let sharedRootURL else { return }
        viewModel.scan(url: sharedRootURL)
    }

    private var toolbar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Duplicate Finder").font(Theme.TypeScale.title)
                if let root = viewModel.scannedRoot {
                    Text(root.path)
                        .font(Theme.TypeScale.mono)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            Picker("", selection: $viewModel.mode) {
                ForEach(DuplicateMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .help(viewModel.mode.detail)
            .onChange(of: viewModel.mode) {
                if let root = viewModel.scannedRoot { viewModel.scan(url: root) }
            }
            if !viewModel.isScanning {
                Button("Choose Folder…") { chooseFolder() }
            }
        }
        .padding(Theme.Spacing.md)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.scan(url: url)
        }
    }
}

/// One duplicate group as a row of visual previews side by side — actually lets you
/// compare the copies (especially photos) instead of reading a list of paths and
/// guessing which one to keep.
private struct DuplicateGroupCard: View {
    let group: DuplicateGroup
    @ObservedObject var actionQueueVM: ActionQueueViewModel
    let keepStrategy: DuplicateKeepStrategy
    /// Auto-applied so a whole group cleans with one click ("group delete all if we want,
    /// not one by one"). Re-applies when the auto-keep strategy changes. Still fully
    /// overridable — the explicit Keep/Undo/Delete per tile always wins afterward.
    @State private var appliedStrategy: DuplicateKeepStrategy?

    private func node(for file: DuplicateFile) -> FileNode {
        FileNode(url: file.url, isDirectory: false, sizeBytes: file.sizeBytes, tag: .clean)
    }

    /// Queues every OTHER copy in the group for deletion and un-queues the keeper.
    private func keepOnly(_ keeper: DuplicateFile) {
        for file in group.files {
            let n = node(for: file)
            if file.id == keeper.id {
                actionQueueVM.unqueue(n)
            } else {
                actionQueueVM.queue(n, kind: .trash)
            }
        }
    }

    private func applyStrategy() {
        guard let keeper = group.keeper(keepStrategy) else { return }
        appliedStrategy = keepStrategy
        keepOnly(keeper)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("\(group.files.count) copies · \(group.sizeBytes.formattedBytes) each")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("Saves \(group.reclaimableBytes.formattedBytes)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.moduleColor(.processes))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(group.files) { file in
                        DuplicateFileTile(
                            file: file,
                            isKeeper: !actionQueueVM.isQueued(node(for: file)),
                            isQueued: actionQueueVM.isQueued(node(for: file)),
                            onKeepOnly: { keepOnly(file) },
                            onToggleDelete: {
                                let n = node(for: file)
                                if actionQueueVM.isQueued(n) {
                                    actionQueueVM.unqueue(n)
                                } else {
                                    actionQueueVM.queue(n, kind: .trash)
                                }
                            }
                        )
                    }
                }
                .padding(.bottom, 2)
            }

            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 11))
                Text("Auto-keeping the “\(keepStrategy.rawValue.lowercased())” copy, the rest queued to delete — change the keeper anytime, nothing is deleted until you review the queue.")
                    .font(.system(size: 11))
            }
            .foregroundStyle(.tertiary)
        }
        .padding(18)
        .glassCard()
        .onAppear {
            if appliedStrategy == nil { applyStrategy() }
        }
        .onChange(of: keepStrategy) { applyStrategy() }
    }
}

/// No copy is auto-designated "the one to keep" — every copy looks identical to the
/// scanner, and only the user can judge which one actually matters (e.g. the one in the
/// right album vs. a stray export). Two equal choices per copy — "Keep only this" (queues
/// the others) and "Delete" (queues just this one) — plus the full path always visible so
/// you can tell the copies apart. Nothing is queued until the user picks.
private struct DuplicateFileTile: View {
    let file: DuplicateFile
    let isKeeper: Bool
    let isQueued: Bool
    let onKeepOnly: () -> Void
    let onToggleDelete: () -> Void

    private static let tileSize: CGFloat = 168
    private var deleteColor: Color { Theme.moduleColor(.uninstaller) }
    private var keepColor: Color { Theme.moduleColor(.processes) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                ThumbnailView(url: file.url, size: Self.tileSize)
                    .onTapGesture(count: 2) { openFile() }
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isQueued ? deleteColor : keepColor, lineWidth: isQueued ? 3 : 2)
                    )
                if isQueued {
                    Text("QUEUED TO DELETE")
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(deleteColor)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(6)
                } else if isKeeper {
                    Text("KEEPING")
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(keepColor)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(6)
                }
            }
            .help("Double-click to open")

            Text(file.url.lastPathComponent)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
                .frame(width: Self.tileSize, alignment: .leading)

            // Full path, wrapping across as many lines as needed — the user said they
            // couldn't see the folder name; truncating it defeats the whole point of
            // telling the copies apart. Shown relative to home for readability.
            Text(shortPath)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: Self.tileSize, alignment: .leading)
                .help(file.url.path)

            HStack(spacing: 6) {
                Button { openFile() } label: { Image(systemName: "eye") }
                    .help("Open")
                Button { revealInFinder() } label: { Image(systemName: "folder") }
                    .help("Show in Finder")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            HStack(spacing: 6) {
                Button {
                    onKeepOnly()
                } label: {
                    Text("Keep only this")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .help("Keep this copy and queue the others for deletion")

                Button {
                    onToggleDelete()
                } label: {
                    Text(isQueued ? "Undo" : "Delete")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .tint(isQueued ? deleteColor : nil)
                .help(isQueued ? "Remove this copy from the delete queue" : "Queue just this copy for deletion")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(width: Self.tileSize)
        }
        .frame(width: Self.tileSize)
    }

    private var shortPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dir = file.url.deletingLastPathComponent().path
        if dir == home { return "~" }
        if dir.hasPrefix(home + "/") { return "~/" + dir.dropFirst(home.count + 1) }
        return dir
    }

    private func openFile() {
        NSWorkspace.shared.open(file.url)
    }

    private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([file.url])
    }
}
