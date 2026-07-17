import Foundation

struct VolumeStats {
    let totalBytes: Int64
    let usedBytes: Int64
    let freeBytes: Int64        // strict free (volumeAvailableCapacity) — the headline "real free", matches Finder/df
    let purgeableHint: Int64    // max(0, importantUsage - strict): system-reclaimable estimate
}

struct ScanResult {
    let root: FileNode
    let scannedAt: Date
    let volume: VolumeStats?
    let skippedPaths: [String]
    let deniedPaths: [String]
}
