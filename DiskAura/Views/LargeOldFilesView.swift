import SwiftUI
import AppKit

enum LargeOldFilesSort: String, CaseIterable, Identifiable {
    case largest = "Largest"
    case oldest = "Oldest"

    var id: String { rawValue }
}

/// Curated top-25 view over the currently scanned tree — deliberately NOT a dump of
/// every file. "Biggest things eating space" only matters for the handful you'd
/// actually act on; a 200-row list is noise, not information.
struct LargeOldFilesView: View {
    let root: FileNode?
    @ObservedObject var actionQueueVM: ActionQueueViewModel
    @State private var sort: LargeOldFilesSort = .largest

    /// Cached, not recomputed inline in `body` — flattening + sorting a full scan tree
    /// (can be hundreds of thousands of files for something like /Applications) is
    /// expensive; doing it as a computed property re-ran it on every SwiftUI re-render,
    /// same class of bug that pegged the sunburst's CPU. Recomputed only when the root or
    /// sort mode actually changes.
    @State private var files: [FileNode] = []
    @State private var maxSize: Int64 = 1
    @State private var limit = 100
    /// Same interactive ring as Disk Scan — lets you narrow "largest files" down to a
    /// specific subfolder visually instead of only sorting the flat list.
    @State private var zoomStack: [FileNode] = []
    /// Multi-select for batch Move — a flat curated list is exactly where "grab several old
    /// files and move them to an archive drive, organized" makes sense (and it's the only
    /// path that sends >1 file to the organizer, so Smart/type/date grouping can actually group).
    @State private var selection: Set<String> = []
    @State private var moveRequest: MoveRequest?

    private static let limitOptions = [25, 50, 100, 250]

    private var selectedFiles: [FileNode] { files.filter { selection.contains($0.id) } }
    private var selectedBytes: Int64 { selectedFiles.reduce(0) { $0 + $1.sizeBytes } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Large & Old Files").font(Theme.TypeScale.title)
                    Text("Top \(limit) — not a full listing")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                HStack(spacing: 6) {
                    Text("Show").font(.system(size: 10)).foregroundColor(.secondary)
                    Picker("", selection: $limit) {
                        ForEach(Self.limitOptions, id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 170)
                }
                HStack(spacing: 6) {
                    Text("Sort").font(.system(size: 10)).foregroundColor(.secondary)
                    Picker("", selection: $sort) {
                        ForEach(LargeOldFilesSort.allCases) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 150)
                }
            }
            .padding(Theme.Spacing.md)

            Divider()

            if root == nil {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("Scan a folder first — this view reads from your last Disk Scan")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        if let root {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Explore").font(.system(size: 15, weight: .semibold))
                                    Spacer()
                                    if !zoomStack.isEmpty {
                                        Text("Showing: \((zoomStack.last ?? root).name)")
                                            .font(.system(size: 11)).foregroundColor(.secondary)
                                    }
                                }
                                SunburstView(root: root, zoomStack: $zoomStack)
                                    .frame(height: 420)
                                    .frame(maxWidth: .infinity)
                            }
                            .padding(18)
                            .glassCard()
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
                        }

                        VStack(spacing: 0) {
                            ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                                FileRow(rank: index + 1, file: file,
                                        fraction: Double(file.sizeBytes) / Double(maxSize),
                                        actionQueueVM: actionQueueVM,
                                        isChecked: selection.contains(file.id),
                                        onToggleCheck: { toggle(file.id) })
                                if file.id != files.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                    .padding(Theme.Spacing.lg)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !selection.isEmpty { moveBar }
        }
        .sheet(item: $moveRequest) { req in
            MoveSheet(items: req.items) {
                let movedIDs = Set(req.items.map { $0.id })
                files.removeAll { movedIDs.contains($0.id) }
                selection.subtract(movedIDs)
            }
        }
        .onAppear { recompute() }
        // Use the root NODE's object identity, not its path — a re-scan after a delete produces
        // a brand-new FileNode tree at the SAME path, so keying on `id` (the path) never fired
        // and the cached list kept showing files that were already deleted.
        .onChange(of: root.map(ObjectIdentifier.init)) { zoomStack.removeAll(); selection.removeAll(); recompute() }
        // Belt-and-suspenders: also recompute whenever the delete queue actually executes.
        .onChange(of: actionQueueVM.executedGeneration) { selection.removeAll(); recompute() }
        .onChange(of: sort) { recompute() }
        .onChange(of: limit) { recompute() }
        .onChange(of: zoomStack.last?.id) { recompute() }
    }

    private func toggle(_ id: String) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    private var moveBar: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(Theme.moduleColor(.scan).opacity(0.18)).frame(width: 34, height: 34)
                Image(systemName: "arrow.right.circle.fill").foregroundColor(Theme.moduleColor(.scan))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("\(selection.count) selected · \(selectedBytes.formattedBytes)")
                    .font(.system(size: 13, weight: .semibold))
                Text("Move to another folder or drive — optionally organized by type, date, or AI")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer()
            Button("Clear") { selection.removeAll() }
                .buttonStyle(.plain).font(.system(size: 12)).foregroundColor(.secondary)
            Button {
                moveRequest = MoveRequest(items: selectedFiles)
            } label: {
                Label("Move \(selection.count)…", systemImage: "arrow.right.circle")
                    .font(.system(size: 12.5, weight: .semibold))
            }
            .buttonStyle(.pill(Theme.moduleColor(.scan)))
        }
        .padding(.horizontal, Theme.Spacing.md).padding(.vertical, 11)
        .background(.ultraThinMaterial)
        .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.border), alignment: .top)
    }

    private func recompute() {
        guard let root else {
            files = []
            maxSize = 1
            return
        }
        let all = (zoomStack.last ?? root).flattenFiles()
        let computed: [FileNode]
        switch sort {
        case .largest:
            computed = all.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(limit).map { $0 }
        case .oldest:
            computed = all
                .filter { $0.modifiedAt != nil }
                .sorted { ($0.modifiedAt ?? .distantFuture) < ($1.modifiedAt ?? .distantFuture) }
                .prefix(limit)
                .map { $0 }
        }
        files = computed
        maxSize = computed.map(\.sizeBytes).max() ?? 1
    }
}

