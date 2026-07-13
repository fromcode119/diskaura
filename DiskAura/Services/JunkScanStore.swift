import Foundation

/// One shared junk-scan result for the whole app. Smart Scan and Cleanup both read/write it, so
/// scanning in Smart Scan and then opening Cleanup shows the SAME result instantly — no second
/// scan. After a clean, items are removed optimistically instead of triggering a full re-scan.
@MainActor
final class JunkScanStore: ObservableObject {
    static let shared = JunkScanStore()
    private init() {}

    @Published private(set) var categories: [JunkCategory] = []
    @Published private(set) var snapshots: [TMSnapshot] = []
    @Published private(set) var hasScanned = false
    @Published private(set) var isScanning = false

    var totalBytes: Int64 { categories.reduce(0) { $0 + $1.totalBytes } }

    private final class CancelFlag: @unchecked Sendable { var cancelled = false }
    private var cancelFlag = CancelFlag()

    /// Runs a fresh junk scan and caches the result. Awaitable so Smart Scan can use the total
    /// while also populating the cache for Cleanup.
    @discardableResult
    func scan() async -> [JunkCategory] {
        guard !isScanning else { return categories }
        isScanning = true
        let flag = CancelFlag()
        cancelFlag = flag
        let matcher = ExclusionStore().matcher()
        let result = await Task.detached(priority: .userInitiated) {
            JunkScanner.scan(exclusions: matcher, isCancelled: { flag.cancelled })
        }.value
        let snaps = await Task.detached(priority: .userInitiated) { TimeMachineSnapshotService.list() }.value
        guard !flag.cancelled else { isScanning = false; return categories }
        categories = result
        snapshots = snaps
        isScanning = false
        hasScanned = true
        return result
    }

    /// Scans only if we don't already have a result (so navigating to Cleanup after a Smart Scan
    /// reuses it, but a cold Cleanup still scans once).
    func scanIfNeeded() {
        guard !hasScanned, !isScanning else { return }
        Task { await scan() }
    }

    func cancel() {
        cancelFlag.cancelled = true
        isScanning = false
    }

    /// Optimistically drop the items that were just cleaned (and the Trash category if emptied),
    /// so the list updates immediately without a jarring full re-scan.
    func applyCleaned(itemPaths: Set<String>, emptiedTrash: Bool) {
        categories = categories.compactMap { cat in
            if emptiedTrash && cat.id == "trash" { return nil }
            let remaining = cat.items.filter { !itemPaths.contains($0.url.path) }
            if remaining.isEmpty { return nil }
            if remaining.count == cat.items.count { return cat }
            return JunkCategory(id: cat.id, title: cat.title, icon: cat.icon,
                                explanation: cat.explanation, items: remaining, recommended: cat.recommended)
        }
    }

    func setSnapshots(_ snaps: [TMSnapshot]) { snapshots = snaps }
}
