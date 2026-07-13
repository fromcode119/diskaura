import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable {
    case scanner = "Scanner"
    case cleanup = "Cleanup"
    case system = "System"

    var id: String { rawValue }
}

enum SidebarTab: String, CaseIterable, Identifiable {
    case scan = "Disk Scan"
    case largeOldFiles = "Large & Old Files"
    case systemData = "System Data"
    case cleanup = "Cleanup"
    case smartRules = "Smart Rules"
    case assistant = "Assistant"
    case duplicates = "Duplicates"
    case uninstaller = "App Uninstaller"
    case processes = "Processes"
    case loginItems = "Login Items"
    case settings = "Settings"

    var id: String { rawValue }

    /// Short label for the sidebar (the full rawValue is used for the content header).
    var menuLabel: String {
        switch self {
        case .scan: return "Disk scan"
        case .largeOldFiles: return "Large & old"
        case .systemData: return "System data"
        case .cleanup: return "Cleanup"
        case .smartRules: return "Smart rules"
        case .assistant: return "Assistant"
        case .duplicates: return "Duplicates"
        case .uninstaller: return "Uninstaller"
        case .processes: return "Processes"
        case .loginItems: return "Login items"
        case .settings: return "Settings"
        }
    }

    var section: SidebarSection {
        switch self {
        case .scan, .largeOldFiles: return .scanner
        case .systemData, .cleanup, .smartRules, .assistant, .duplicates, .uninstaller: return .cleanup
        case .processes, .loginItems, .settings: return .system
        }
    }

    var icon: String {
        switch self {
        case .scan: return "chart.pie.fill"
        case .largeOldFiles: return "doc.text.magnifyingglass"
        case .systemData: return "internaldrive.fill"
        case .cleanup: return "sparkles"
        case .smartRules: return "wand.and.stars"
        case .assistant: return "sparkle"
        case .duplicates: return "doc.on.doc.fill"
        case .uninstaller: return "trash.square.fill"
        case .processes: return "cpu.fill"
        case .loginItems: return "power.circle.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

struct ContentView: View {
    @ObservedObject var router: AppRouter
    private var selectedTab: SidebarTab { router.selectedTab }
    @StateObject private var scanVM = ScanViewModel()
    @StateObject private var processVM = ProcessViewModel()
    @StateObject private var actionQueueVM = ActionQueueViewModel()
    @StateObject private var scheduledScan = ScheduledScanService()
    @State private var showActionQueue = false
    @State private var showRecovery = false
    @ObservedObject private var undoStore = UndoHistoryStore.shared

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Group {
                switch selectedTab {
                case .scan:
                    ScanView(scanVM: scanVM, actionQueueVM: actionQueueVM)
                case .largeOldFiles:
                    LargeOldFilesView(root: scanVM.result?.root, actionQueueVM: actionQueueVM)
                case .systemData:
                    SystemDataView(router: router)
                case .cleanup:
                    CleanupView(actionQueueVM: actionQueueVM)
                case .smartRules:
                    RulesView()
                case .assistant:
                    AssistantView(scanVM: scanVM)
                case .duplicates:
                    DuplicateFinderView(actionQueueVM: actionQueueVM, sharedRootURL: scanVM.result?.root.url)
                case .uninstaller:
                    UninstallerView(actionQueueVM: actionQueueVM)
                case .processes:
                    ProcessTableView(viewModel: processVM)
                        .onAppear { processVM.start() }
                        .onDisappear { processVM.stop() }
                case .loginItems:
                    LoginItemsView()
                case .settings:
                    SettingsView(classification: scanVM.classification, actionQueueVM: actionQueueVM, scheduledScan: scheduledScan, exclusions: scanVM.exclusions)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.appGradient)
            // The delete queue lives here, at the app level — not inside ScanView — so
            // anything you queue from Duplicates / Large & Old / the breakdown can always be
            // reviewed and actually deleted, from whatever tab you're on. Previously the bar
            // only existed on the Scan tab, so queued deletions were unreachable elsewhere.
            .safeAreaInset(edge: .bottom) {
                if !actionQueueVM.pendingActions.isEmpty {
                    GlobalQueueBar(actionQueueVM: actionQueueVM) { showActionQueue = true }
                }
            }
            .sheet(isPresented: $showActionQueue) {
                ActionQueueView(viewModel: actionQueueVM) {
                    // After a real delete, re-scan the current folder so the breakdown,
                    // Large & Old, and dashboard drop the files that are now gone.
                    if let url = scanVM.result?.root.url {
                        scanVM.scan(url: url)
                    }
                }
            }
            .sheet(isPresented: $showRecovery) { RecoveryView() }
        }
        .onAppear { scheduledScan.attach(to: scanVM) }
    }

    /// Wide labeled sidebar (CleanMyMac's actual layout) — colored icon + text label per
    /// module, grouped under section headers. Replaces the cramped 50px icon-only rail that
    /// made the app feel like a stripped-down utility.
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image("AppLogo")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 26, height: 26)
                Text("DiskAura").font(.system(size: 15, weight: .semibold))
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 18)

