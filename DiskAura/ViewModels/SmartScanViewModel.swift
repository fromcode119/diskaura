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

    func loadStats() {
        if let s = VolumeInfoService.stats(for: FileManager.default.homeDirectoryForCurrentUser) {
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
            let results = await SmartScanService.scan()
            findings = results
            scanning = false
            hasScanned = true
            loadStats()
        }
    }
}
