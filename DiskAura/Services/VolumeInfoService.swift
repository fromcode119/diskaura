import Foundation

enum VolumeInfoService {
    static func stats(for url: URL) -> VolumeStats? {
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]) else {
            return nil
        }

        guard let total = values.volumeTotalCapacity else { return nil }
        let available = values.volumeAvailableCapacityForImportantUsage ?? 0

        let totalBytes = Int64(total)
        let freeBytes = available
        let usedBytes = totalBytes - freeBytes

        return VolumeStats(totalBytes: totalBytes, usedBytes: usedBytes, freeBytes: freeBytes)
    }
}
