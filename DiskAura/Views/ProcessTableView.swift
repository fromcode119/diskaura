import SwiftUI

/// Default view: Applications vs System processes, CleanMyMac's actual split (by owning
/// UID) — not an arbitrary "top 6" list with no structure. A "Show all processes" toggle
/// reveals the full sortable table for the rare case someone needs it.
struct ProcessTableView: View {
    @ObservedObject var viewModel: ProcessViewModel
    @State private var temp = SystemStatsService.temperature()
    private let tempTicker = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if viewModel.showAllProcesses {
                allProcessesTable
            } else {
                categorizedView
            }
        }
        .onReceive(tempTicker) { _ in temp = SystemStatsService.temperature() }
        .alert("Quit Failed", isPresented: Binding(
            get: { viewModel.quitError != nil },
            set: { if !$0 { viewModel.quitError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.quitError ?? "")
        }
    }

    private var tempGlow: Color {
        guard temp.available else { return Theme.moduleColor(.largeOldFiles) }
        switch temp.level {
        case .normal: return Theme.moduleColor(.processes)
        case .fair: return Theme.moduleColor(.largeOldFiles)
        case .serious, .critical: return Theme.moduleColor(.uninstaller)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Processes").font(Theme.TypeScale.title)
                    Text("\(viewModel.processCount) running  ·  \(String(format: "%.0f", viewModel.totalCPUPercent))% CPU"
                         + (viewModel.isPaused ? "  ·  paused" : ""))
                        .font(.system(size: 12)).foregroundColor(.secondary)
                }
                Spacer()
                Button { viewModel.captureSnapshot() } label: {
                    Label("Snapshot", systemImage: "camera.viewfinder").font(.system(size: 11))
                }.buttonStyle(.bordered).controlSize(.small)
                    .help("Freeze the current figures to compare against later")
                Button { viewModel.togglePause() } label: {
                    Label(viewModel.isPaused ? "Resume" : "Pause", systemImage: viewModel.isPaused ? "play.fill" : "pause.fill").font(.system(size: 11))
                }.buttonStyle(.bordered).controlSize(.small)
                    .tint(viewModel.isPaused ? Theme.moduleColor(.largeOldFiles) : nil)
                    .help("Freeze the list so it stops changing while you read it")
                Toggle("Show all", isOn: Binding(get: { viewModel.showAllProcesses }, set: { viewModel.setShowAllProcesses($0) }))
                    .toggleStyle(.switch).controlSize(.small)
            }

            if let snap = viewModel.snapshot { snapshotBar(snap) }

            // Memory donut + stat tiles hero — the same circular language as every other tab.
            // Collapsed to a one-line summary in "Show all" so the table gets full height.
            if !viewModel.showAllProcesses {
                heroRow
            } else {
                HStack(spacing: 14) {
                    ForEach(memorySegments) { seg in
                        HStack(spacing: 5) {
                            Circle().fill(seg.color).frame(width: 7, height: 7)
                            Text(seg.label).font(.system(size: 10)).foregroundColor(.secondary)
                            Text(seg.sizeBytes.formattedMemoryBytes).font(.system(size: 10, weight: .semibold, design: .rounded))
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(Theme.Spacing.md)
    }

    private var heroRow: some View {
        StatHero(
            segments: memorySegments,
            centerValue: Int64(viewModel.totalMemoryBytes).formattedMemoryBytes,
            centerLabel: "of \(Int64(viewModel.totalMemoryCapacity).formattedMemoryBytes)",
            tiles: [
                StatTileData(title: "Processes", value: "\(viewModel.processCount)", glow: Theme.moduleColor(.scan), icon: "square.grid.3x3.fill"),
                StatTileData(title: "CPU load", value: String(format: "%.0f%%", viewModel.totalCPUPercent), glow: Theme.moduleColor(.processes), icon: "cpu.fill", sparkline: viewModel.cpuHistory),
                StatTileData(title: "App memory", value: Int64(viewModel.appMemoryBytes).formattedMemoryBytes, glow: Theme.moduleColor(.duplicates), icon: "memorychip.fill"),
                StatTileData(title: "Temperature",
                             value: temp.available ? "\(Int(temp.peakCelsius.rounded()))°C" : Int64(viewModel.memoryFreeBytes).formattedMemoryBytes,
                             glow: tempGlow, icon: "thermometer.medium",
                             valueColor: temp.available && temp.level != .normal ? tempGlow : nil),
            ]
        )
    }

    private var memorySegments: [DonutSegment] {
        [
            DonutSegment(id: "active", label: "Active", sizeBytes: Int64(viewModel.memoryActiveBytes), color: Theme.moduleColor(.processes)),
            DonutSegment(id: "wired", label: "Wired", sizeBytes: Int64(viewModel.memoryWiredBytes), color: Theme.moduleColor(.duplicates)),
            DonutSegment(id: "compressed", label: "Compressed", sizeBytes: Int64(viewModel.memoryCompressedBytes), color: Theme.moduleColor(.largeOldFiles)),
            DonutSegment(id: "free", label: "Free", sizeBytes: Int64(viewModel.memoryFreeBytes), color: Color.white.opacity(0.25)),
        ]
    }

    /// Shows how CPU / memory / process count moved since the user captured a snapshot —
    /// the "compare over time" they asked for.
    private func snapshotBar(_ snap: ProcessViewModel.CapturedSnapshot) -> some View {
        let cpuDelta = viewModel.totalCPUPercent - snap.totalCPUPercent
        let memDelta = Int64(viewModel.totalMemoryBytes) - Int64(snap.usedMemoryBytes)
        let procDelta = viewModel.processCount - snap.processCount
        return HStack(spacing: 14) {
            Image(systemName: "camera.viewfinder").foregroundColor(Theme.moduleColor(.scan))
            Text("Snapshot \(snap.takenAt.formatted(date: .omitted, time: .standard))")
                .font(.system(size: 11, weight: .medium))
            Divider().frame(height: 16)
            deltaLabel("CPU", String(format: "%+.0f%%", cpuDelta), cpuDelta <= 0)
            deltaLabel("Memory", (memDelta >= 0 ? "+" : "−") + abs(memDelta).formattedMemoryBytes, memDelta <= 0)
            deltaLabel("Processes", String(format: "%+d", procDelta), procDelta <= 0)
            Spacer()
            Button { viewModel.clearSnapshot() } label: {
                Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .glassCard(cornerRadius: 10)
    }

    private func deltaLabel(_ label: String, _ value: String, _ good: Bool) -> some View {
        HStack(spacing: 5) {
            Text(label).font(.system(size: 10)).foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(good ? Theme.moduleColor(.processes) : Theme.moduleColor(.uninstaller))
        }
    }

    private var categorizedView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                categorySection(
                    title: "Applications",
                    icon: "app.badge",
                    accent: Theme.moduleColor(.processes),
                    count: viewModel.appCount,
                    memoryBytes: viewModel.appMemoryBytes,
                    processes: viewModel.topApps,
                    canQuit: true
                )
                categorySection(
                    title: "Background",
                    icon: "gearshape",
                    accent: .secondary,
                    count: viewModel.backgroundCount,
                    memoryBytes: viewModel.backgroundMemoryBytes,
                    processes: viewModel.topBackground,
                    canQuit: true
                )
                categorySection(
                    title: "System",
                    icon: "gearshape.2",
                    accent: .secondary,
                    count: viewModel.systemCount,
                    memoryBytes: viewModel.systemMemoryBytes,
                    processes: viewModel.topSystem,
                    canQuit: false,
                    emptyMessage: "macOS blocks unprivileged apps from reading other users' process details — confirmed via a direct syscall test (errno 1, EPERM), not a bug here. Activity Monitor gets a special Apple entitlement regular apps don't have."
                )
            }
            .padding(Theme.Spacing.lg)
        }
    }

    private func categorySection(
        title: String,
        icon: String,
        accent: Color,
        count: Int,
        memoryBytes: UInt64,
        processes: [ProcessSnapshot],
        canQuit: Bool,
        emptyMessage: String = "None using notable CPU right now"
    ) -> some View {
        let maxMemory = processes.map(\.memoryBytes).max() ?? 1

        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(accent)
                Spacer()
                Text("\(count) processes  ·  \(Int64(memoryBytes).formattedMemoryBytes)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(processes) { proc in
                    ProcessRow(
                        process: proc,
                        canQuit: canQuit,
                        memoryFraction: maxMemory > 0 ? Double(proc.memoryBytes) / Double(maxMemory) : 0,
                        onQuit: { viewModel.quit(proc) }
                    )
                    if proc.id != processes.last?.id {
                        Divider().padding(.leading, 46)
                    }
                }
                if processes.isEmpty {
                    Text(emptyMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                }
            }
        }
        .glassCard()
    }

    // Full list, but styled to match the rest of the app (dark rows, icons, colored CPU/mem,
    // sortable header) instead of the stock SwiftUI `Table` that read as an alien system
    // control. Column headers are clickable to sort.
    private var allProcessesTable: some View {
        let rows = viewModel.filteredAllProcesses
        let maxMem = rows.map(\.memoryBytes).max() ?? 1
        return VStack(spacing: 0) {
            HStack {
                Picker("", selection: $viewModel.filter) {
                    ForEach(ProcessFilter.allCases) { filter in Text(filter.rawValue).tag(filter) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 240)
                Spacer()
                Text("\(rows.count) processes").font(.system(size: 11)).foregroundColor(.secondary)
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundColor(.secondary)
                    TextField("Filter by name…", text: $viewModel.searchText).textFieldStyle(.plain).frame(width: 160)
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.05)))
            }
            .padding(.horizontal, Theme.Spacing.lg).padding(.vertical, 10)

            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { i, proc in
                            AllProcessRow(process: proc, memFraction: maxMem > 0 ? Double(proc.memoryBytes) / Double(maxMem) : 0,
                                          zebra: i % 2 == 1, onQuit: { viewModel.quit(proc) })
                        }
                    } header: {
                        HStack(spacing: 12) {
                            sortHeader("Process", \.name, width: nil, align: .leading)
                            sortHeader("CPU", \.cpuPercent, width: 64, align: .trailing)
                            sortHeader("Memory", \.memoryBytes, width: 150, align: .trailing)
                            Color.clear.frame(width: 52)
                        }
                        .padding(.vertical, 6)
                        .background(Theme.appBackground)
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg).padding(.bottom, Theme.Spacing.md)
            }
        }
    }

    private func sortHeader(_ title: String, _ key: KeyPath<ProcessSnapshot, some Comparable>, width: CGFloat?, align: Alignment) -> some View {
        let isActive = viewModel.sortOrder.first?.keyPath == key
        return Button {
            let ascending = isActive && viewModel.sortOrder.first?.order == .reverse
            viewModel.sortOrder = [KeyPathComparator(key, order: ascending ? .forward : .reverse)]
        } label: {
            HStack(spacing: 3) {
                if align == .trailing { Spacer(minLength: 0) }
                Text(title).font(.system(size: 10, weight: .bold)).textCase(.uppercase).tracking(0.4)
                    .foregroundColor(isActive ? Theme.accent : Color.secondary.opacity(0.8))
                if isActive {
                    Image(systemName: viewModel.sortOrder.first?.order == .reverse ? "chevron.down" : "chevron.up")
                        .font(.system(size: 7, weight: .bold)).foregroundColor(Theme.accent)
                }
                if align == .leading { Spacer(minLength: 0) }
            }
            .frame(width: width, alignment: align)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, align == .leading ? 44 : 0)
    }
}

