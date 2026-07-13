import SwiftUI

@main
struct DiskAuraApp: App {
    @StateObject private var menuBarMonitor = MenuBarVolumeMonitor()
    @StateObject private var router = AppRouter()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView(router: router)
                .frame(minWidth: 960, minHeight: 640)
                .tint(Theme.accent)
                // The whole product is designed as a premium dark app (the sunburst, the
                // dark cards) — pinning the scheme keeps it consistent instead of flipping
                // to a washed-out light look when the user's system is in light mode.
                .preferredColorScheme(.dark)
                .onAppear { menuBarMonitor.start(); AppRemovalWatcher.shared.start() }
        }
        .windowResizability(.contentSize)
        .commands {
            // Discoverable View menu with Cmd+1…N to jump between modules — the canonical
            // Mac-app place for navigation shortcuts.
            CommandGroup(after: .sidebar) {
                ForEach(Array(SidebarTab.allCases.enumerated()), id: \.element) { i, tab in
                    // ⌘1–⌘9 only — beyond 9 there's no single-digit key, and Character("10")
                    // would fatally trap. Tabs past the ninth are still reachable in the sidebar.
                    if i < 9 {
                        Button(tab.rawValue) { router.selectedTab = tab }
                            .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                    } else {
                        Button(tab.rawValue) { router.selectedTab = tab }
                    }
                }
            }
        }

        MenuBarExtra {
            MenuBarPanel(monitor: menuBarMonitor, router: router)
        } label: {
            MenuBarLabel(monitor: menuBarMonitor)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var monitor: MenuBarVolumeMonitor

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: monitor.isLow ? "exclamationmark.triangle.fill" : "internaldrive")
            if let stats = monitor.stats {
                Text(stats.freeBytes.formattedBytes)
            }
        }
    }
}

