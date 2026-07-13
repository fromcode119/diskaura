import Foundation

/// One actionable result from a Smart Scan — a bucket of reclaimable space and the module that
/// handles it. The UI turns `tab` into a "Review" button that jumps there.
struct SmartFinding: Identifiable {
    let id: String
    let title: String
    let detail: String
    let bytes: Int64
    let icon: String
    let tab: SidebarTab
}

/// Smart Scan — a single tap that runs the cheap, safe analyzers across the app (system junk,
/// browser caches, Trash) and returns a combined, routed list of what can be reclaimed. It does
/// NOT delete anything; each finding links to the module that owns the cleanup.
enum SmartScanService {
    static func scan() async -> [SmartFinding] {
        async let junk = junkFinding()
        async let caches = browserCacheFinding()
        async let trash = trashFinding()
        return await [junk, caches, trash].compactMap { $0 }
            .sorted { $0.bytes > $1.bytes }
    }

    private static func junkFinding() async -> SmartFinding? {
        await Task.detached(priority: .utility) {
            let bytes = JunkScanner.scan().reduce(Int64(0)) { $0 + $1.totalBytes }
            guard bytes > 0 else { return nil }
            return SmartFinding(id: "junk", title: "System junk",
                                detail: "Caches, logs and developer junk",
                                bytes: bytes, icon: "sparkles", tab: .cleanup)
        }.value
    }

    private static func browserCacheFinding() async -> SmartFinding? {
        await Task.detached(priority: .utility) {
            let bytes = PrivacyService.scan()
                .filter { $0.category == .caches }
                .reduce(Int64(0)) { $0 + $1.sizeBytes }
            guard bytes > 0 else { return nil }
            return SmartFinding(id: "browser", title: "Browser caches",
                                detail: "Cached pages and images from your browsers",
                                bytes: bytes, icon: "hand.raised.fill", tab: .privacy)
        }.value
    }

    private static func trashFinding() async -> SmartFinding? {
        await Task.detached(priority: .utility) {
            let bytes = TrashService.size()
            guard bytes > 0 else { return nil }
            let count = TrashService.itemCount()
            return SmartFinding(id: "trash", title: "Trash",
                                detail: "\(count) item\(count == 1 ? "" : "s") waiting to be emptied",
                                bytes: bytes, icon: "trash.fill", tab: .cleanup)
        }.value
    }
}
