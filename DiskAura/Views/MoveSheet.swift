import SwiftUI
import AppKit

/// Wraps the files to move so the sheet can be driven by `.sheet(item:)` — presenting via a
/// bool + separate array captured a stale (empty) array, so the sheet showed "Move 0 items".
struct MoveRequest: Identifiable {
    let id = UUID()
    let items: [FileNode]
}

/// Move selected files to a destination folder (external drive / archive / any folder), with
/// an option to auto-organize them by type or date, or leave them as-is. The user's spec:
/// "point to some external drive or archive or folder, with an option to organize them."
struct MoveSheet: View {
    let items: [FileNode]
    var onCompleted: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    @State private var destination: URL?
    @State private var organize: MoveOrganize = .byType
    @State private var isMoving = false
    @State private var error: String?
    @State private var plan: [MoveService.PlanGroup] = []
    @State private var isPlanning = false
    @State private var expanded: Set<String> = []
    @State private var aiProgress: (done: Int, total: Int)?

    private var totalBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }

    /// Display name for a plan folder — "" is the destination root.
    private func folderLabel(_ folder: String) -> String {
        folder.isEmpty ? "Destination folder" : folder
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Theme.moduleColor(.scan).opacity(0.18)).frame(width: 34, height: 34)
                    Image(systemName: "arrow.right.circle.fill").foregroundColor(Theme.moduleColor(.scan))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Move \(items.count) item\(items.count == 1 ? "" : "s")")
                        .font(.system(size: 15, weight: .semibold))
                    Text("\(totalBytes.formattedBytes) · files are moved, not copied")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
                Spacer()
                Button("Close") { dismiss() }.buttonStyle(.bordered)
            }
            .padding(Theme.Spacing.md)
            Divider()

            ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("DESTINATION").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary).tracking(0.7)
                    HStack(spacing: 10) {
                        Image(systemName: "externaldrive.fill").foregroundColor(.secondary)
                        Text(destination?.path ?? "Choose a folder, external drive, or archive…")
                            .font(.system(size: 12, design: destination == nil ? .default : .monospaced))
                            .foregroundColor(destination == nil ? .secondary : .primary)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Choose…") { chooseDestination() }
                    }
                    .padding(12)
                    .glassCard(cornerRadius: 10)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("ORGANIZE").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary).tracking(0.7)
                    ForEach(MoveOrganize.allCases) { option in
                        Button { organize = option; recompute() } label: {
                            HStack(spacing: 10) {
                                Image(systemName: organize == option ? "largecircle.fill.circle" : "circle")
                                    .foregroundColor(organize == option ? Theme.moduleColor(.scan) : .secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(option.rawValue).font(.system(size: 12.5, weight: .medium))
                                    Text(option.detail).font(.system(size: 10)).foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 4).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("PREVIEW").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary).tracking(0.7)
                    previewBox
                }

                if let error {
                    Text(error).font(.caption).foregroundColor(.red).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Theme.Spacing.md)
            }

            Divider()
            HStack {
                Text(destination == nil ? "Pick a destination to continue."
                     : "\(items.count) files → \(plan.count) folder\(plan.count == 1 ? "" : "s")")
                    .font(.system(size: 11)).foregroundColor(.secondary)
                Spacer()
                Button {
                    performMove()
                } label: {
                    if isMoving { ProgressView().controlSize(.small) }
                    else { Label("Move \(items.count) now", systemImage: "arrow.right.circle").font(.system(size: 13, weight: .semibold)) }
                }
                .buttonStyle(.pill(Theme.moduleColor(.scan)))
                .disabled(destination == nil || isMoving)
            }
            .padding(Theme.Spacing.md)
        }
        .frame(width: 620)
        .frame(minHeight: 340, idealHeight: 500, maxHeight: 580)
        .background(Theme.appBackground)
        .onAppear { recompute() }
    }

    private var planningLabel: String {
        if let p = aiProgress, p.total > 0 { return "Naming folders on-device… \(p.done)/\(p.total)" }
        return organize == .smart ? "Reading files on-device…" : "Planning…"
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
            } else {
                VStack(spacing: 8) {
                    ForEach(plan, id: \.folder) { group in folderCard(group) }
                }
                .padding(8)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
        .glassCard(cornerRadius: 10)
    }

    /// One destination folder — tap to expand a thumbnail strip of exactly which files land in it.
    @ViewBuilder private func folderCard(_ group: MoveService.PlanGroup) -> some View {
        let label = folderLabel(group.folder)
        let isOpen = expanded.contains(group.folder)
        let bytes = group.files.reduce(0) { $0 + $1.sizeBytes }
        VStack(spacing: 0) {
            Button {
                if isOpen { expanded.remove(group.folder) } else { expanded.insert(group.folder) }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                    Image(systemName: group.folder.isEmpty ? "tray.full.fill" : "folder.fill")
                        .font(.system(size: 13)).foregroundColor(Theme.moduleColor(.scan))
                    if group.folder.isEmpty {
                        Text(label).font(.system(size: 12, weight: .semibold))
                    } else {
                        let parts = group.folder.components(separatedBy: "/")
                        ForEach(Array(parts.enumerated()), id: \.offset) { idx, part in
                            Text(part).font(.system(size: 12, weight: .semibold))
                            if idx != parts.count - 1 {
                                Image(systemName: "chevron.right").font(.system(size: 7)).foregroundStyle(.tertiary)
                            }
                        }
                    }
                    Spacer()
                    Text("\(group.files.count)").font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.moduleColor(.scan))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Theme.moduleColor(.scan).opacity(0.15)).clipShape(Capsule())
                    Text(bytes.formattedBytes).font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary).frame(width: 62, alignment: .trailing)
                }
                .padding(.horizontal, 10).padding(.vertical, 8).contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(group.files.prefix(40), id: \.path) { file in
                            VStack(spacing: 3) {
                                ThumbnailView(url: file.url, size: 46)
                                Text(file.name)
                                    .font(.system(size: 8)).foregroundColor(.secondary)
                                    .lineLimit(1).truncationMode(.middle).frame(width: 52)
                            }
                        }
                        if group.files.count > 40 {
                            Text("+\(group.files.count - 40)").font(.system(size: 10, weight: .semibold))
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
        let nodes = self.items
        let organize = self.organize
        Task {
            let computed = await MoveService.planAsync(nodes, organize: organize) { done, total in
                Task { @MainActor in self.aiProgress = (done, total) }
            }
            await MainActor.run { self.plan = computed; self.isPlanning = false; self.aiProgress = nil }
        }
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Move Here"
        if panel.runModal() == .OK { destination = panel.url }
    }

    private func performMove() {
        guard let destination else { return }
        isMoving = true
        error = nil
        let plan = self.plan
        Task {
            // Move by the ALREADY-computed plan so files land exactly where the preview showed
            // and the (possibly expensive) on-device naming isn't paid for twice.
            let outcome = await Task.detached(priority: .userInitiated) { () -> Result<[(from: URL, to: URL)], Error> in
                do { return .success(try MoveService.move(plan: plan, to: destination)) }
                catch { return .failure(error) }
            }.value
            await MainActor.run {
                isMoving = false
                switch outcome {
                case .success(let pairs):
                    UndoHistoryStore.shared.recordMoves(
                        title: "Moved \(pairs.count) file\(pairs.count == 1 ? "" : "s") to \(destination.lastPathComponent)",
                        movedPairs: pairs)
                    onCompleted(); dismiss()
                case .failure(let e): self.error = e.localizedDescription
                }
            }
        }
    }
}