            ForEach(SidebarSection.allCases) { section in
                Text(section.rawValue.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.7)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 5)

                ForEach(SidebarTab.allCases.filter { $0.section == section }) { tab in
                    sidebarRow(tab)
                }
            }

            Spacer()

            Button { showRecovery = true } label: {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.uturn.backward").font(.system(size: 11, weight: .semibold))
                    Text("Recovery").font(.system(size: 12, weight: .medium))
                    if !undoStore.entries.isEmpty {
                        Text("\(undoStore.entries.count)").font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Theme.moduleColor(.processes).opacity(0.25)).clipShape(Capsule())
                    }
                    Spacer()
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)

            HStack(spacing: 6) {
                Circle().fill(scanVM.result != nil ? Theme.moduleColor(.processes) : Color.secondary)
                    .frame(width: 6, height: 6)
                Text(scanVM.result != nil ? "Scan ready" : "No scan yet")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .frame(width: 194)
        .background(Theme.sidebarGradient)
    }

    private func sidebarRow(_ tab: SidebarTab) -> some View {
        let isSelected = selectedTab == tab
        let color = Theme.moduleColor(tab)
        return Button {
            router.selectedTab = tab
        } label: {
            HStack(spacing: 11) {
                // Glossy module tile — a soft top-highlight gradient + a colored glow when
                // selected gives the vivid, tactile feel of CleanMyMac's module icons.
                Image(systemName: tab.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(LinearGradient(colors: [color.opacity(isSelected ? 1 : 0.9),
                                                          color.opacity(isSelected ? 0.78 : 0.66)],
                                                 startPoint: .top, endPoint: .bottom))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                    )
                    .shadow(color: isSelected ? color.opacity(0.5) : .clear, radius: 6, y: 1)
                Text(tab.menuLabel)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(isSelected ? color.opacity(0.16) : .clear)
                    if isSelected {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color)
                            .frame(width: 3)
                            .padding(.vertical, 6)
                    }
                }
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 1.5)
    }
}

/// The always-available delete queue bar — pinned to the bottom of the content area on
/// EVERY tab. Whatever you queue (a duplicate, a big old file, a breakdown row) collects
/// here and can be reviewed + actually deleted from anywhere. Nothing is deleted until you
/// open the review sheet and confirm.
struct GlobalQueueBar: View {
    @ObservedObject var actionQueueVM: ActionQueueViewModel
    let onReview: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Theme.moduleColor(.uninstaller).opacity(0.18))
                    .frame(width: 34, height: 34)
                Image(systemName: "trash.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.moduleColor(.uninstaller))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("\(actionQueueVM.pendingActions.count) item\(actionQueueVM.pendingActions.count == 1 ? "" : "s") queued to delete")
                    .font(.system(size: 13, weight: .semibold))
                Text("Frees \(actionQueueVM.totalBytes.formattedBytes) · nothing deleted until you confirm")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                actionQueueVM.clear()
            } label: {
                Text("Clear").font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            Button {
                onReview()
            } label: {
                Label("Review & delete", systemImage: "trash")
                    .font(.system(size: 12.5, weight: .semibold))
            }
            .buttonStyle(.pill(Theme.moduleColor(.uninstaller)))
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 11)
        .background(.ultraThinMaterial)
        .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.border), alignment: .top)
    }
}

