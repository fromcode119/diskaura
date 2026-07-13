import SwiftUI
import AppKit

/// System Junk / Cleanup — CleanMyMac's flagship module. Scans safe-to-clean locations
/// (caches, logs, Trash, Xcode junk), shows them as category cards you can toggle, and
/// cleans the selected ones through the global action queue (to Trash, recoverable).
struct CleanupView: View {
    @StateObject private var viewModel = CleanupViewModel()
    @ObservedObject var actionQueueVM: ActionQueueViewModel
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let result = viewModel.lastCleanResult {
                cleanResultBanner(result)
            }

            if viewModel.isScanning {
                VStack(spacing: 14) {
                    ProgressView()
                    Text("Scanning caches, logs and junk…").font(.system(size: 12)).foregroundColor(.secondary)
                    Button("Cancel") { viewModel.cancel() }.buttonStyle(.bordered).controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !viewModel.hasScanned {
                emptyState
            } else if viewModel.categories.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 40)).foregroundColor(Theme.moduleColor(.processes))
                    Text("Nothing to clean — you're tidy.").foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: Theme.Spacing.md) {
                        heroRow
                        if !viewModel.snapshots.isEmpty {
                            snapshotCard
                        }
                        ForEach(viewModel.categories) { category in
                            categoryCard(category)
                        }
                    }
                    .padding(Theme.Spacing.lg)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if viewModel.hasScanned && !viewModel.categories.isEmpty {
                cleanBar
            }
        }
    }

    private static let donutPalette: [Color] = [
        Theme.moduleColor(.cleanup), Theme.moduleColor(.scan), Theme.moduleColor(.largeOldFiles),
        Theme.moduleColor(.duplicates), Theme.moduleColor(.uninstaller), Theme.moduleColor(.processes),
        Color(red: 0.31, green: 0.84, blue: 0.90),
    ]

    private var categorySegments: [DonutSegment] {
        viewModel.categories.enumerated().map { i, c in
            DonutSegment(id: c.id, label: c.title, sizeBytes: c.totalBytes, color: Self.donutPalette[i % Self.donutPalette.count])
        }
    }

    /// Junk breakdown donut + stat tiles — the same circular language as the rest of the app,
    /// so the amount and shape of what's cleanable reads at a glance before the category list.
    private var heroRow: some View {
        StatHero(
            segments: categorySegments,
            centerValue: viewModel.totalBytes.formattedBytes,
            centerLabel: "removable",
            tiles: [
                StatTileData(title: "Removable junk", value: viewModel.totalBytes.formattedBytes, glow: Theme.moduleColor(.cleanup), icon: "sparkles"),
                StatTileData(title: "Categories", value: "\(viewModel.categories.count)", glow: Theme.moduleColor(.scan), icon: "square.grid.2x2.fill"),
                StatTileData(title: "Selected to clean", value: viewModel.selectedBytes.formattedBytes, glow: Theme.moduleColor(.processes), icon: "checkmark.circle.fill", valueColor: Theme.moduleColor(.processes)),
                StatTileData(title: "Snapshots", value: "\(viewModel.snapshots.count)", glow: Theme.moduleColor(.duplicates), icon: "clock.arrow.2.circlepath"),
            ]
        )
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Cleanup").font(Theme.TypeScale.title)
                Text(viewModel.hasScanned
                     ? "\(viewModel.totalBytes.formattedBytes) of removable junk found"
                     : "Free up space from caches, logs, and system junk")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer()
            Button {
                viewModel.scan()
            } label: {
                Label(viewModel.hasScanned ? "Rescan" : "Scan", systemImage: "sparkles")
            }
            .buttonStyle(.gradientPill)
        }
        .padding(Theme.Spacing.md)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Theme.accentGradient).frame(width: 92, height: 92).opacity(0.9)
                Image(systemName: "sparkles").font(.system(size: 36, weight: .medium)).foregroundColor(.white)
            }
            VStack(spacing: 5) {
                Text("Clean up system junk").font(Theme.TypeScale.title)
                Text("Find cache files, logs, Trash, and developer junk that's safe to remove.")
                    .font(.system(size: 13)).foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button { viewModel.scan() } label: {
                Label("Scan for junk", systemImage: "sparkles")
            }
            .buttonStyle(.gradientPill)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func categoryCard(_ category: JunkCategory) -> some View {
        let isSelected = viewModel.selectedCategoryIDs.contains(category.id)
        let isOpen = expanded.contains(category.id)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Button { viewModel.toggle(category.id) } label: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundColor(isSelected ? Theme.moduleColor(.processes) : .secondary)
                }
                .buttonStyle(.plain)

                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Theme.accent.opacity(0.16)).frame(width: 32, height: 32)
                    Image(systemName: category.icon).font(.system(size: 14)).foregroundColor(Theme.accent)
                }

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(category.title).font(.system(size: 13, weight: .semibold))
                        if category.recommended {
                            Text("SAFE").font(.system(size: 7, weight: .bold))
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Theme.moduleColor(.processes).opacity(0.2))
                                .foregroundColor(Theme.moduleColor(.processes))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    Text(category.explanation).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
                }

                Spacer()
                Text(category.totalBytes.formattedBytes)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                HStack(spacing: 3) {
                    Text(isOpen ? "Hide" : "\(category.items.count) items")
                        .font(.system(size: 10, weight: .medium)).foregroundColor(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .frame(height: 16)
            }
            .padding(16)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isOpen { expanded.remove(category.id) } else { expanded.insert(category.id) }
                }
            }

            if isOpen {
                Divider().padding(.leading, 60)
                VStack(spacing: 0) {
                    ForEach(category.items.prefix(60)) { item in
                        let excluded = viewModel.isItemExcluded(item.url)
                        HStack(spacing: 10) {
                            Button { viewModel.toggleItem(item.url) } label: {
                                Image(systemName: excluded ? "circle" : "checkmark.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundColor(excluded ? .secondary.opacity(0.5) : Theme.moduleColor(.processes))
                            }
                            .buttonStyle(.plain)
                            .help(excluded ? "Keep this file" : "Include this file in the clean")
                            FileIconView(url: item.url, size: 18)
                            Text(item.name)
                                .font(.system(size: 11))
                                .foregroundColor(excluded ? .secondary : .primary)
                                .strikethrough(excluded)
                                .lineLimit(1)
                            Spacer()
                            Button { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } label: {
                                Image(systemName: "folder").font(.system(size: 10))
                            }
                            .buttonStyle(.plain).foregroundColor(.secondary).help("Show in Finder")
                            Text(item.sizeBytes.formattedBytes)
                                .font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                                .frame(width: 64, alignment: .trailing)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 6)
                    }
                    if category.items.count > 60 {
                        Text("+ \(category.items.count - 60) more")
                            .font(.system(size: 10)).foregroundColor(.secondary)
                            .padding(.bottom, 8)
                    }
                }
            }
        }
        .glassCard()
    }

    /// Time Machine local snapshots — explains and clears the "purgeable" space that makes
    /// deleting files seem to free nothing. Distinct from the trash-to-recycle categories.
    private var snapshotCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Theme.moduleColor(.scan).opacity(0.16)).frame(width: 32, height: 32)
                    Image(systemName: "clock.arrow.2.circlepath").font(.system(size: 14)).foregroundColor(Theme.moduleColor(.scan))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Time Machine Local Snapshots").font(.system(size: 13, weight: .semibold))
                    Text("\(viewModel.snapshots.count) snapshot\(viewModel.snapshots.count == 1 ? "" : "s") are holding onto “purgeable” space — why deleting files may not free room.")
                        .font(.system(size: 10)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    viewModel.deleteSnapshots()
                } label: {
                    if viewModel.isDeletingSnapshots { ProgressView().controlSize(.small) }
                    else { Text("Thin snapshots").font(.system(size: 11, weight: .semibold)) }
                }
                .buttonStyle(.pill(Theme.moduleColor(.scan)))
                .disabled(viewModel.isDeletingSnapshots)
            }
            if let msg = viewModel.snapshotMessage {
                Text(msg).font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .glassCard()
    }

    private func cleanResultBanner(_ result: CleanupViewModel.CleanResult) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Theme.moduleColor(.processes))
            Text(bannerText(result))
                .font(.system(size: 12, weight: .medium))
            Spacer()
            if !result.restorePairs.isEmpty {
                Button("Undo") { viewModel.undoLastClean() }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(.horizontal, Theme.Spacing.md).padding(.vertical, 10)
        .background(Theme.moduleColor(.processes).opacity(0.08))
        .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.border), alignment: .bottom)
    }

    private func bannerText(_ result: CleanupViewModel.CleanResult) -> String {
        var parts: [String] = []
        if result.movedCount > 0 { parts.append("Cleaned \(result.movedCount) items · freed \(result.freedBytes.formattedBytes)") }
        if result.emptiedTrash { parts.append(result.movedCount > 0 ? "and emptied the Trash" : "Emptied the Trash") }
        return parts.isEmpty ? "Nothing to clean" : parts.joined(separator: " ")
    }

    private var cleanBar: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(Theme.moduleColor(.processes).opacity(0.18)).frame(width: 34, height: 34)
                Image(systemName: "sparkles").font(.system(size: 14)).foregroundColor(Theme.moduleColor(.processes))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("\(viewModel.selectedBytes.formattedBytes) selected to clean")
                    .font(.system(size: 13, weight: .semibold))
                Text("Moved to Trash — recoverable until you empty it")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer()
            Button {
                viewModel.clean()
            } label: {
                if viewModel.isCleaning {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Clean up", systemImage: "sparkles").font(.system(size: 12.5, weight: .semibold))
                }
            }
            .buttonStyle(.pill(Theme.moduleColor(.processes)))
            .disabled(viewModel.selectedBytes == 0 || viewModel.isCleaning)
        }
        .padding(.horizontal, Theme.Spacing.md).padding(.vertical, 11)
        .background(.ultraThinMaterial)
        .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.border), alignment: .top)
    }
}