private struct AllProcessRow: View {
    let process: ProcessSnapshot
    let memFraction: Double
    let zebra: Bool
    let onQuit: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            if let icon = process.icon {
                Image(nsImage: icon).resizable().frame(width: 24, height: 24)
            } else {
                Image(systemName: "gearshape.fill").font(.system(size: 12)).foregroundColor(.secondary).frame(width: 24, height: 24)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(process.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                Text("PID \(process.id)").font(.system(size: 9.5, design: .monospaced)).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(String(format: "%.1f%%", process.cpuPercent))
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundColor(process.cpuPercent > 50 ? Theme.moduleColor(.uninstaller) : (process.cpuPercent > 10 ? Theme.moduleColor(.largeOldFiles) : .secondary))
                .frame(width: 64, alignment: .trailing)

            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(Color(white: 0.24)).frame(width: 56, height: 4)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(LinearGradient(colors: [Theme.moduleColor(.processes), Theme.moduleColor(.duplicates)], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(56 * memFraction, 2), height: 4)
                    }
                Text(Int64(process.memoryBytes).formattedMemoryBytes)
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .frame(width: 78, alignment: .trailing)
            }
            .frame(width: 150, alignment: .trailing)

            Group {
                if !process.isSystemProcess {
                    Button("Quit") { onQuit() }
                        .buttonStyle(.plain).font(.system(size: 10.5, weight: .bold)).foregroundColor(Theme.moduleColor(.uninstaller))
                        .opacity(hovering ? 1 : 0.55)
                } else {
                    Color.clear
                }
            }
            .frame(width: 52)
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(hovering ? Color.white.opacity(0.06) : (zebra ? Color.white.opacity(0.02) : .clear)))
        .onHover { hovering = $0 }
    }
}

