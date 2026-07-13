import Foundation

/// A lightweight, persisted summary of one scan — just enough to diff against the next
/// scan of the same root without re-storing the whole tree.
struct ScanSnapshot: Codable, Identifiable {
    var id: String { "\(rootPath)-\(scannedAt.timeIntervalSince1970)" }
    let rootPath: String
    let scannedAt: Date
    let totalBytes: Int64
    /// Top-level child name -> size, for a per-folder growth breakdown.
    let childSizes: [String: Int64]

    init(result: ScanResult) {
        self.rootPath = result.root.path
        self.scannedAt = result.scannedAt
        self.totalBytes = result.root.sizeBytes
        var sizes: [String: Int64] = [:]
        for child in result.root.children {
            sizes[child.name] = child.sizeBytes
        }
        self.childSizes = sizes
    }
}

struct SnapshotDelta: Identifiable {
    var id: String { name }
    let name: String
    let previousBytes: Int64
    let currentBytes: Int64

    var deltaBytes: Int64 { currentBytes - previousBytes }
}
