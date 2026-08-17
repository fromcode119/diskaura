import SwiftUI

/// Homebrew tab: installed packages with sizes, outdated upgrades, catalog search and install,
/// and cleanup. Destructive actions always preview first — brew deletes with no Trash step.
struct BrewView: View {
    @StateObject private var viewModel = BrewViewModel()
    private var accent: Color { Theme.moduleColor(.homebrew) }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isInstalled {
                header
                Divider()
                content
            } else {
                BrewNotInstalledCard(accent: accent) { viewModel.openBrewWebsite() }
            }
        }
        .background(Theme.appGradient)
        .safeAreaInset(edge: .bottom) {
            if let op = viewModel.operation {
                BrewOperationBar(operation: op, accent: accent) { viewModel.dismissOperation() }
            }
        }
        .onAppear { if viewModel.packages.isEmpty { viewModel.load() } }
        .alert("Remove \(viewModel.pendingUninstall?.package.name ?? "")?",
               isPresented: Binding(get: { viewModel.pendingUninstall != nil },
                                    set: { if !$0 { viewModel.pendingUninstall = nil } })) {
            // Blocked entirely while something depends on it — removing would break those packages.
            if viewModel.pendingUninstall?.dependents.isEmpty == false {
                Button("OK", role: .cancel) {}
            } else {
                Button("Remove", role: .destructive) { viewModel.confirmUninstall() }
                Button("Cancel", role: .cancel) {}
            }
        } message: {
            Text(uninstallMessage)
        }
        .alert("Clean up Homebrew?", isPresented: Binding(
            get: { viewModel.cleanupPreview != nil }, set: { if !$0 { viewModel.cleanupPreview = nil } })) {
            Button("Clean up", role: .destructive) { viewModel.confirmCleanup() }
            Button("Cancel", role: .cancel) {}
        } message: {
            let p = viewModel.cleanupPreview
            Text("Removes stale downloads and superseded versions of packages you still have."
                 + ((p?.reclaimableBytes ?? 0) > 0
                    ? "\n\nFrees about \(p!.reclaimableBytes.formattedBytes)."
                    : "\n\nNothing to reclaim right now."))
        }
    }

    private var uninstallMessage: String {
        guard let pending = viewModel.pendingUninstall else { return "" }
        if !pending.dependents.isEmpty {
            return "\(pending.package.name) can't be removed — these installed packages still "
                 + "depend on it: \(pending.dependents.prefix(6).joined(separator: ", ")). "
                 + "Remove those first."
        }
        let size = pending.package.sizeBytes
        return "Homebrew deletes immediately — there's no Trash step, so this can't be undone from "
             + "here.\n\nFrees about \(size > 0 ? size.formattedBytes : "an unknown amount")."
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Homebrew").font(Theme.TypeScale.title)
                    HStack(spacing: 6) {
                        Text(subtitle).font(.system(size: 11)).foregroundColor(.secondary)
                        // Sizes arrive after the list; say so rather than showing a silent 0 B.
                        if viewModel.isMeasuring { ProgressView().controlSize(.small).scaleEffect(0.7) }
                    }
                }
                Spacer()
                // Both actions use the pill family so they share font, padding and height.
                Button { viewModel.requestCleanup() } label: { Label("Clean up", systemImage: "sparkles") }
                    .buttonStyle(.softPill(accent))
                    .disabled(viewModel.operation?.isRunning == true || viewModel.isLoading)
                if !viewModel.outdated.isEmpty {
                    Button { viewModel.upgrade(nil) } label: {
                        Label("Upgrade all \(viewModel.outdated.count)", systemImage: "arrow.up.circle.fill")
                    }
                    .buttonStyle(.pill(accent))
                    .disabled(viewModel.operation?.isRunning == true)
                }
            }
            searchField
        }
        .padding(Theme.Spacing.md)
    }

    /// Never reports a total while it's still being measured — a growing number that starts near
    /// zero reads as wrong data.
    private var subtitle: String {
        if viewModel.isLoading { return "Reading installed packages…" }
        var parts = ["\(viewModel.packages.count) installed"]
        if viewModel.isMeasuring { parts.append("measuring sizes…") }
        else if viewModel.totalBytes > 0 { parts.append(viewModel.totalBytes.formattedBytes) }
        if !viewModel.outdated.isEmpty { parts.append("\(viewModel.outdated.count) outdated") }
        return parts.joined(separator: " · ")
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundColor(.secondary)
            TextField("Search Homebrew for something to install…", text: $viewModel.searchText)
                .textFieldStyle(.plain).font(.system(size: 12.5))
                .onSubmit { viewModel.runSearch() }
                .onChange(of: viewModel.searchText) { _, _ in viewModel.runSearch() }
            if viewModel.isSearching { ProgressView().controlSize(.small) }
            if !viewModel.searchText.isEmpty {
                Button { viewModel.searchText = ""; viewModel.runSearch() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        if viewModel.isLoading && viewModel.packages.isEmpty {
            loadingState
        } else {
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.md) {
                    if !viewModel.searchResults.isEmpty { searchSection }
                    if !viewModel.outdated.isEmpty && viewModel.searchResults.isEmpty { outdatedSection }
                    if viewModel.searchResults.isEmpty { installedSection }
                }
                .padding(Theme.Spacing.lg)
            }
        }
    }

    /// Opening the tab used to show an empty pane while brew was read — indistinguishable from
    /// "nothing installed". State what's happening instead.
    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text(viewModel.loadingStage.isEmpty ? "Reading Homebrew…" : viewModel.loadingStage)
                .font(.system(size: 13, weight: .medium))
            Text("Asking brew what's installed and how much space it uses.")
                .font(.system(size: 11)).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var searchSection: some View {
        section("Search results", subtitle: "\(viewModel.searchResults.count) match\(viewModel.searchResults.count == 1 ? "" : "es")") {
            ForEach(viewModel.searchResults) { pkg in
                BrewPackageRow(package: pkg, accent: accent,
                               isBusy: viewModel.operation?.isRunning == true,
                               onInstall: { viewModel.install(pkg) })
            }
        }
    }

    private var outdatedSection: some View {
        section("Outdated", subtitle: "\(viewModel.outdated.count) package\(viewModel.outdated.count == 1 ? "" : "s") can be upgraded") {
            ForEach(viewModel.outdated) { pkg in
                BrewPackageRow(package: pkg, accent: accent,
                               isBusy: viewModel.operation?.isRunning == true,
                               onUpgrade: { viewModel.upgrade(pkg) },
                               onUninstall: { viewModel.requestUninstall(pkg) })
            }
        }
    }

    private var installedSection: some View {
        section("Installed", subtitle: "\(viewModel.installedFormulae.count) formulae · \(viewModel.installedCasks.count) casks · largest first") {
            ForEach(viewModel.packages) { pkg in
                BrewPackageRow(package: pkg, accent: accent,
                               isBusy: viewModel.operation?.isRunning == true,
                               onUpgrade: pkg.isOutdated ? { viewModel.upgrade(pkg) } : nil,
                               onUninstall: { viewModel.requestUninstall(pkg) })
            }
        }
    }

    private func section<C: View>(_ title: String, subtitle: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 14, weight: .bold))
                Text(subtitle).font(.system(size: 10.5)).foregroundColor(.secondary)
            }
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 8)
            content()
        }
        .glassCard()
    }
}
