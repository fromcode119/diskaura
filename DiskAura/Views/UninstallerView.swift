import SwiftUI
import AppKit

enum UninstallerFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case unused = "Unused"
    var id: String { rawValue }
}

enum UninstallerSort: String, CaseIterable, Identifiable {
    case name = "Name"
    case size = "Size"
    case lastUsed = "Last used"
    var id: String { rawValue }
}

/// "Command Center" layout — no separate empty detail pane. Stat tiles up top, then a
/// full-width table of every app; click a row to expand its leftovers inline and uninstall.
struct UninstallerView: View {
    @StateObject private var viewModel = UninstallerViewModel()
    @ObservedObject var actionQueueVM: ActionQueueViewModel
    @State private var searchText = ""
    @State private var filter: UninstallerFilter = .all
    @State private var sort: UninstallerSort = .size
    @State private var selection: Set<String> = []
    @State private var expandedID: String?
    @State private var confirmBatch = false

    private var selectedApps: [InstalledApp] { viewModel.apps.filter { selection.contains($0.id) } }
    private var selectedBatchBytes: Int64 { selectedApps.reduce(0) { $0 + max($1.appSizeBytes, 0) } }
    private var unusedApps: [InstalledApp] { viewModel.apps.filter { $0.isUnused } }
    private var totalAppBytes: Int64 { viewModel.apps.reduce(0) { $0 + max($1.appSizeBytes, 0) } }
    private var reclaimableBytes: Int64 { unusedApps.reduce(0) { $0 + max($1.appSizeBytes, 0) } }

    private var filteredApps: [InstalledApp] {
        var list = viewModel.apps
        if !searchText.isEmpty { list = list.filter { $0.name.lowercased().contains(searchText.lowercased()) } }
        if filter == .unused { list = list.filter { $0.isUnused } }
        switch sort {
        case .name: list.sort { $0.name.lowercased() < $1.name.lowercased() }
        case .size: list.sort { $0.appSizeBytes > $1.appSizeBytes }
        case .lastUsed: list.sort { ($0.lastUsedDate ?? .distantPast) > ($1.lastUsedDate ?? .distantPast) }
        }
        return list
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            heroRow
            toolbar
            if let result = viewModel.lastResult { resultBanner(result) }
            if let batch = viewModel.batchResult { batchResultBanner(batch) }
            Divider()
            table
            if !selection.isEmpty { batchBar }
        }
        .background(Theme.appGradient)
        .confirmationDialog("Uninstall \(selection.count) apps?", isPresented: $confirmBatch, titleVisibility: .visible) {
            Button("Move \(selection.count) apps to Trash", role: .destructive) {
                viewModel.batchUninstall(selectedApps); selection.removeAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Each app and the leftovers DiskAura can reach move to the Trash (recoverable). System items needing admin rights are left for you.")
        }
        .onAppear { if viewModel.apps.isEmpty { viewModel.loadApps() } }
    }