struct ScanView: View {
    @ObservedObject var scanVM: ScanViewModel
    @ObservedObject var actionQueueVM: ActionQueueViewModel
    /// Shared between the ring and the list below — clicking a segment only zoomed the ring
    /// while the file list kept showing the root's children forever.
    @State private var zoomStack: [FileNode] = []
    @State private var moveTarget: MoveRequest?
    @State private var organizeTarget: OrganizeRequest?
    @State private var selection: Set<String> = []

    private func selectedNodes(in result: ScanResult) -> [FileNode] {
        result.root.nodes(matching: selection)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            if let result = scanVM.result {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        // CleanMyMac-style donut + legend + sub-pills + largest items — driven
                        // by whatever node is currently focused (root, or a folder you've
                        // zoomed into via the sunburst below), so the numbers up top actually
                        // change when you deep-dive instead of staying pinned to the root.
                        ScanDashboard(root: zoomStack.last ?? result.root, volume: result.volume,
                                      actionQueueVM: actionQueueVM,
                                      onMove: { moveTarget = MoveRequest(items: [$0]) })

                        ScanHistoryView(scanVM: scanVM)

                        // …plus the interactive "fancy circle" (sunburst) — kept because it's
                        // clickable and drives both the dashboard above and the breakdown
                        // below. Mixed with the donut, not replaced.
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Explore").font(.system(size: 15, weight: .semibold))
                            SunburstView(root: result.root, zoomStack: $zoomStack)
                                .frame(height: 430)
                                .frame(maxWidth: .infinity)
                        }
                        .padding(18)
                        .glassCard()
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))

                        FolderBreakdownView(node: zoomStack.last ?? result.root,
                                            actionQueueVM: actionQueueVM,
                                            onMove: { moveTarget = MoveRequest(items: [$0]) },
                                            selection: $selection)
                    }
                    .padding(Theme.Spacing.lg)
                }
                // Key on the ROOT NODE's identity, not its path — a re-scan after a delete builds
                // a fresh tree at the SAME path, so keying on the path never fired and any folder
                // you'd zoomed into kept showing the OLD (pre-delete) contents.
                .onChange(of: ObjectIdentifier(result.root)) {
                    zoomStack.removeAll()
                    selection.removeAll()
                }
                .safeAreaInset(edge: .bottom) {
                    if !selection.isEmpty { batchBar(result: result) }
                }
            } else if scanVM.isScanning {
                scanningView
            } else {
                emptyState
            }
        }
        .sheet(item: $moveTarget) { req in
            MoveSheet(items: req.items) {
                selection.removeAll()
                if let url = scanVM.result?.root.url { scanVM.scan(url: url) }
            }
        }
        .sheet(item: $organizeTarget) { req in
            OrganizeSheet(folder: req.folder) {
                if let url = scanVM.result?.root.url { scanVM.scan(url: url) }
            }
        }
        // Re-scan after the delete queue runs so freshly-deleted files stop showing. Also drop
        // any zoom so the breakdown returns to the fresh root instead of a stale sub-tree.
        .onChange(of: actionQueueVM.executedGeneration) {
            selection.removeAll()
            zoomStack.removeAll()
            if let url = scanVM.result?.root.url { scanVM.scan(url: url) }
        }
    }

    private func batchBar(result: ScanResult) -> some View {
        let nodes = selectedNodes(in: result)
        let bytes = nodes.reduce(Int64(0)) { $0 + $1.sizeBytes }
        return HStack(spacing: 12) {
            Text("\(nodes.count) selected · \(bytes.formattedBytes)")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Button("Clear") { selection.removeAll() }
                .buttonStyle(.plain).font(.system(size: 12)).foregroundColor(.secondary)
            Button {
                moveTarget = MoveRequest(items: nodes)
            } label: {
                Label("Move \(nodes.count)…", systemImage: "arrow.right.circle")
                    .font(.system(size: 12.5, weight: .semibold))
            }
            .buttonStyle(.pill(Theme.moduleColor(.scan)))
            Button {
                for node in nodes { actionQueueVM.queue(node, kind: .trash) }
                selection.removeAll()
            } label: {
                Label("Delete \(nodes.count)…", systemImage: "trash")
                    .font(.system(size: 12.5, weight: .semibold))
            }
            .buttonStyle(.pill(Theme.moduleColor(.uninstaller)))
        }
        .padding(.horizontal, Theme.Spacing.md).padding(.vertical, 11)
        .background(.ultraThinMaterial)
        .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.border), alignment: .top)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Disk Scan").font(Theme.TypeScale.title)
                if let result = scanVM.result {
                    Text(result.root.path)
                        .font(Theme.TypeScale.mono)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            if scanVM.isScanning {
                ProgressView().controlSize(.small)
                Text("\(scanVM.nodesScanned) items scanned…")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button("Cancel", role: .cancel) { scanVM.cancelScan() }
                    .buttonStyle(.bordered)
            } else {
                if !scanVM.recentLocations.paths.isEmpty {
                    Menu {
                        ForEach(scanVM.recentLocations.paths, id: \.self) { path in
                            Button(displayName(for: path)) {
                                scanVM.scan(url: URL(fileURLWithPath: path))
                            }
                        }
                    } label: {
                        Label("Recent", systemImage: "clock.arrow.circlepath")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                if let result = scanVM.result {
                    Button {
                        scanVM.scan(url: result.root.url)
                    } label: {
                        Label("Rescan", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .help("Re-scan this folder — reflects files you've added, deleted, or restored")
                    Button {
                        organizeTarget = OrganizeRequest(folder: result.root.url)
                    } label: {
                        Label("Organize…", systemImage: "square.grid.3x3")
                    }
                    .buttonStyle(.bordered)
                    .help("Tidy this folder's loose files into subfolders")
                    Button {
                        exportReport()
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                }
                Button {
                    chooseFolder()
                } label: {
                    Label("Choose Folder…", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                Button {
                    scanVM.scan(url: FileManager.default.homeDirectoryForCurrentUser)
                } label: {
                    Label("Scan Home Folder", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.gradientPill)
            }
        }
        .padding(Theme.Spacing.md)
    }

    private func displayName(for path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "Home" }
        if path.hasPrefix(home + "/") { return "~/" + path.dropFirst(home.count + 1) }
        return (path as NSString).lastPathComponent
    }

    private func exportReport() {
        guard let result = scanVM.result else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "DiskAura-Report-\(result.root.name).md"
        panel.allowedContentTypes = [.text]
        if panel.runModal() == .OK, let url = panel.url {
            let markdown = ScanReportService.generateMarkdown(from: result)
            try? markdown.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private var scanningView: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.12))
                    .frame(width: 72, height: 72)
                ProgressView()
                    .controlSize(.large)
            }
            Text("\(scanVM.nodesScanned) items scanned")
                .font(.system(size: 13, weight: .semibold))
            Text(scanVM.progressPath)
                .font(Theme.TypeScale.mono)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 520)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Theme.accentGradient)
                    .frame(width: 92, height: 92)
                    .opacity(0.9)
                Image(systemName: "internaldrive")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundColor(.white)
            }
            VStack(spacing: 5) {
                Text("Scan a folder to begin")
                    .font(Theme.TypeScale.title)
                Text("See what's taking space, find duplicates, and clean up.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 10) {
                Button {
                    scanVM.scan(url: FileManager.default.homeDirectoryForCurrentUser)
                } label: {
                    Label("Scan home folder", systemImage: "house")
                }
                .buttonStyle(.gradientPill)
                .controlSize(.large)
                Button {
                    chooseFolder()
                } label: {
                    Label("Choose folder…", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            if !scanVM.recentLocations.paths.isEmpty {
                VStack(spacing: 8) {
                    Text("RECENT")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .tracking(0.8)
                    HStack(spacing: 8) {
                        ForEach(scanVM.recentLocations.paths.prefix(4), id: \.self) { path in
                            Button {
                                scanVM.scan(url: URL(fileURLWithPath: path))
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 10))
                                    Text(displayName(for: path)).font(.system(size: 11, weight: .medium))
                                }
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .glassCard(cornerRadius: 20)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            scanVM.scan(url: url)
        }
    }
}
