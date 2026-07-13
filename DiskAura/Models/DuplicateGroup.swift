import Foundation

/// How the app suggests which copy to keep when auto-selecting a group. The user always
/// overrides per-tile; this is just the smart default so one click cleans a whole group.
enum DuplicateKeepStrategy: String, CaseIterable, Identifiable {
    case smart = "Smart"
    case newest = "Newest"
    case oldest = "Oldest"
    case first = "First"
    var id: String { rawValue }
}

struct DuplicateFile: Identifiable {
    var id: String { url.path }
    let url: URL
    let sizeBytes: Int64
    var modifiedAt: Date? = nil
}

struct DuplicateGroup: Identifiable {
    let id = UUID()
    let files: [DuplicateFile]

    var sizeBytes: Int64 { files.first?.sizeBytes ?? 0 }
    /// Space reclaimable by keeping exactly one copy.
    var reclaimableBytes: Int64 { sizeBytes * Int64(files.count - 1) }

    /// The copy the app suggests keeping under a given strategy. "Smart" ranks copies
    /// lexicographically: a copy in a real/organized location beats one in a junk location
    /// (Downloads/Desktop/Trash/Caches/tmp/temp), then newer beats older, then a shallower
    /// (tidier) path wins the tie. A single weighted float score was fragile — small date
    /// deltas got swamped by path depth — so this compares field-by-field instead.
    func keeper(_ strategy: DuplicateKeepStrategy) -> DuplicateFile? {
        switch strategy {
        case .first: return files.first
        case .newest: return files.max { ($0.modifiedAt ?? .distantPast) < ($1.modifiedAt ?? .distantPast) }
        case .oldest: return files.min { ($0.modifiedAt ?? .distantFuture) < ($1.modifiedAt ?? .distantFuture) }
        case .smart:
            return files.sorted(by: Self.smartRank).first
        }
    }

    private static func isJunkLocation(_ url: URL) -> Bool {
        let p = url.path.lowercased()
        return ["/downloads/", "/desktop/", "/.trash/", "/caches/", "/tmp/", "/temp/", "/library/caches"]
            .contains { p.contains($0) }
    }

    /// True if `a` should be kept over `b`.
    private static func smartRank(_ a: DuplicateFile, _ b: DuplicateFile) -> Bool {
        let ja = isJunkLocation(a.url), jb = isJunkLocation(b.url)
        if ja != jb { return !ja }                       // non-junk location wins
        let da = a.modifiedAt ?? .distantPast, db = b.modifiedAt ?? .distantPast
        if da != db { return da > db }                   // newer wins
        return a.url.pathComponents.count < b.url.pathComponents.count // shallower wins
    }
}
