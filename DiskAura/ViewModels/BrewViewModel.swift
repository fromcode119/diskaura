import Foundation
import AppKit

/// Drives the Homebrew tab: installed packages, outdated upgrades, catalog search, and the
/// operation queue. All brew work runs off the main actor; only published state comes back.
@MainActor
final class BrewViewModel: ObservableObject {
    @Published private(set) var environment: BrewEnvironment?
    @Published private(set) var packages: [BrewPackage] = []
    @Published private(set) var isLoading = false
    @Published private(set) var operation: BrewOperation?
    @Published var searchText = ""
    @Published private(set) var searchResults: [BrewPackage] = []
    @Published private(set) var isSearching = false
    @Published var errorMessage: String?
    /// Pending confirmation — a destructive action always previews before it runs.
    @Published var pendingUninstall: (package: BrewPackage, preview: BrewPreview, dependents: [String])?
    @Published var cleanupPreview: BrewPreview?

    private let catalog = BrewCatalog()

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

    func load() {
        environment = BrewEnvironment.locate()
        guard let service = makeService() else { return }
        isLoading = true
        Task {
            let loaded = await Task.detached(priority: .userInitiated) { () -> [BrewPackage] in
                guard var pkgs = try? service.installedPackages() else { return [] }
                // Sizes come from disk; brew has no fast size query.
                for i in pkgs.indices { pkgs[i].sizeBytes = service.sizeOnDisk(pkgs[i]) }
                return pkgs.sorted { $0.sizeBytes > $1.sizeBytes }
            }.value
            self.packages = loaded
            self.isLoading = false
            await self.catalog.loadCache()
            if await self.catalog.isStale { Task.detached { await self.catalog.refresh() } }
        }
    }

    // MARK: - Search

    func runSearch() {
        let query = searchText
        guard query.trimmingCharacters(in: .whitespaces).count >= 2 else { searchResults = []; return }
        isSearching = true
        Task {
            var results = await catalog.search(query)
            // Offline / never-cached fallback so search still works, just slower.
            if results.isEmpty, let service = makeService(), await !catalog.isLoaded {
                results = await Task.detached { BrewCatalog.cliSearch(query, service: service) }.value
            }
            let installedNames = Set(self.packages.map(\.id))
            self.searchResults = results.map { r in
                var r = r
                if let hit = self.packages.first(where: { $0.id == r.id }) { r.installedVersion = hit.installedVersion }
                return r
            }.filter { !$0.isInstalled || installedNames.isEmpty }
            self.isSearching = false
        }
    }

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