    // MARK: header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("App Uninstaller").font(Theme.TypeScale.title)
                Text(viewModel.isLoading
                     ? "Reading /Applications…"
                     : "\(viewModel.apps.count) apps · \(totalAppBytes.formattedBytes) · \(unusedApps.count) unused")
                    .font(.system(size: 12)).foregroundColor(.secondary)
            }
            Spacer()
            if viewModel.isLoading { ProgressView().controlSize(.small) }
            if !unusedApps.isEmpty {
                Button {
                    selection = Set(unusedApps.map { $0.id }); confirmBatch = true
                } label: {
                    Label("Uninstall \(unusedApps.count) unused · \(reclaimableBytes.formattedBytes)", systemImage: "trash")
                        .font(.system(size: 12.5, weight: .semibold))
                }
                .buttonStyle(.pill(Theme.moduleColor(.uninstaller)))
            }
        }
        .padding(.horizontal, Theme.Spacing.lg).padding(.top, Theme.Spacing.md).padding(.bottom, 10)
    }

    private static let donutPalette: [Color] = [
        Theme.moduleColor(.scan), Theme.moduleColor(.duplicates), Theme.moduleColor(.largeOldFiles),
        Theme.moduleColor(.processes), Theme.moduleColor(.uninstaller), Color(red: 0.31, green: 0.84, blue: 0.90),
    ]

    /// App storage as donut slices — the biggest apps, then everything else folded into
    /// "Others". The circular breakdown the rest of the app uses, applied to /Applications.
    private var appSegments: [DonutSegment] {
        let sorted = viewModel.apps.filter { $0.appSizeBytes > 0 }.sorted { $0.appSizeBytes > $1.appSizeBytes }
        var segs = sorted.prefix(6).enumerated().map { i, a in
            DonutSegment(id: a.id, label: a.name, sizeBytes: a.appSizeBytes, color: Self.donutPalette[i % Self.donutPalette.count])
        }
        let others = sorted.dropFirst(6).reduce(Int64(0)) { $0 + $1.appSizeBytes }
        if others > 0 { segs.append(DonutSegment(id: "others", label: "\(max(sorted.count - 6, 0)) others", sizeBytes: others, color: Color(white: 0.28))) }
        return segs
    }

    private var heroRow: some View {
        StatHero(
            segments: appSegments,
            centerValue: totalAppBytes.formattedBytes,
            centerLabel: "in \(viewModel.apps.count) apps",
            tiles: [
                StatTileData(title: "Applications", value: "\(viewModel.apps.count)", glow: Theme.moduleColor(.scan), icon: "square.grid.2x2.fill"),
                StatTileData(title: "Total size", value: totalAppBytes.formattedBytes, glow: Theme.moduleColor(.duplicates), icon: "externaldrive.fill"),
                StatTileData(title: "Unused (6mo+)", value: "\(unusedApps.count)", glow: Theme.moduleColor(.uninstaller), icon: "clock.badge.exclamationmark.fill", valueColor: Theme.moduleColor(.uninstaller)),
                StatTileData(title: "Reclaimable", value: reclaimableBytes.formattedBytes, glow: Theme.moduleColor(.processes), icon: "arrow.down.circle.fill", valueColor: Theme.moduleColor(.processes)),
            ]
        )
        .padding(.horizontal, Theme.Spacing.lg).padding(.bottom, 14)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Picker("", selection: $filter) {
                Text("All \(viewModel.apps.count)").tag(UninstallerFilter.all)
                Text("Unused \(unusedApps.count)").tag(UninstallerFilter.unused)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 190)

            HStack(spacing: 5) {
                Text("Sort").font(.system(size: 10)).foregroundColor(.secondary)
                Picker("", selection: $sort) {
                    ForEach(UninstallerSort.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu).labelsHidden().controlSize(.small).frame(width: 96)
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundColor(.secondary)
                TextField("Filter apps…", text: $searchText).textFieldStyle(.plain).font(.system(size: 12)).frame(width: 160)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
        }
        .padding(.horizontal, Theme.Spacing.lg).padding(.bottom, 10)
    }

    // MARK: table

    private var table: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                columnHeader
                ForEach(filteredApps) { app in
                    AppTableRow(
                        app: app,
                        viewModel: viewModel,
                        isChecked: selection.contains(app.id),
                        isExpanded: expandedID == app.id,
                        maxBytes: max(totalAppBytes / 4, 1),
                        onToggleCheck: { toggleCheck(app.id) },
                        onToggleExpand: { toggleExpand(app) }
                    )
                    Divider().padding(.leading, 52)
                }
            }
            .padding(.horizontal, Theme.Spacing.lg).padding(.bottom, Theme.Spacing.md)
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: 20)
            Text("Application").frame(maxWidth: .infinity, alignment: .leading)
            Text("Last used").frame(width: 120, alignment: .leading)
            Text("Size").frame(width: 96, alignment: .trailing)
            Color.clear.frame(width: 84)
            Color.clear.frame(width: 12)
        }
        .font(.system(size: 10.5, weight: .bold)).foregroundStyle(.tertiary)
        .textCase(.uppercase).tracking(0.4)
        .padding(.vertical, 9)
    }

    private func resultBanner(_ result: AppUninstallerService.UninstallResult) -> some View {
        HStack(spacing: 10) {
            Image(systemName: result.failed.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(result.failed.isEmpty ? Theme.moduleColor(.processes) : Theme.moduleColor(.largeOldFiles))
            Text(result.failed.isEmpty
                 ? "Moved \(result.trashedCount) items to Trash · freed \(result.freedBytes.formattedBytes)"
                 : "Removed \(result.trashedCount) · \(result.failed.count) need admin (remove manually)")
                .font(.system(size: 12, weight: .medium))
            Spacer()
            if !result.restorePairs.isEmpty {
                Button("Undo") { viewModel.undoLastUninstall() }.buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg).padding(.vertical, 9)
        .background(Theme.moduleColor(.processes).opacity(0.08))
    }

    private func batchResultBanner(_ batch: UninstallerViewModel.BatchUninstallResult) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.moduleColor(.processes))
            Text("Uninstalled \(batch.appCount) app\(batch.appCount == 1 ? "" : "s") · moved \(batch.trashedItems) items · freed \(batch.freedBytes.formattedBytes)"
                 + (batch.adminItems > 0 ? " · \(batch.adminItems) need admin" : ""))
                .font(.system(size: 12, weight: .medium))
            Spacer()
            if !batch.restorePairs.isEmpty {
                Button("Undo") { viewModel.undoBatch() }.buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg).padding(.vertical, 9)
        .background(Theme.moduleColor(.processes).opacity(0.08))
    }

    private func toggleCheck(_ id: String) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }
    private func toggleExpand(_ app: InstalledApp) {
        if expandedID == app.id { expandedID = nil }
        else {
            expandedID = app.id
            viewModel.lastResult = nil
            if !viewModel.leftoversLoadedIDs.contains(app.id) { viewModel.scanLeftovers(for: app) }
        }
    }

    private var batchBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                if viewModel.isBatchUninstalling {
                    ProgressView().controlSize(.small)
                    Text("Uninstalling \(viewModel.batchProgress) of \(viewModel.batchTotal)…")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                } else {
                    Text("\(selection.count) selected · \(selectedBatchBytes.formattedBytes)")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button("Clear") { selection.removeAll() }
                        .buttonStyle(.plain).font(.system(size: 12)).foregroundColor(.secondary)
                    Button { confirmBatch = true } label: {
                        Label("Uninstall \(selection.count) apps", systemImage: "trash")
                            .font(.system(size: 12.5, weight: .semibold))
                    }
                    .buttonStyle(.pill(Theme.moduleColor(.uninstaller)))
                }
            }
            .padding(.horizontal, Theme.Spacing.lg).padding(.vertical, 11)
            .background(.ultraThinMaterial)
        }
    }
}

