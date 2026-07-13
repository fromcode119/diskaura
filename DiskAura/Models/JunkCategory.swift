import Foundation

struct JunkItem: Identifiable {
    var id: String { url.path }
    let url: URL
    let sizeBytes: Int64
    /// Display name — the top-level entry name (e.g. an app's cache folder).
    var name: String { url.lastPathComponent }
}

/// One cleanable category (User caches, Logs, Trash, Xcode junk, …). `safe` categories are
/// pre-checked; anything with real reinstall/regeneration cost is left unchecked so the
/// user opts in deliberately.
struct JunkCategory: Identifiable {
    let id: String
    let title: String
    let icon: String
    let explanation: String
    let items: [JunkItem]
    let recommended: Bool

    var totalBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }
    var isEmpty: Bool { items.isEmpty }
}
