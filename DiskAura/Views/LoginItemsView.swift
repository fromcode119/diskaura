import SwiftUI
import AppKit

/// Login Items / Launch Agents manager — the startup items macOS runs in the background. Same
/// design language as the rest of the app: donut of items-by-domain + stat tiles + a dense
/// table, with multi-select removal (recoverable to Trash) and admin flagging.
struct LoginItemsView: View {
    @StateObject private var viewModel = LoginItemsViewModel()
    @State private var searchText = ""
    @State private var selection: Set<String> = []
    @State private var confirmRemove = false

    private var filtered: [LaunchItem] {
        guard !searchText.isEmpty else { return viewModel.items }
        let q = searchText.lowercased()
        return viewModel.items.filter { $0.label.lowercased().contains(q) || $0.program.lowercased().contains(q) }
    }
    private var selectedItems: [LaunchItem] { viewModel.items.filter { selection.contains($0.id) } }

    private var segments: [DonutSegment] {
        [
            DonutSegment(id: "user", label: "User agents", sizeBytes: Int64(viewModel.userItems.count), color: Theme.moduleColor(.loginItems), valueText: "\(viewModel.userItems.count)"),
            DonutSegment(id: "system", label: "System agents", sizeBytes: Int64(viewModel.systemItems.count), color: Theme.moduleColor(.scan), valueText: "\(viewModel.systemItems.count)"),
            DonutSegment(id: "daemon", label: "Daemons", sizeBytes: Int64(viewModel.daemonItems.count), color: Theme.moduleColor(.uninstaller), valueText: "\(viewModel.daemonItems.count)"),
        ].filter { $0.sizeBytes > 0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            StatHero(
                segments: segments,
                centerValue: "\(viewModel.items.count)",
                centerLabel: "startup items",
                tiles: [
                    StatTileData(title: "Startup items", value: "\(viewModel.items.count)", glow: Theme.moduleColor(.loginItems), icon: "power"),
                    StatTileData(title: "Run at login", value: "\(viewModel.runAtLoadCount)", glow: Theme.moduleColor(.processes), icon: "bolt.fill"),
                    StatTileData(title: "User agents", value: "\(viewModel.userItems.count)", glow: Theme.moduleColor(.scan), icon: "person.fill"),
                    StatTileData(title: "System · daemons", value: "\(viewModel.systemItems.count + viewModel.daemonItems.count)", glow: Theme.moduleColor(.uninstaller), icon: "lock.shield.fill"),
                ]
            )
            .padding(.horizontal, Theme.Spacing.lg).padding(.bottom, 14)

            if let msg = viewModel.message {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle.fill").foregroundColor(Theme.moduleColor(.scan))
                    Text(msg).font(.system(size: 12, weight: .medium)); Spacer()
                    if !viewModel.lastRestorePairs.isEmpty {
                        Button("Undo") { viewModel.undoLastRemove() }.buttonStyle(.bordered).controlSize(.small)
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg).padding(.vertical, 9)
                .background(Theme.moduleColor(.scan).opacity(0.08))
            }

            Divider()
            table
            if !selection.isEmpty { removeBar }
        }
        .background(Theme.appGradient)
        .confirmationDialog("Remove \(selection.count) startup items?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Move \(selection.count) to Trash", role: .destructive) {
                viewModel.remove(selectedItems); selection.removeAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Their .plist files move to the Trash (recoverable), so they stop launching. System items under /Library need admin rights and are left for you.")
        }
        .onAppear { if viewModel.items.isEmpty { viewModel.load() } }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Login Items").font(Theme.TypeScale.title)
                Text(viewModel.isLoading ? "Reading LaunchAgents & LaunchDaemons…"
                     : "\(viewModel.items.count) background startup items · \(viewModel.runAtLoadCount) run at login")
                    .font(.system(size: 12)).foregroundColor(.secondary)
            }
            Spacer()
            if viewModel.isLoading { ProgressView().controlSize(.small) }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundColor(.secondary)
                TextField("Filter…", text: $searchText).textFieldStyle(.plain).font(.system(size: 12)).frame(width: 150)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
        }
        .padding(.horizontal, Theme.Spacing.lg).padding(.top, Theme.Spacing.md).padding(.bottom, 10)
    }

    private var table: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                HStack(spacing: 12) {
                    Color.clear.frame(width: 20)
                    Text("Startup item").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Runs at login").frame(width: 110, alignment: .leading)
                    Text("On").frame(width: 60, alignment: .leading)
                    Text("Location").frame(width: 130, alignment: .leading)
                    Color.clear.frame(width: 70)
                }
                .font(.system(size: 10.5, weight: .bold)).foregroundStyle(.tertiary).textCase(.uppercase).tracking(0.4)
                .padding(.vertical, 9)

                ForEach(filtered) { item in
                    row(item)
                    Divider().padding(.leading, 44)
                }
            }
            .padding(.horizontal, Theme.Spacing.lg).padding(.bottom, Theme.Spacing.md)
        }
    }

    private func row(_ item: LaunchItem) -> some View {
        let isChecked = selection.contains(item.id)
        return HStack(spacing: 12) {
            Button {
                if isChecked { selection.remove(item.id) } else { selection.insert(item.id) }
            } label: {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15)).foregroundColor(isChecked ? Theme.moduleColor(.loginItems) : .secondary.opacity(0.45))
            }
            .buttonStyle(.plain).frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.label).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if item.requiresAdmin { tag("ADMIN", Theme.moduleColor(.largeOldFiles)) }
                }
                Text(item.program).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 5) {
                Circle().fill(item.runAtLoad ? Theme.moduleColor(.processes) : Color.secondary.opacity(0.4)).frame(width: 7, height: 7)
                Text(item.runAtLoad ? "Yes" : "On demand").font(.system(size: 11.5)).foregroundColor(.secondary)
            }
            .frame(width: 110, alignment: .leading)

            // Enable/disable toggle — user agents can be flipped via launchctl; system items
            // are disabled (need sudo) and shown as a static label.
            Group {
                if item.domain == .userAgent {
                    Toggle("", isOn: Binding(get: { item.enabled }, set: { _ in viewModel.toggle(item) }))
                        .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                } else {
                    Text(item.enabled ? "On" : "Off").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }
            .frame(width: 60, alignment: .leading)

            HStack(spacing: 8) {
                Button { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } label: {
                    Image(systemName: "folder").font(.system(size: 11))
                }.buttonStyle(.plain).foregroundStyle(.tertiary).help("Show in Finder")
                Button("Remove") { selection = [item.id]; confirmRemove = true }
                    .buttonStyle(.plain).font(.system(size: 11, weight: .bold)).foregroundColor(Theme.moduleColor(.uninstaller))
            }
            .frame(width: 70, alignment: .trailing)
        }
        .padding(.vertical, 9)
        .opacity(item.enabled ? 1 : 0.5)
    }

    private var removeBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                if viewModel.isRemoving {
                    ProgressView().controlSize(.small); Text("Removing…").font(.system(size: 12, weight: .medium)); Spacer()
                } else {
                    Text("\(selection.count) selected").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button("Clear") { selection.removeAll() }.buttonStyle(.plain).font(.system(size: 12)).foregroundColor(.secondary)
                    Button { confirmRemove = true } label: {
                        Label("Remove \(selection.count)", systemImage: "trash").font(.system(size: 12.5, weight: .semibold))
                    }.buttonStyle(.pill(Theme.moduleColor(.uninstaller)))
                }
            }
            .padding(.horizontal, Theme.Spacing.lg).padding(.vertical, 11).background(.ultraThinMaterial)
        }
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 7.5, weight: .bold))
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(color.opacity(0.2)).foregroundColor(color).clipShape(RoundedRectangle(cornerRadius: 3))
    }
}