/// One row of the table + its inline expansion (leftovers, uninstall, result banner).
private struct AppTableRow: View {
    let app: InstalledApp
    @ObservedObject var viewModel: UninstallerViewModel
    let isChecked: Bool
    let isExpanded: Bool
    let maxBytes: Int64
    let onToggleCheck: () -> Void
    let onToggleExpand: () -> Void
    @State private var confirmUninstall = false

    private var leftoversLoaded: Bool { viewModel.leftoversLoadedIDs.contains(app.id) }
    private var sizeFraction: Double { maxBytes > 0 ? min(Double(max(app.appSizeBytes, 0)) / Double(maxBytes), 1) : 0 }
    private var adminItems: [LeftoverItem] { app.leftovers.filter { $0.requiresAdmin } }
    private var removableTotal: Int64 {
        max(app.appSizeBytes, 0) + app.leftovers.filter { !$0.requiresAdmin }.reduce(0) { $0 + $1.sizeBytes }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: onToggleCheck) {
                    Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15))
                        .foregroundColor(isChecked ? Theme.moduleColor(.uninstaller) : .secondary.opacity(0.45))
                }
                .buttonStyle(.plain).frame(width: 20)

                HStack(spacing: 11) {
                    FileIconView(url: URL(fileURLWithPath: app.bundlePath), size: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(app.name).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                            if app.isUnused { tag("UNUSED", Theme.moduleColor(.uninstaller)) }
                            if app.isSystemApp { tag("SYSTEM", Theme.moduleColor(.scan)) }
                        }
                        Text(app.bundleIdentifier ?? "—")
                            .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(app.lastUsedDescription)
                    .font(.system(size: 11.5)).foregroundColor(app.isUnused ? Theme.moduleColor(.uninstaller) : .secondary)
                    .frame(width: 120, alignment: .leading).lineLimit(1)

                VStack(alignment: .trailing, spacing: 4) {
                    if app.appSizeBytes < 0 {
                        ProgressView().controlSize(.mini)
                    } else {
                        Text(app.appSizeBytes.formattedBytes)
                            .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                    }
                    RoundedRectangle(cornerRadius: 2).fill(Color(white: 0.25)).frame(height: 4)
                        .overlay(alignment: .leading) {
                            GeometryReader { g in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(LinearGradient(colors: [Theme.moduleColor(.scan), Theme.moduleColor(.duplicates)], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: max(g.size.width * sizeFraction, 2))
                            }
                        }
                }
                .frame(width: 96)

                Group {
                    if app.isSystemApp {
                        Text("Protected").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.tertiary)
                    } else {
                        Button("Uninstall") { onToggleExpand(); confirmAfterLoad() }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .bold)).foregroundColor(Theme.moduleColor(.uninstaller))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.moduleColor(.uninstaller), lineWidth: 1))
                    }
                }
                .frame(width: 84)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0)).frame(width: 12)
            }
            .padding(.vertical, 9)
            .background(isExpanded ? Color.white.opacity(0.03) : .clear)
            .contentShape(Rectangle())
            .onTapGesture { onToggleExpand() }

            if isExpanded { expansion.transition(.opacity) }
        }
        .confirmationDialog("Uninstall \(app.name)?", isPresented: $confirmUninstall, titleVisibility: .visible) {
            Button("Move to Trash (\(removableTotal.formattedBytes))", role: .destructive) {
                viewModel.uninstall(app, leftovers: app.leftovers.filter { !$0.requiresAdmin })
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(adminItems.isEmpty
                 ? "\(app.name) and \(app.leftovers.count) related items will be moved to the Trash (recoverable)."
                 : "\(app.name) and \(app.leftovers.count - adminItems.count) items move to Trash. \(adminItems.count) system item(s) need admin rights — listed to remove manually.")
        }
    }

    private func confirmAfterLoad() {
        // Wait for the leftover scan (kicked off by expand) before showing the confirm sheet.
        if leftoversLoaded { confirmUninstall = true; return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            if leftoversLoaded { confirmUninstall = true }
        }
    }

    @ViewBuilder private var expansion: some View {
        VStack(alignment: .leading, spacing: 10) {
            if app.isSystemApp {
                Label("Part of macOS — its files are the system, so it's never scanned as leftovers and can't be removed.",
                      systemImage: "lock.shield.fill")
                    .font(.system(size: 11.5)).foregroundColor(.secondary)
            } else if !leftoversLoaded {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Finding everything \(app.name) left behind…").font(.system(size: 11.5)).foregroundColor(.secondary) }
            } else if app.leftovers.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.moduleColor(.processes))
                    Text("No leftovers — just the app itself (\(app.appSizeBytes.formattedBytes)).").font(.system(size: 11.5)).foregroundColor(.secondary)
                    Spacer()
                    uninstallButton
                }
            } else {
                HStack {
                    Text("Also removing \(app.leftovers.count) related items · \(app.totalLeftoverBytes.formattedBytes)")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    uninstallButton
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 7) {
                    ForEach(app.leftovers) { LeftoverRow(item: $0) }
                }
            }
        }
        .padding(14).background(Theme.panelBackground.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.leading, 32).padding(.bottom, 8)
    }

    private var uninstallButton: some View {
        Button {
            confirmUninstall = true
        } label: {
            if viewModel.isUninstalling { ProgressView().controlSize(.small) }
            else { Label("Uninstall \(app.name)", systemImage: "trash").font(.system(size: 11.5, weight: .semibold)) }
        }
        .buttonStyle(.pill(Theme.moduleColor(.uninstaller)))
        .disabled(viewModel.isUninstalling)
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 7.5, weight: .bold))
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(color.opacity(0.2)).foregroundColor(color)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

private struct LeftoverRow: View {
    let item: LeftoverItem
    var body: some View {
        HStack(spacing: 9) {
            FileIconView(url: item.url, size: 18)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(item.url.lastPathComponent).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                    if item.requiresAdmin {
                        Text("ADMIN").font(.system(size: 7, weight: .bold))
                            .padding(.horizontal, 3).padding(.vertical, 1)
                            .background(Theme.moduleColor(.largeOldFiles).opacity(0.2))
                            .foregroundColor(Theme.moduleColor(.largeOldFiles))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                Text(item.location.isEmpty ? item.url.deletingLastPathComponent().path : item.location)
                    .font(.system(size: 9.5, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 6)
            Text(item.sizeBytes.formattedBytes).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundColor(.secondary)
            Button { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } label: {
                Image(systemName: "folder").font(.system(size: 10))
            }
            .buttonStyle(.plain).foregroundStyle(.tertiary).help("Show in Finder")
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.03)))
    }
}

