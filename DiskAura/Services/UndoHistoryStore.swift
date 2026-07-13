import Foundation

/// A single reversible action the user took — the data needed to put every file back where it
/// was. Reverting moves each `source` back to its `dest`.
struct UndoEntry: Identifiable {
    let id = UUID()
    let title: String
    let date: Date
    let pairs: [RevertPair]
    var count: Int { pairs.count }

    struct RevertPair {
        let source: URL   // where the file is now
        let dest: URL     // where it should go back to
    }
}

/// A visible, session-wide history of everything DiskAura moved, organized, or cleaned — each with
/// a one-click Revert. This is the "trust" feature: nothing we do is a one-way door. Cleanups go to
/// the Trash (revert = restore from Trash); moves/organizes revert by moving files back to their
/// original location.
@MainActor
final class UndoHistoryStore: ObservableObject {
    static let shared = UndoHistoryStore()
    private init() {}

    @Published private(set) var entries: [UndoEntry] = []

    /// Records a move/organize as reversible. `movedPairs` is (originalLocation, newLocation);
    /// reverting moves the file from newLocation back to originalLocation.
    func recordMoves(title: String, movedPairs: [(from: URL, to: URL)]) {
        guard !movedPairs.isEmpty else { return }
        let pairs = movedPairs.map { UndoEntry.RevertPair(source: $0.to, dest: $0.from) }
        entries.insert(UndoEntry(title: title, date: Date(), pairs: pairs), at: 0)
    }

    /// Records a cleanup as reversible. `restorePairs` is (trashedURL, originalURL) — reverting
    /// moves the item out of the Trash back to where it was.
    func recordTrash(title: String, restorePairs: [AppUninstallerService.RestorePair]) {
        guard !restorePairs.isEmpty else { return }
        let pairs = restorePairs.map { UndoEntry.RevertPair(source: $0.trashed, dest: $0.original) }
        entries.insert(UndoEntry(title: title, date: Date(), pairs: pairs), at: 0)
    }

    struct RevertResult { let restored: Int; let failed: Int }

    /// Puts every file in an entry back. Returns how many succeeded, and drops the entry on any
    /// success so the UI reflects reality.
    @discardableResult
    func revert(_ entry: UndoEntry) -> RevertResult {
        let fm = FileManager.default
        var restored = 0, failed = 0
        var sourceParents: Set<URL> = []
        for pair in entry.pairs {
            guard fm.fileExists(atPath: pair.source.path) else { failed += 1; continue }
            do {
                try fm.createDirectory(at: pair.dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                let dest = uniqueDestination(pair.dest, fm: fm)
                try fm.moveItem(at: pair.source, to: dest)
                sourceParents.insert(pair.source.deletingLastPathComponent())
                restored += 1
            } catch { failed += 1 }
        }
        // Tidy up: remove folders the move/organize created that are now empty — so a revert leaves
        // no orphaned "Documents"/"Images" shells behind. Gated by CleanupSafety so we never touch a
        // protected or pre-existing important folder, and we walk up only while a level stays empty.
        for parent in sourceParents { removeIfEmptyUpwards(parent, fm: fm) }
        if restored > 0 { entries.removeAll { $0.id == entry.id } }
        return RevertResult(restored: restored, failed: failed)
    }

    private func removeIfEmptyUpwards(_ dir: URL, fm: FileManager) {
        var current = dir.standardizedFileURL
        while CleanupSafety.isSafeToClean(current),
              let contents = try? fm.contentsOfDirectory(atPath: current.path),
              contents.filter({ $0 != ".DS_Store" }).isEmpty {
            let parent = current.deletingLastPathComponent()
            try? fm.removeItem(at: current)
            current = parent.standardizedFileURL
        }
    }

    private func uniqueDestination(_ url: URL, fm: FileManager) -> URL {
        guard fm.fileExists(atPath: url.path) else { return url }
        let dir = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        var i = 1
        while true {
            let name = ext.isEmpty ? "\(base)-\(i)" : "\(base)-\(i).\(ext)"
            let candidate = dir.appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            i += 1
        }
    }
}
