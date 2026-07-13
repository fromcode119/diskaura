import Foundation

/// Persists scan snapshots to disk (one JSON file per root path is overkill for v1 —
/// a single JSON array, capped per root, is plenty for the diff view).
final class ScanHistoryStore: ObservableObject {
    @Published private(set) var snapshots: [ScanSnapshot]

    private static let maxPerRoot = 20
    private static let fileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("DiskAura", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("scan-history.json")
    }()

    init() {
        self.snapshots = Self.load()
    }

    func record(_ result: ScanResult) {
        let snapshot = ScanSnapshot(result: result)
        var updated = snapshots
        updated.append(snapshot)

        // Cap how many snapshots we keep per root so this file doesn't grow forever.
        let forRoot = updated.filter { $0.rootPath == snapshot.rootPath }
        if forRoot.count > Self.maxPerRoot {
            let toDrop = forRoot.sorted { $0.scannedAt < $1.scannedAt }.prefix(forRoot.count - Self.maxPerRoot)
            let dropIDs = Set(toDrop.map(\.id))
            updated.removeAll { dropIDs.contains($0.id) }
        }

        snapshots = updated
        persist()
    }

    /// Most recent snapshot for a root, if any.
    func latest(for rootPath: String) -> ScanSnapshot? {
        snapshots
            .filter { $0.rootPath == rootPath }
            .max { $0.scannedAt < $1.scannedAt }
    }

    /// Last two snapshots for a root, oldest first — nil if there's no prior snapshot to diff against.
    func lastTwo(for rootPath: String) -> (previous: ScanSnapshot, current: ScanSnapshot)? {
        let matching = snapshots
            .filter { $0.rootPath == rootPath }
            .sorted { $0.scannedAt < $1.scannedAt }
        guard matching.count >= 2 else { return nil }
        return (matching[matching.count - 2], matching[matching.count - 1])
    }

    func deltas(for rootPath: String) -> [SnapshotDelta] {
        guard let pair = lastTwo(for: rootPath) else { return [] }
        let allNames = Set(pair.previous.childSizes.keys).union(pair.current.childSizes.keys)
        return allNames
            .map { name in
                SnapshotDelta(
                    name: name,
                    previousBytes: pair.previous.childSizes[name] ?? 0,
                    currentBytes: pair.current.childSizes[name] ?? 0
                )
            }
            .filter { $0.deltaBytes != 0 }
            .sorted { abs($0.deltaBytes) > abs($1.deltaBytes) }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        try? data.write(to: Self.fileURL)
    }

    private static func load() -> [ScanSnapshot] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([ScanSnapshot].self, from: data) else {
            return []
        }
        return decoded
    }
}
