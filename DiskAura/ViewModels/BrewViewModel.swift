import Foundation
import AppKit

/// Drives the Homebrew tab: installed packages, outdated upgrades, catalog search, and the
/// operation queue. All brew work runs off the main actor; only published state comes back.
@MainActor
final class BrewViewModel: ObservableObject {
    @Published private(set) var environment: BrewEnvironment?
    @Published private(set) var packages: [BrewPackage] = []
    @Published private(set) var isLoading = false
    /// Sizes still being measured — the list is already usable, so this is a subtle inline hint,
    /// not a blocking spinner.
    @Published private(set) var isMeasuring = false
    @Published private(set) var loadingStage = ""
    @Published private(set) var operation: BrewOperation?
    @Published var searchText = ""
    /// Search hits among installed packages (local, instant) and in the catalog (not installed).
    @Published private(set) var installedMatches: [BrewPackage] = []
    @Published private(set) var availableMatches: [BrewPackage] = []
    @Published private(set) var isSearching = false
    @Published var errorMessage: String?
    /// Pending confirmation — a destructive action always previews before it runs.
    @Published var pendingUninstall: (package: BrewPackage, preview: BrewPreview, dependents: [String])?
    @Published var cleanupPreview: BrewPreview?

    private let catalog = BrewCatalog()

    #if DEBUG
    /// Test seam: inject installed packages without shelling out to a real brew.
    func setPackagesForTesting(_ pkgs: [BrewPackage]) { packages = pkgs }
    #endif

    var isInstalled: Bool { environment != nil }
    var outdated: [BrewPackage] { packages.filter(\.isOutdated) }
    var installedFormulae: [BrewPackage] { packages.filter { $0.kind == .formula } }
    var installedCasks: [BrewPackage] { packages.filter { $0.kind == .cask } }
    var totalBytes: Int64 { packages.reduce(0) { $0 + $1.sizeBytes } }

    private func makeService() -> BrewService? {
        guard let environment else { return nil }
        return BrewService(runner: ProcessBrewRunner(binaryPath: environment.binaryPath),
                           environment: environment)
    }

    // MARK: - Loading

    /// Two-phase on purpose. Reading brew's JSON is fast; measuring every package walks the whole
    /// Cellar/Caskroom (~2.6GB of directories) and is slow. Doing both before showing anything left
    /// the tab blank with no explanation, so phase 1 publishes the list immediately and phase 2
    /// fills sizes in behind it.
    func load() {
        environment = BrewEnvironment.locate()
        guard let service = makeService() else { return }
        isLoading = true
        loadingStage = "Reading installed packages…"
        Task {
            let parsed = await Task.detached(priority: .userInitiated) {
                (try? service.installedPackages()) ?? []
            }.value
            self.packages = parsed.sorted { $0.name < $1.name }
            self.isLoading = false

            guard !parsed.isEmpty else { return }
            self.isMeasuring = true
            self.loadingStage = "Measuring package sizes…"
            let measured = await Task.detached(priority: .utility) { () -> [BrewPackage] in
                var pkgs = parsed
                for i in pkgs.indices { pkgs[i].sizeBytes = service.sizeOnDisk(pkgs[i]) }
                return pkgs.sorted { $0.sizeBytes > $1.sizeBytes }
            }.value
            self.packages = measured
            self.isMeasuring = false
            self.loadingStage = ""

            await self.catalog.loadCache()
            if await self.catalog.isStale { Task.detached { await self.catalog.refresh() } }
        }
    }

    // MARK: - Search

    /// Searches BOTH what's installed and what's available. Installed matches come from local data
    /// so they appear instantly and work offline; catalog matches follow. The two are kept separate
    /// because the useful action differs — upgrade/remove versus install.
    func runSearch() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard query.count >= 2 else {
            installedMatches = []; availableMatches = []; isSearching = false; return
        }
        let q = query.lowercased()

