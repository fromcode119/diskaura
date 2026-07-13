import Foundation

@MainActor
final class LoginItemsViewModel: ObservableObject {
    @Published var items: [LaunchItem] = []
    @Published var isLoading = false
    @Published var isRemoving = false
    @Published var message: String?
    @Published var lastRestorePairs: [AppUninstallerService.RestorePair] = []

    func load() {
        isLoading = true
        Task.detached(priority: .userInitiated) {
            let found = LoginItemsService.list()
            await MainActor.run { self.items = found; self.isLoading = false }
        }
    }

    var userItems: [LaunchItem] { items.filter { $0.domain == .userAgent } }
    var systemItems: [LaunchItem] { items.filter { $0.domain == .systemAgent } }
    var daemonItems: [LaunchItem] { items.filter { $0.domain == .daemon } }
    var runAtLoadCount: Int { items.filter { $0.runAtLoad }.count }

    /// Removes the given items (moves their plists to Trash), then reloads. On failure (system
    /// items needing admin) reports how many couldn't be removed automatically.
    func remove(_ toRemove: [LaunchItem]) {
        guard !toRemove.isEmpty else { return }
        isRemoving = true
        message = nil
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                LoginItemsService.remove(toRemove)
            }.value
            await MainActor.run {
                self.isRemoving = false
                self.items = LoginItemsService.list()
                self.lastRestorePairs = result.restorePairs
                if result.failed > 0 && result.removed == 0 {
                    self.message = "These are system items — remove them from Terminal with admin rights (sudo)."
                } else if result.removed > 0 {
                    self.message = "Removed \(result.removed) startup item\(result.removed == 1 ? "" : "s")."
                    + (result.failed > 0 ? " \(result.failed) system item(s) need admin." : "")
                }
            }
        }
    }

    /// Toggle a user agent on/off at login (via launchctl) without deleting its plist.
    func toggle(_ item: LaunchItem) {
        Task {
            let ok = await Task.detached(priority: .userInitiated) {
                LoginItemsService.setEnabled(item, enabled: !item.enabled)
            }.value
            await MainActor.run {
                if ok {
                    self.items = LoginItemsService.list()
                    self.message = item.enabled ? "Disabled \(item.label) — won't start at next login." : "Enabled \(item.label)."
                    self.lastRestorePairs = []
                } else {
                    self.message = "Couldn't change \(item.label) — system items need admin (sudo launchctl)."
                }
            }
        }
    }

    /// Puts the last-removed startup items back where they were (from the Trash), then reloads.
    func undoLastRemove() {
        guard !lastRestorePairs.isEmpty else { return }
        let pairs = lastRestorePairs
        Task {
            let restored = await Task.detached(priority: .userInitiated) {
                AppUninstallerService.restore(pairs)
            }.value
            await MainActor.run {
                if restored > 0 {
                    self.lastRestorePairs = []
                    self.message = "Restored \(restored) startup item\(restored == 1 ? "" : "s")."
                    self.items = LoginItemsService.list()
                }
            }
        }
    }
}