private struct FileRow: View {
    let rank: Int
    let file: FileNode
    let fraction: Double
    @ObservedObject var actionQueueVM: ActionQueueViewModel
    let isChecked: Bool
    let onToggleCheck: () -> Void
    private var isQueued: Bool { actionQueueVM.isQueued(file) }
    private var advice: CleanupAdvisor.Advice { CleanupAdvisor.advise(for: file) }

    private var adviceColor: Color {
        switch advice.level {
        case .safe: return Color(red: 0.30, green: 0.78, blue: 0.45)
        case .review: return Color(red: 0.95, green: 0.70, blue: 0.25)
        case .caution: return Color(red: 0.92, green: 0.42, blue: 0.40)
        }
    }

    @ViewBuilder private var adviceBadge: some View {
        HStack(spacing: 3) {
            Circle().fill(adviceColor).frame(width: 6, height: 6)
            Text(advice.level.rawValue).font(.system(size: 8, weight: .semibold))
                .foregroundColor(adviceColor)
        }
        .padding(.horizontal, 5).padding(.vertical, 1.5)
        .background(adviceColor.opacity(0.14))
        .clipShape(Capsule())
        .help("\(advice.reason) — \(advice.score)/100 safe to remove")
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggleCheck) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundColor(isChecked ? Theme.moduleColor(.scan) : .secondary.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help("Select for batch move")

            Text("\(rank)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 18, alignment: .trailing)

            ThumbnailView(url: file.url, size: 32)

            VStack(alignment: .leading, spacing: 3) {
                // Full name/path was unreadable when truncated with no way to see the rest —
                // `.help()` surfaces the full string on hover, and the folder path is now a
                // button that reveals the file directly instead of just being inert text.
                HStack(spacing: 5) {
                    Text(file.url.lastPathComponent)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .strikethrough(isQueued, color: Theme.moduleColor(.uninstaller))
                        .foregroundColor(isQueued ? .secondary : .primary)
                        .help(file.url.path)
                    if isQueued {
                        Text("TO DELETE").font(.system(size: 7, weight: .bold))
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Theme.moduleColor(.uninstaller).opacity(0.2)).foregroundColor(Theme.moduleColor(.uninstaller))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    } else {
                        adviceBadge
                    }
                }
                Button {
                    revealInFinder()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .font(.system(size: 9))
                        Text(shortDir)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let modified = file.modifiedAt {
                            Text("· \(modified.formatted(date: .abbreviated, time: .omitted))")
                                .font(.system(size: 11))
                        }
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Show in Finder: \(file.url.path)")
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.accent.opacity(0.6))
                        .frame(width: max(geo.size.width * fraction, 3), height: 4)
                }
                .frame(height: 4)
            }

            Spacer()

            Text(file.sizeBytes.formattedBytes)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .frame(width: 80, alignment: .trailing)

            HStack(spacing: 6) {
                Button {
                    NSWorkspace.shared.open(file.url)
                } label: {
                    Image(systemName: "eye")
                        .font(.system(size: 11))
                }
                .help("Open")

                Button {
                    revealInFinder()
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                }
                .help("Show in Finder")

                Button {
                    if isQueued { actionQueueVM.unqueue(file) } else { actionQueueVM.queue(file, kind: .trash) }
                } label: {
                    Image(systemName: isQueued ? "arrow.uturn.backward" : "trash")
                        .font(.system(size: 11))
                        .foregroundColor(isQueued ? Theme.moduleColor(.uninstaller) : .secondary)
                }
                .help(isQueued ? "Remove from delete queue" : "Queue for deletion")
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
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

    private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([file.url])
    }
}
