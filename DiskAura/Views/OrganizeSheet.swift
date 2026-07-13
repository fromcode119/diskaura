import SwiftUI
import AppKit

/// Wraps a folder so `.sheet(item:)` can present the organizer.
struct OrganizeRequest: Identifiable {
    let id = UUID()
    let folder: URL
}

/// Tidy a folder's own loose files into subfolders IN PLACE — the "just organize my Downloads"
/// flow. Shows a live preview of the exact (possibly nested) tree before committing.
struct OrganizeSheet: View {
    let folder: URL
    var onCompleted: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    @State private var scheme: OrganizeScheme = .byType
    @State private var plan: [OrganizePlanItem] = []
    @State private var isPlanning = false
    @State private var isRunning = false
    @State private var error: String?
    @State private var expanded: Set<String> = []
    @State private var aiProgress: (done: Int, total: Int)?

    /// One destination folder in the preview: its path, the files headed there, and totals.
    private struct PreviewGroup: Identifiable {
        let path: String
        let items: [OrganizePlanItem]
        var id: String { path }
        var count: Int { items.count }
        var bytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }
    }

    /// Grouped preview, largest folder first — so the biggest reorganization is up top.
    private var previewGroups: [PreviewGroup] {
        Dictionary(grouping: plan, by: { $0.folderPath })
            .map { PreviewGroup(path: $0.key, items: $0.value) }
            .sorted { $0.bytes > $1.bytes }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9).fill(Theme.moduleColor(.largeOldFiles).opacity(0.18)).frame(width: 34, height: 34)
                    Image(systemName: "square.grid.3x3.fill").foregroundColor(Theme.moduleColor(.largeOldFiles))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Organize folder").font(.system(size: 15, weight: .semibold))
                    Text(folder.path).font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Button("Close") { dismiss() }.buttonStyle(.bordered)
            }
            .padding(Theme.Spacing.md)
            Divider()

            ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("SCHEME").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary).tracking(0.7)
                ForEach(OrganizeScheme.allCases) { option in
                    Button { scheme = option; recompute() } label: {
                        HStack(spacing: 10) {
                            Image(systemName: scheme == option ? "largecircle.fill.circle" : "circle")
                                .foregroundColor(scheme == option ? Theme.moduleColor(.largeOldFiles) : .secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 6) {
                                    Text(option.rawValue).font(.system(size: 12.5, weight: .medium))
                                    if option.isNested {
                                        Text("NESTED").font(.system(size: 7, weight: .bold))
                                            .padding(.horizontal, 4).padding(.vertical, 1)
                                            .background(Theme.moduleColor(.largeOldFiles).opacity(0.2))
                                            .foregroundColor(Theme.moduleColor(.largeOldFiles))
                                            .clipShape(RoundedRectangle(cornerRadius: 3))
                                    }
                                }
                                Text(option.detail).font(.system(size: 10)).foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 3).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Text("PREVIEW").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary).tracking(0.7)
                    .padding(.top, 4)
                previewBox
            }
            .padding(Theme.Spacing.md)
            }

            Divider()
            HStack {
                if plan.isEmpty && !isPlanning {
                    Text("No loose files to organize here.").font(.system(size: 11)).foregroundColor(.secondary)
                } else {
                    Text("\(plan.count) files → \(previewGroups.count) folders").font(.system(size: 11)).foregroundColor(.secondary)
                }
                if let error { Text(error).font(.caption).foregroundColor(.red) }
                Spacer()
                Button { run() } label: {
                    if isRunning { ProgressView().controlSize(.small) }
                    else { Label("Organize", systemImage: "square.grid.3x3").font(.system(size: 13, weight: .semibold)) }
                }
                .buttonStyle(.pill(Theme.moduleColor(.largeOldFiles)))
                .disabled(plan.isEmpty || isRunning)
            }
            .padding(Theme.Spacing.md)
        }
        .frame(width: 640)
        .frame(minHeight: 340, idealHeight: 500, maxHeight: 580)
        .background(Theme.appBackground)
        .onAppear { recompute() }
    }

    private var planningLabel: String {
        if let p = aiProgress, p.total > 0 { return "Naming folders on-device… \(p.done)/\(p.total)" }
        return scheme.usesAI ? "Reading files on-device…" : "Planning…"
    }

    @ViewBuilder private var previewBox: some View {
        Group {
            if isPlanning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(planningLabel)
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            } else if previewGroups.isEmpty {
                Text("No loose files to organize here.")
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            } else {
                VStack(spacing: 8) {
                    ForEach(previewGroups) { group in folderCard(group) }
                }
                .padding(8)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .glassCard(cornerRadius: 10)
    }

    /// One destination folder — tap to expand a thumbnail strip of exactly which files land in it.
    @ViewBuilder private func folderCard(_ group: PreviewGroup) -> some View {
        let isOpen = expanded.contains(group.path)
        VStack(spacing: 0) {
            Button {
                if isOpen { expanded.remove(group.path) } else { expanded.insert(group.path) }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                    Image(systemName: "folder.fill")
                        .font(.system(size: 13)).foregroundColor(Theme.moduleColor(.largeOldFiles))
                    ForEach(group.path.components(separatedBy: "/"), id: \.self) { part in
                        Text(part).font(.system(size: 12, weight: .semibold))
                        if part != group.path.components(separatedBy: "/").last {
                            Image(systemName: "chevron.right").font(.system(size: 7)).foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    Text("\(group.count)").font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.moduleColor(.largeOldFiles))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Theme.moduleColor(.largeOldFiles).opacity(0.15))
                        .clipShape(Capsule())
                    Text(group.bytes.formattedBytes).font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary).frame(width: 62, alignment: .trailing)
                }
                .padding(.horizontal, 10).padding(.vertical, 8).contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(group.items.prefix(40)) { item in
                            VStack(spacing: 3) {
                                ThumbnailView(url: item.file, size: 46)
                                Text(item.file.lastPathComponent)
                                    .font(.system(size: 8)).foregroundColor(.secondary)
                                    .lineLimit(1).truncationMode(.middle).frame(width: 52)
                            }
                        }
                        if group.count > 40 {
                            Text("+\(group.count - 40)").font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary).frame(width: 46, height: 46)
                                .background(Theme.panelBackground).clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                    }
                    .padding(.horizontal, 10).padding(.bottom, 8)
                }
            }
        }
        .background(Theme.panelBackground.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func recompute() {
        isPlanning = true
        expanded.removeAll()
        aiProgress = nil
        let folder = self.folder
        let scheme = self.scheme
        Task {
            let computed = await OrganizeService.planAsync(for: folder, scheme: scheme) { done, total in
                Task { @MainActor in self.aiProgress = (done, total) }
            }
            await MainActor.run { self.plan = computed; self.isPlanning = false; self.aiProgress = nil }
        }
    }

    private func run() {
        isRunning = true
        error = nil
        let items = self.plan
        let folder = self.folder
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<OrganizeService.OrganizeResult, Error> in
                do { return .success(try OrganizeService.organize(items, in: folder)) }
                catch { return .failure(error) }
            }.value
            await MainActor.run {
                isRunning = false
                switch result {
                case .success(let outcome):
                    UndoHistoryStore.shared.recordMoves(
                        title: "Organized \(outcome.movedCount) file\(outcome.movedCount == 1 ? "" : "s") in \(folder.lastPathComponent)",
                        movedPairs: outcome.movedPairs)
                    onCompleted(); dismiss()
                case .failure(let e): error = e.localizedDescription
                }
            }
        }
    }
}
