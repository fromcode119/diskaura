import Foundation

/// Watches the Applications folders while DiskAura is running and, the moment you drag an app to
/// the Trash in Finder, finds the caches / preferences / support files it leaves behind and nudges
/// you to clean them — Pearcleaner's "Sentinel" idea. Read-only and notification-driven: it never
/// deletes anything on its own, it just catches leftovers you'd otherwise never notice.
@MainActor
final class AppRemovalWatcher: ObservableObject {
    static let shared = AppRemovalWatcher()
    private init() {}

    /// Leftovers discovered from the most recent removal — surfaced so a UI can offer one-click
    /// cleanup, and so a notification tap has something to act on.
    @Published private(set) var orphanedName: String?
    @Published private(set) var orphanedLeftovers: [LeftoverItem] = []

    private var monitors: [DirectoryMonitor] = []
    private var known: [String: InstalledApp] = [:]     // bundlePath → app snapshot

    private var watchedDirs: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func start() {
        guard monitors.isEmpty else { return }
        refreshKnown()
        for dir in watchedDirs {
            if let monitor = DirectoryMonitor(url: dir, onChange: { [weak self] in
                Task { @MainActor in self?.handleChange() }
            }) {
                monitors.append(monitor)
            }
        }
    }

    private func refreshKnown() {
        known = Dictionary(AppUninstallerService.listInstalledApps().map { ($0.bundlePath, $0) },
                           uniquingKeysWith: { a, _ in a })
    }

    private func handleChange() {
        let previous = known
        let currentPaths = Set(AppUninstallerService.listInstalledApps().map { $0.bundlePath })
        let removed = previous.filter { !currentPaths.contains($0.key) }.map { $0.value }
        refreshKnown()
        guard let app = removed.first else { return }   // one at a time is the normal case

        Task.detached(priority: .utility) {
            let leftovers = AppUninstallerService.findLeftovers(for: app)
            guard !leftovers.isEmpty else { return }
            let total = leftovers.reduce(Int64(0)) { $0 + $1.sizeBytes }
            await MainActor.run {
                self.orphanedName = app.name
                self.orphanedLeftovers = leftovers
                NotificationService.postAppRemovedLeftovers(appName: app.name, count: leftovers.count, bytes: total)
            }
        }
    }

    /// Trashes the currently-surfaced orphaned leftovers (recoverable), and records an Undo.
    @discardableResult
    func cleanOrphanedLeftovers() -> Int {
        let items = orphanedLeftovers.map { ($0.url, $0.sizeBytes) }
        guard !items.isEmpty else { return 0 }
        let outcome = TrashMover.move(items)
        UndoHistoryStore.shared.recordTrash(
            title: "Cleaned \(outcome.movedCount) leftover\(outcome.movedCount == 1 ? "" : "s") from \(orphanedName ?? "a removed app")",
            restorePairs: outcome.restorePairs)
        orphanedLeftovers = []
        orphanedName = nil
        return outcome.movedCount
    }
}

/// Minimal directory-change watcher via a kqueue/DispatchSource vnode on the folder's descriptor.
/// Fires `onChange` on any add/remove/rename inside the directory.
final class DirectoryMonitor {
    private let source: DispatchSourceFileSystemObject
    private let descriptor: Int32

    init?(url: URL, onChange: @escaping () -> Void) {
        descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .delete, .rename], queue: .global())
        source.setEventHandler(handler: onChange)
        source.setCancelHandler { [descriptor] in close(descriptor) }
        source.resume()
    }

    deinit { source.cancel() }
}