        // Phase 1 — local, instant.
        installedMatches = packages.filter {
            $0.name.lowercased().contains(q) || $0.desc.lowercased().contains(q)
        }.sorted { lhs, rhs in
            // Exact name first, then prefix, then the rest — same intent as the catalog ranking.
            func rank(_ p: BrewPackage) -> Int {
                let n = p.name.lowercased()
                return n == q ? 0 : (n.hasPrefix(q) ? 1 : (n.contains(q) ? 2 : 3))
            }
            return rank(lhs) == rank(rhs) ? lhs.name < rhs.name : rank(lhs) < rank(rhs)
        }

        // Phase 2 — catalog, excluding anything already installed (it's in phase 1 already).
        isSearching = true
        Task {
            var results = await catalog.search(query)
            if results.isEmpty, let service = makeService(), await !catalog.isLoaded {
                // Never cached and offline — slower CLI path so search still returns something.
                results = await Task.detached { BrewCatalog.cliSearch(query, service: service) }.value
            }
            let installedIDs = Set(self.packages.map(\.id))
            self.availableMatches = results.filter { !installedIDs.contains($0.id) }
            self.isSearching = false
        }
    }

    var hasSearchQuery: Bool { searchText.trimmingCharacters(in: .whitespaces).count >= 2 }
    var hasAnyMatches: Bool { !installedMatches.isEmpty || !availableMatches.isEmpty }

    // MARK: - Destructive actions (preview first)

    /// Builds the confirmation: what brew would remove, and who still depends on it.
    func requestUninstall(_ pkg: BrewPackage) {
        guard let service = makeService() else { return }
        Task {
            let (preview, dependents) = await Task.detached { () -> (BrewPreview, [String]) in
                let p = (try? service.previewUninstall(pkg)) ?? BrewPreview(lines: [], reclaimableBytes: 0)
                let d = (try? service.dependents(of: pkg.name)) ?? []
                return (p, d)
            }.value
            self.pendingUninstall = (pkg, preview, dependents)
        }
    }

    func confirmUninstall() {
        guard let pending = pendingUninstall else { return }
        pendingUninstall = nil
        run(.uninstall, target: pending.package.name,
            args: BrewService.uninstallArguments(pending.package))
    }

    func requestCleanup() {
        guard let service = makeService() else { return }
        Task {
            let preview = await Task.detached {
                (try? service.previewCleanup()) ?? BrewPreview(lines: [], reclaimableBytes: 0)
            }.value
            self.cleanupPreview = preview
        }
    }

    func confirmCleanup() {
        cleanupPreview = nil
        run(.cleanup, target: "", args: BrewService.cleanupArguments(dryRun: false))
    }

    func install(_ pkg: BrewPackage) {
        run(.install, target: pkg.name, args: BrewService.installArguments(pkg))
    }

    func upgrade(_ pkg: BrewPackage?) {
        run(.upgrade, target: pkg?.name ?? "", args: BrewService.upgradeArguments(pkg))
    }

    // MARK: - Operation runner

    private func run(_ kind: BrewOperation.Kind, target: String, args: [String]) {
        guard operation?.isRunning != true, let service = makeService() else { return }
        operation = BrewOperation(kind: kind, target: target)
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> BrewResult? in
                try? service.runner.stream(args) { line in
                    Task { @MainActor in self.operation?.log.append(line) }
                }
            }.value
            if let result, result.succeeded {
                self.operation?.state = .succeeded(self.successText(kind, target: target))
            } else {
                // brew's own stderr is almost always the clearest explanation — show it verbatim.
                let reason = (result?.stderr).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
                self.operation?.state = .failed(reason.isEmpty ? "\(kind.verb) failed." : reason)
            }
            self.load()   // re-read real state rather than assuming the outcome
        }
    }

    private func successText(_ kind: BrewOperation.Kind, target: String) -> String {
        switch kind {
        case .install: return "Installed \(target)."
        case .uninstall: return "Uninstalled \(target)."
        case .upgrade: return target.isEmpty ? "Upgraded all packages." : "Upgraded \(target)."
        case .cleanup: return "Cleanup finished."
        }
    }

    func dismissOperation() { if operation?.isRunning == false { operation = nil } }

    func openBrewWebsite() {
        if let url = URL(string: "https://brew.sh") { NSWorkspace.shared.open(url) }
    }
}
