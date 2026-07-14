import Foundation

enum VolumeInfoService {
    static func stats(for url: URL) -> VolumeStats? {
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]), let total = values.volumeTotalCapacity else {
            return nil
        }

        // Strict free (volumeAvailableCapacity) is the "real free" number Finder and `df` show —
        // it does NOT optimistically include space the system merely *might* reclaim. The Finder
        // "important usage" value can be larger (it counts purgeable), which is why one surface
        // reading it looks inconsistent next to another reading strict. We headline the strict
        // number everywhere and keep the difference as a purgeable hint.
        let strict = Int64(values.volumeAvailableCapacity ?? 0)
        let important = values.volumeAvailableCapacityForImportantUsage ?? strict
        let totalBytes = Int64(total)

        return VolumeStats(
            totalBytes: totalBytes,
            usedBytes: totalBytes - strict,
            freeBytes: strict,
            purgeableHint: max(0, important - strict)
        )
    }
}
