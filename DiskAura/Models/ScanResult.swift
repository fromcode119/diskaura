import Foundation

struct VolumeStats {
    let totalBytes: Int64
    let usedBytes: Int64
    let freeBytes: Int64
}

struct ScanResult {
    let root: FileNode
    let scannedAt: Date
    let volume: VolumeStats?
    let skippedPaths: [String]
    let deniedPaths: [String]
}
