import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var classification: ClassificationEngine
    @ObservedObject var actionQueueVM: ActionQueueViewModel
    @ObservedObject var scheduledScan: ScheduledScanService
    @ObservedObject var exclusions: ExclusionStore
    @State private var recentActions: [ActionLogEntry] = []
    @State private var hasFullDiskAccess = FullDiskAccessService.isGranted()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text("Settings").font(Theme.TypeScale.title)

                fullDiskAccessCard

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        sectionHeader(icon: "hand.raised.fill", tint: Theme.moduleColor(.uninstaller), title: "Ignore List")
                        Spacer()
                        Button {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = true
                            panel.canChooseFiles = false
                            panel.allowsMultipleSelection = true
                            if panel.runModal() == .OK { panel.urls.forEach { exclusions.add($0) } }
                        } label: { Label("Add Folder", systemImage: "plus") }
                        .buttonStyle(.bordered).controlSize(.small)
                    }
                    Text("DiskAura never scans, counts, or offers to clean these folders.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                    if exclusions.paths.isEmpty {
                        Text("No ignored folders.").font(.caption).foregroundColor(.secondary)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(exclusions.paths, id: \.self) { path in
                                HStack(spacing: 10) {
                                    Image(systemName: "folder.fill").font(.system(size: 12)).foregroundColor(.secondary)
                                    Text(displayPath(path)).font(.system(size: 11, design: .monospaced))
                                        .lineLimit(1).truncationMode(.middle)
                                    Spacer()
                                    Button { exclusions.remove(path) } label: {
                                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                                    }.buttonStyle(.plain)
                                }
                                .padding(.vertical, 7)
                                if path != exclusions.paths.last { Divider() }
                            }
                        }
                    }
                }
                .padding(18)
                .glassCard()

                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader(icon: "clock.arrow.circlepath", tint: Theme.moduleColor(.scan), title: "Scheduled Scans")
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Automatically re-scan the last folder in the background", isOn: Binding(
                            get: { scheduledScan.isEnabled },
                            set: { scheduledScan.isEnabled = $0; scheduledScan.reschedule() }
                        ))
                        .toggleStyle(.switch)
                        if scheduledScan.isEnabled {
                            HStack {
                                Text("Every").font(.system(size: 12))
                                Stepper(value: Binding(
                                    get: { scheduledScan.intervalHours },
                                    set: { scheduledScan.intervalHours = $0; scheduledScan.reschedule() }
                                ), in: 1...48, step: 1) {
                                    Text("\(Int(scheduledScan.intervalHours))h")
                                        .font(.system(size: 12, design: .monospaced))
                                }
                            }
                            Text("Growth of 1GB+ since the last scan triggers a notification.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Divider().padding(.vertical, 2)
                        Toggle("Auto-clean safe junk to the Trash on each scheduled run", isOn: Binding(
                            get: { scheduledScan.autoCleanEnabled },
                            set: { scheduledScan.autoCleanEnabled = $0 }
                        ))
                        .toggleStyle(.switch)
                        HStack(spacing: 10) {
                            Text("Only caches, logs & crash reports — moved to Trash (recoverable), never emptied automatically.")
                                .font(.caption).foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Button("Run now") { scheduledScan.runAutoCleanNow() }
                                .buttonStyle(.bordered)
                        }
                        if let summary = scheduledScan.lastAutoCleanSummary {
                            Text(summary).font(.caption).foregroundColor(Theme.moduleColor(.cleanup))
                        }
                    }
                }
                .padding(18)
                .glassCard()

                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader(icon: "tag.fill", tint: Theme.moduleColor(.largeOldFiles), title: "Classification Rules")
                    VStack(spacing: 0) {
                        ForEach(classification.rules) { rule in
                            HStack {
                                TagPill(tag: rule.tag)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(rule.name).font(.system(size: 12, weight: .semibold))
                                    if let note = rule.note {
                                        Text(note).font(.system(size: 10)).foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                Text(rule.pattern)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 8)
                            if rule.id != classification.rules.last?.id {
                                Divider()
                            }
                        }
                    }
                }
                .padding(18)
                .glassCard()

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        sectionHeader(icon: "list.bullet.rectangle", tint: Theme.moduleColor(.processes), title: "Recent Actions")
                        Spacer()
                        Button("Refresh") { recentActions = ActionExecutor.loadLog() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    if recentActions.isEmpty {
                        Text("No actions executed yet.").font(.caption).foregroundColor(.secondary)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(recentActions.prefix(50), id: \.timestamp) { entry in
                                HStack {
                                    Text(entry.kind.rawValue).font(.system(size: 11, weight: .semibold))
                                        .frame(width: 110, alignment: .leading)
                                    Text(entry.path)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                    Text(entry.sizeBytes.formattedBytes)
                                        .font(.system(size: 11, design: .monospaced))
                                }
                                .padding(.vertical, 6)
                                if entry.timestamp != recentActions.prefix(50).last?.timestamp {
                                    Divider()
                                }
                            }
                        }
                    }
                }
                .padding(18)
                .glassCard()
            }
            .padding(Theme.Spacing.lg)
        }
        .onAppear { recentActions = ActionExecutor.loadLog() }
    }

    /// Full Disk Access status + one-click deep link. Shown green/reassuring when granted,
    /// amber/actionable when not — because without it, cleanup and uninstall silently miss
    /// protected caches and leftovers (the "nothing happened" class of bug).
    @ViewBuilder private var fullDiskAccessCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader(
                    icon: hasFullDiskAccess ? "checkmark.shield.fill" : "exclamationmark.shield.fill",
                    tint: hasFullDiskAccess ? .green : .orange,
                    title: "Full Disk Access"
                )
                Spacer()
                Button("Re-check") { hasFullDiskAccess = FullDiskAccessService.isGranted() }
                    .buttonStyle(.bordered).controlSize(.small)
            }
            if hasFullDiskAccess {
                Text("Granted. DiskAura can see every cache, container and leftover it needs to clean and uninstall thoroughly.")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            } else {
                Text("Not granted. Without it, macOS hides protected caches and app leftovers — so cleanups and uninstalls can miss files. Turn DiskAura on in System Settings, then Re-check.")
                    .font(.system(size: 11)).foregroundColor(.secondary)
                Button {
                    FullDiskAccessService.openSettingsPane()
                } label: { Label("Open System Settings", systemImage: "arrow.up.forward.app") }
                .buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
        .padding(18)
        .glassCard()
    }

    private func sectionHeader(icon: String, tint: Color, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundColor(tint)
            Text(title).font(.system(size: 15, weight: .semibold))
        }
    }

    private func displayPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~/" + path.dropFirst(home.count + 1) }
        return path
    }
}