private struct MenuBarPanel: View {
    @ObservedObject var monitor: MenuBarVolumeMonitor
    @ObservedObject var router: AppRouter
    @Environment(\.openWindow) private var openWindow
    @State private var junkBytes: Int64?
    @State private var checkingJunk = false
    @State private var memory = SystemStatsService.memory()
    @State private var temp = SystemStatsService.temperature()
    @State private var cpu = SystemStatsService.cpuLoad()
    private let ticker = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    private var usedFraction: Double {
        guard let s = monitor.stats, s.totalBytes > 0 else { return 0 }
        return Double(s.usedBytes) / Double(s.totalBytes)
    }
    private var accent: Color { monitor.isLow ? Color(red: 1, green: 0.38, blue: 0.44) : Color(red: 0.34, green: 0.62, blue: 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 9) {
                Image("AppLogo").resizable().interpolation(.high).frame(width: 24, height: 24)
                Text("DiskAura").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button { refresh() } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Refresh")
            }
            .padding(.bottom, 14)

            // Disk usage ring + numbers
            if let stats = monitor.stats {
                HStack(spacing: 16) {
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.10), lineWidth: 11).frame(width: 92, height: 92)
                        Circle().trim(from: 0, to: usedFraction)
                            .stroke(AngularGradient(colors: [accent, accent.opacity(0.7)], center: .center),
                                    style: StrokeStyle(lineWidth: 11, lineCap: .round))
                            .rotationEffect(.degrees(-90)).frame(width: 92, height: 92)
                        VStack(spacing: 0) {
                            Text(stats.freeBytes.formattedBytes)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(monitor.isLow ? accent : .primary)
                            Text("free").font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        legendRow(accent, "Used", stats.usedBytes.formattedBytes)
                        legendRow(Color.white.opacity(0.18), "Free", stats.freeBytes.formattedBytes)
                        Text("of \(stats.totalBytes.formattedBytes) total").font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 12)

                if monitor.isLow {
                    HStack(spacing: 7) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(accent)
                        Text("Below 10% free — time for a scan").font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(accent.opacity(0.14)))
                    .padding(.bottom, 12)
                }
            } else {
                HStack { Spacer(); ProgressView(); Spacer() }.padding(.vertical, 20)
            }

            // Removable junk
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 6).fill(Color(red: 0.30, green: 0.80, blue: 0.90))
                    .frame(width: 22, height: 22)
                    .overlay(Image(systemName: "sparkles").font(.system(size: 11)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 0) {
                    Text("Removable junk").font(.system(size: 12, weight: .medium))
                    Text("caches · logs · trash").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                Spacer()
                if checkingJunk { ProgressView().controlSize(.mini) }
                else if let junkBytes {
                    Text(junkBytes.formattedBytes).font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 0.30, green: 0.80, blue: 0.90))
                } else { Text("—").foregroundStyle(.secondary) }
            }
            .padding(.vertical, 8).padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.05)))
            .padding(.bottom, 10)

            Button { openApp(tab: .cleanup) } label: {
                Label("Review in Cleanup", systemImage: "arrow.right.circle.fill")
                    .font(.system(size: 12, weight: .semibold)).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(Color(red: 0.30, green: 0.80, blue: 0.90))
            .padding(.bottom, 12)

            // Live system glance — CPU + memory pressure + thermal state (updates while open).
            HStack(spacing: 8) {
                systemStat(icon: "cpu.fill", color: Color(red: 0.30, green: 0.82, blue: 0.58),
                           title: "CPU",
                           value: "\(Int((cpu * 100).rounded()))%",
                           fraction: cpu)
                systemStat(icon: "memorychip.fill", color: Color(red: 0.68, green: 0.48, blue: 1),
                           title: "Memory",
                           value: memory.usedBytes.formattedMemoryBytes,
                           fraction: memory.usedFraction)
                systemStat(icon: "thermometer.medium", color: thermalColor,
                           title: "Temp",
                           value: temp.available ? "\(Int(temp.peakCelsius.rounded()))°C" : SystemStatsService.thermal().rawValue,
                           fraction: temp.available ? min(temp.peakCelsius / 100, 1) : nil)
            }
            .padding(.bottom, 12)

            Divider().padding(.bottom, 10)

            HStack {
                Button { openApp(tab: nil) } label: { Label("Open", systemImage: "macwindow").font(.system(size: 12)) }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.font(.system(size: 12))
            }
        }
        .padding(16)
        .frame(width: 300)
        .task { await rescanJunk() }
        .onReceive(ticker) { _ in
            memory = SystemStatsService.memory()
            temp = SystemStatsService.temperature()
            cpu = SystemStatsService.cpuLoad()
        }
    }

    private var thermalColor: Color {
        switch temp.available ? temp.level : SystemStatsService.thermal() {
        case .normal: return Color(red: 0.30, green: 0.82, blue: 0.58)
        case .fair: return Color(red: 1.00, green: 0.62, blue: 0.20)
        case .serious, .critical: return Color(red: 1, green: 0.38, blue: 0.44)
        }
    }

    /// Vertical tile: the three-across row is too narrow for icon+title+value on one line
    /// (it truncated "Memory" to "Me…" and clipped the value). Stacking gives the title and
    /// value the tile's full width so both stay readable.
    private func systemStat(icon: String, color: Color, title: String, value: String, fraction: Double?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 5).fill(color).frame(width: 18, height: 18)
                    .overlay(Image(systemName: icon).font(.system(size: 9, weight: .semibold)).foregroundStyle(.white))
                Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            Text(value).font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.7)
            if let fraction {
                RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.12)).frame(height: 3)
                    .overlay(alignment: .leading) {
                        GeometryReader { g in
                            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: max(g.size.width * fraction, 2))
                        }.frame(height: 3)
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 9).padding(.horizontal, 9)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.05)))
    }

    private func legendRow(_ color: Color, _ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 9, height: 9)
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer(minLength: 10)
            Text(value).font(.system(size: 12, weight: .semibold, design: .rounded))
        }
    }

    private func refresh() {
        monitor.refresh()
        Task { await rescanJunk() }
    }

    private func rescanJunk() async {
        checkingJunk = true
        let bytes = await Task.detached(priority: .utility) {
            JunkScanner.scan().reduce(Int64(0)) { $0 + $1.totalBytes }
        }.value
        junkBytes = bytes
        checkingJunk = false
    }

    private func openApp(tab: SidebarTab?) {
        if let tab { router.selectedTab = tab }
        NSApp.activate(ignoringOtherApps: true)
        // Find the real content window (titled). The menu-bar panel is a borderless panel, so
        // filtering on `.titled` excludes it. If the content window exists (even miniaturized or
        // hidden behind), bring it forward; only spawn a new one when there genuinely isn't one.
        // The old check ("all windows invisible") was always false while this panel was open, so
        // the window never reopened after being closed — which made Review/Open do nothing.
        if let content = NSApp.windows.first(where: { $0.styleMask.contains(.titled) }) {
            content.deminiaturize(nil)
            content.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
    }
}