private struct ProcessRow: View {
    let process: ProcessSnapshot
    let canQuit: Bool
    /// This process's memory relative to the heaviest process in its own category (0-1) —
    /// gives an at-a-glance sense of "which of these is actually worth quitting" instead of
    /// making you compare raw numbers row by row, matching CleanMyMac's compact list style.
    let memoryFraction: Double
    let onQuit: () -> Void
    @State private var showConfirm = false

    var body: some View {
        HStack(spacing: 10) {
            if let icon = process.icon {
                Image(nsImage: icon).resizable().frame(width: 22, height: 22)
            } else {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .frame(width: 22, height: 22)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(process.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.accent.opacity(0.55))
                        .frame(width: max(geo.size.width * memoryFraction, 2), height: 3)
                }
                .frame(height: 3)
            }

            Spacer()

            Text(String(format: "%.1f%%", process.cpuPercent))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(process.cpuPercent > 50 ? .red : .secondary)
                .frame(width: 55, alignment: .trailing)

            Text(Int64(process.memoryBytes).formattedMemoryBytes)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .trailing)

            if canQuit {
                Button {
                    showConfirm = true
                } label: {
                    Text("Quit")
                        .font(.system(size: 10))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .confirmationDialog("Quit \(process.name)?", isPresented: $showConfirm) {
                    Button("Quit", role: .destructive, action: onQuit)
                    Button("Cancel", role: .cancel) {}
                }
            } else {
                Color.clear.frame(width: 38)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
