import Foundation

@MainActor
final class UninstallerViewModel: ObservableObject {
    @Published var apps: [InstalledApp] = []
    @Published var isLoading = false
    @Published var selectedApp: InstalledApp?
    @Published var leftoversLoadedIDs: Set<String> = []

    /// Shows the app list immediately (cheap directory listing), then fills in each app's
    /// real on-disk size in the background — previously the whole list waited behind every
    /// app's recursive size scan before a single row appeared.
    func loadApps() {
        isLoading = true
        let fastList = AppUninstallerService.listInstalledApps()
        self.apps = fastList
        self.isLoading = false

        Task.detached(priority: .userInitiated) {
            for app in fastList {
                let size = AppUninstallerService.appSizeBytes(for: app)
                let used = AppUninstallerService.lastUsedDate(for: app.bundlePath)
                await MainActor.run {
                    guard let index = self.apps.firstIndex(where: { $0.id == app.id }) else { return }
                    self.apps[index].appSizeBytes = size
                    self.apps[index].lastUsedDate = used
                    if self.selectedApp?.id == app.id {
                        self.selectedApp?.appSizeBytes = size
                        self.selectedApp?.lastUsedDate = used
                    }
                }
            }
        }
    }

    func scanLeftovers(for app: InstalledApp) {
        Task {
            let leftovers = AppUninstallerService.findLeftovers(for: app)
            await MainActor.run {
                if let index = self.apps.firstIndex(where: { $0.id == app.id }) {
                    self.apps[index].leftovers = leftovers
                }
                if self.selectedApp?.id == app.id {
                    self.selectedApp?.leftovers = leftovers
                }
                self.leftoversLoadedIDs.insert(app.id)
            }
        }
    }

    @Published var isUninstalling = false
    @Published var lastResult: AppUninstallerService.UninstallResult?

    @Published var didUndo = false

    /// Restores the last single-app uninstall from the Trash, then reloads the app list so the
    /// recovered app reappears. A real undo — moves every trashed item back where it belongs.
    func undoLastUninstall() {
        guard let result = lastResult, !result.restorePairs.isEmpty else { return }
        Task {
            let restored = await Task.detached(priority: .userInitiated) {
                AppUninstallerService.restore(result.restorePairs)
            }.value
            await MainActor.run {
                if restored > 0 {
                    self.didUndo = true
                    self.lastResult = nil
                    self.loadApps()
                }
            }
        }
    }

    // Batch uninstall state
    @Published var isBatchUninstalling = false
    @Published var batchProgress = 0
    @Published var batchTotal = 0
    @Published var batchResult: BatchUninstallResult?

    struct BatchUninstallResult {
        let appCount: Int
        let trashedItems: Int
        let freedBytes: Int64
        let adminItems: Int
        let restorePairs: [AppUninstallerService.RestorePair]
    }

    /// Undoes an entire batch uninstall — restores every trashed item across all removed apps
    /// back to its original location, then reloads the list so the apps reappear.
    func undoBatch() {
        guard let batch = batchResult, !batch.restorePairs.isEmpty else { return }
        Task {
            let restored = await Task.detached(priority: .userInitiated) {
                AppUninstallerService.restore(batch.restorePairs)
            }.value
            await MainActor.run {
                if restored > 0 {
                    self.batchResult = nil
                    self.loadApps()
                }
            }
        }
    }

    /// Uninstalls several apps in one confirmed action. Each app's own leftovers are found on
    /// the fly (user-domain only — system items need admin and are counted, not auto-removed),
    /// then app + leftovers go to Trash. Results are summed into one banner.
    func batchUninstall(_ appsToRemove: [InstalledApp]) {
        guard !appsToRemove.isEmpty else { return }
        isBatchUninstalling = true
        batchProgress = 0
        batchTotal = appsToRemove.count
        batchResult = nil
        Task {
            var trashed = 0
            var freed: Int64 = 0
            var admin = 0
            var removedIDs: [String] = []
            var pairs: [AppUninstallerService.RestorePair] = []
            for app in appsToRemove {
                let outcome = await Task.detached(priority: .userInitiated) { () -> (AppUninstallerService.UninstallResult, Int) in
                    let all = AppUninstallerService.findLeftovers(for: app)
                    let adminCount = all.filter { $0.requiresAdmin }.count
                    let result = AppUninstallerService.uninstall(app: app, leftovers: all.filter { !$0.requiresAdmin })
                    return (result, adminCount)
                }.value
                trashed += outcome.0.trashedCount
                freed += outcome.0.freedBytes
                admin += outcome.1
                pairs.append(contentsOf: outcome.0.restorePairs)
                if !outcome.0.failed.contains(where: { $0.url.path == app.bundlePath }) {
                    removedIDs.append(app.id)
                }
                await MainActor.run { self.batchProgress += 1 }
            }
            await MainActor.run {
                self.apps.removeAll { removedIDs.contains($0.id) }
                if let sel = self.selectedApp, removedIDs.contains(sel.id) { self.selectedApp = nil }
                self.batchResult = BatchUninstallResult(appCount: removedIDs.count, trashedItems: trashed,
                                                        freedBytes: freed, adminItems: admin, restorePairs: pairs)
                self.isBatchUninstalling = false
            }
        }
    }

    /// Uninstalls the app + the given leftovers, then drops it from the list on success.
    func uninstall(_ app: InstalledApp, leftovers: [LeftoverItem]) {
        isUninstalling = true
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                AppUninstallerService.uninstall(app: app, leftovers: leftovers)
            }.value
            await MainActor.run {
                self.isUninstalling = false
                self.lastResult = result
                // The .app itself was removed unless it was among the failures.
                let appRemoved = !result.failed.contains { $0.url.path == app.bundlePath }
                if appRemoved {
                    self.apps.removeAll { $0.id == app.id }
                    if self.selectedApp?.id == app.id { self.selectedApp = nil }
                }
            }
        }
    }
}
