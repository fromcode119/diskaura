import Foundation

enum NodeTag: String, Codable, CaseIterable, Identifiable {
    case keep
    case clean
    case archive
    case system

    var id: String { rawValue }

    var label: String {
        switch self {
        case .keep: return "Keep"
        case .clean: return "Clearable"
        case .archive: return "Archive"
        case .system: return "System"
        }
    }
}

/// Plain class, NOT `ObservableObject` — a full scan of a large home folder creates
/// 500,000+ of these. `ObservableObject` + 3x `@Published` allocates Combine publisher
/// machinery on EVERY instance regardless of whether anything observes it, which is what
/// pushed RAM to 2-3GB+ on a full home-folder scan (confirmed: the only place that ever
/// bound a `FileNode` as `@ObservedObject` was the handful of currently-expanded rows in
/// `FolderBreakdownView`, not the whole tree). Mutation-triggered UI refresh for the rare
/// user re-tag action is handled by a local `@State` bump in `FolderRow` instead.
final class FileNode: Identifiable {
    let url: URL
    let isDirectory: Bool
    var sizeBytes: Int64
    var tag: NodeTag
    var children: [FileNode]
    let ruleMatched: String?
    let modifiedAt: Date?

    init(
        url: URL,
        isDirectory: Bool,
        sizeBytes: Int64 = 0,
        tag: NodeTag = .keep,
        children: [FileNode] = [],
        ruleMatched: String? = nil,
        modifiedAt: Date? = nil
    ) {
        self.url = url
        self.isDirectory = isDirectory
        self.sizeBytes = sizeBytes
        self.tag = tag
        self.children = children
        self.ruleMatched = ruleMatched
        self.modifiedAt = modifiedAt
    }

    /// Flattens this subtree into every regular file (not directories), for cross-tree
    /// views like "largest files" / "oldest files" that ignore the folder hierarchy.
    func flattenFiles() -> [FileNode] {
        if !isDirectory { return [self] }
        return children.flatMap { $0.flattenFiles() }
    }

    /// Collects every node (files AND directories) in this subtree whose path is in `paths` —
    /// resolves a multi-select set (kept as opaque path strings in the view) back into the
    /// actual nodes to move or delete. A selected directory short-circuits its own subtree.
    func nodes(matching paths: Set<String>) -> [FileNode] {
        guard !paths.isEmpty else { return [] }
        if paths.contains(path) { return [self] }
        var result: [FileNode] = []
        for child in children { result.append(contentsOf: child.nodes(matching: paths)) }
        return result
    }

    // `id`/`name`/`path` used to be separate stored `String` properties, each a second
    // heap allocation duplicating what `url` already holds. On a 500,000+ node home-folder
    // scan that tripled the string-allocation count for no reason — computed here instead;
    // Foundation caches `URL`'s own parsed components so this isn't a re-parse per access.
    var id: String { url.path }
    var name: String { url.lastPathComponent }
    var path: String { url.path }

    var sortedChildren: [FileNode] {
        children.sorted { $0.sizeBytes > $1.sizeBytes }
    }
}

extension Int64 {
    /// Decimal (1000-based) — matches Finder/Disk Utility convention for disk space.
    var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }

    /// Binary (1024-based) — matches Activity Monitor's convention for RAM. Using the
    /// decimal formatter for memory reported 48 GiB of real RAM as "51.5 GB", which read
    /// as a fabricated/wrong number even though the byte count itself was correct.
    var formattedMemoryBytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .memory)
    }
}
