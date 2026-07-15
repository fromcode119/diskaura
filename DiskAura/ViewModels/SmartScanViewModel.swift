import Foundation

/// Drives Smart Scan: live disk/memory/trash stats for the dashboard hero, plus the aggregated
/// reclaimable findings once a scan runs.
@MainActor
final class SmartScanViewModel: ObservableObject {
    @Published private(set) var findings: [SmartFinding] = []
    @Published private(set) var scanning = false
    @Published private(set) var hasScanned = false

    // Live stats for the hero ring + circular mini-stats.
    @Published private(set) var diskTotal: Int64 = 0
    @Published private(set) var diskUsed: Int64 = 0
    @Published private(set) var diskFree: Int64 = 0
    @Published private(set) var memUsedBytes: Int64 = 0
    @Published private(set) var memUsedFraction: Double = 0
    @Published private(set) var trashBytes: Int64 = 0

    var reclaimableBytes: Int64 { findings.reduce(0) { $0 + $1.bytes } }
    var diskUsedFraction: Double { diskTotal > 0 ? Double(diskUsed) / Double(diskTotal) : 0 }

    /// Empties the Trash and refreshes stats — space cleaned into the Trash isn't reclaimed on disk
    /// until it's emptied, so this is how the free-space number actually moves.
    func emptyTrash() {
        Task {
            await Task.detached(priority: .userInitiated) { TrashService.empty() }.value
            VolumeStatsStore.shared.refresh()
            loadStats()
        }
    }

    func loadStats() {
        // Read from the shared live store (force a fresh read first) so this never shows a stale
        // number when the keep-alive tab is revisited.
        let store = VolumeStatsStore.shared
        store.refresh()
        if let s = store.stats {
            diskTotal = s.totalBytes; diskUsed = s.usedBytes; diskFree = s.freeBytes
        }
        let m = SystemStatsService.memory()
        memUsedBytes = m.usedBytes
        memUsedFraction = m.usedFraction
        Task.detached(priority: .utility) {
            let t = TrashService.size()
            await MainActor.run { self.trashBytes = t }
        }
    }

    func scan() {
        guard !scanning else { return }
        scanning = true
        Task {
            // Guard against any single analyzer hanging (a pathological cache dir, tmutil stall):
            // race the scan against a timeout so `scanning` can never wedge on forever.
            let results = await Self.withTimeout(seconds: 90) { await SmartScanService.scan() } ?? []
            findings = results
            scanning = false
            hasScanned = true
            loadStats()
        }
    }

    /// Runs `work`, returning nil if it doesn't finish within `seconds`.
    private static func withTimeout<T: Sendable>(seconds: Double, _ work: @escaping @Sendable () async -> T) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await work() }
            group.addTask { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
