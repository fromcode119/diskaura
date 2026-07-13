import Foundation

/// Moves a set of items to the Trash and reports what was freed, plus the original→in-Trash
/// pairs so the caller can offer a real Undo. Shared by Cleanup and the Uninstaller so both
/// "clean/remove" actions behave identically: recoverable, measured, reversible.
enum TrashMover {
    struct Outcome {
        let movedCount: Int
        let freedBytes: Int64
        let restorePairs: [AppUninstallerService.RestorePair]
        let failedCount: Int
    }

    static func move(_ items: [(url: URL, sizeBytes: Int64)]) -> Outcome {
        let fm = FileManager.default
        var moved = 0
        var freed: Int64 = 0
        var pairs: [AppUninstallerService.RestorePair] = []
        var failed = 0
        for item in items {
            var resultURL: NSURL?
            do {
                try fm.trashItem(at: item.url, resultingItemURL: &resultURL)
                moved += 1
                freed += max(item.sizeBytes, 0)
                if let dest = resultURL as URL? {
                    pairs.append(AppUninstallerService.RestorePair(original: item.url, trashed: dest))
                }
            } catch {
                failed += 1
            }
        }
        return Outcome(movedCount: moved, freedBytes: freed, restorePairs: pairs, failedCount: failed)
    }
}
