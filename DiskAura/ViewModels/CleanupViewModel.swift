import Foundation

@MainActor
final class CleanupViewModel: ObservableObject {
    @Published var categories: [JunkCategory] = []
    @Published var isScanning = false
    @Published var hasScanned = false
    /// Category ids the user has selected to clean (recommended ones start selected).
    @Published var selectedCategoryIDs: Set<String> = []
    /// Individual item paths the user unticked inside an expanded category — everything in a
    /// selected category is cleaned EXCEPT these, so you can keep one file and clean the rest.
    @Published var excludedItemPaths: Set<String> = []

    private final class CancelFlag: @unchecked Sendable { var cancelled = false }
    private var cancelFlag = CancelFlag()

    func isItemExcluded(_ url: URL) -> Bool { excludedItemPaths.contains(url.path) }

    func toggleItem(_ url: URL) {
        if excludedItemPaths.contains(url.path) { excludedItemPaths.remove(url.path) }
        else { excludedItemPaths.insert(url.path) }
    }

    /// Items in a category that are actually going to be cleaned (respecting per-item unticks).
    func includedItems(in category: JunkCategory) -> [JunkItem] {
        category.items.filter { !excludedItemPaths.contains($0.url.path) }
    }

    private func includedBytes(in category: JunkCategory) -> Int64 {
        includedItems(in: category).reduce(0) { $0 + $1.sizeBytes }
    }

    var selectedBytes: Int64 {
        categories.filter { selectedCategoryIDs.contains($0.id) }.reduce(0) { $0 + includedBytes(in: $1) }
    }

    var totalBytes: Int64 { categories.reduce(0) { $0 + $1.totalBytes } }

    // APFS Time Machine local snapshots — surfaced because they pin "purgeable" space and are
    // the usual reason deleting files doesn't free space.
    @Published var snapshots: [TMSnapshot] = []
    @Published var isDeletingSnapshots = false
    @Published var snapshotMessage: String?

    func scan() {
        isScanning = true
        let flag = CancelFlag()
        cancelFlag = flag
        let matcher = ExclusionStore().matcher()
        Task.detached(priority: .userInitiated) {
            let result = JunkScanner.scan(exclusions: matcher, isCancelled: { flag.cancelled })
            let snaps = TimeMachineSnapshotService.list()
            await MainActor.run { [weak self] in
                guard let self, !flag.cancelled else { return }
                self.categories = result
                self.selectedCategoryIDs = Set(result.filter { $0.recommended }.map { $0.id })
                self.excludedItemPaths.removeAll()
                self.snapshots = snaps
                self.isScanning = false
                self.hasScanned = true
            }
        }
    }

    func deleteSnapshots() {
        guard !snapshots.isEmpty else { return }
        isDeletingSnapshots = true
        snapshotMessage = nil
        let snaps = snapshots
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                TimeMachineSnapshotService.delete(snaps)
            }.value
            await MainActor.run {
                self.isDeletingSnapshots = false
                self.snapshots = TimeMachineSnapshotService.list()
                if result.needsPrivileges {
                    self.snapshotMessage = "macOS needs elevated rights to remove these. In Terminal: sudo tmutil deletelocalsnapshots /"
                } else if result.deleted > 0 {
                    self.snapshotMessage = "Removed \(result.deleted) local snapshot\(result.deleted == 1 ? "" : "s")."
                } else if result.failed > 0 {
                    self.snapshotMessage = "Couldn't remove the snapshots automatically."
                }
            }
        }
    }

    func cancel() {
        cancelFlag.cancelled = true
        isScanning = false
    }

    func toggle(_ id: String) {
        if selectedCategoryIDs.contains(id) { selectedCategoryIDs.remove(id) }
        else { selectedCategoryIDs.insert(id) }
    }

    @Published var isCleaning = false
    @Published var lastCleanResult: CleanResult?

    struct CleanResult {
        let movedCount: Int
        let freedBytes: Int64
        let emptiedTrash: Bool
        let restorePairs: [AppUninstallerService.RestorePair]
    }

    /// Actually cleans the selected categories NOW — moves their items to the Trash
    /// (recoverable) and, if the Trash category is selected, empties it. Immediate real
    /// behavior beats "queued but nothing visibly happened"; recorded so we can offer Undo.
    func clean() {
        let selected = categories.filter { selectedCategoryIDs.contains($0.id) }
        guard !selected.isEmpty else { return }
        let emptyTrash = selected.contains { $0.id == "trash" }
        // Final safety gate: every item is re-checked right before trashing. Anything not
        // strictly inside the user's home (or that resolves into /System, /Library, …) is
        // dropped — Cleanup can never remove a macOS system file, by construction.
        let items: [(url: URL, sizeBytes: Int64)] = selected
            .filter { $0.id != "trash" }
            .flatMap { includedItems(in: $0) }
            .filter { CleanupSafety.isSafeToClean($0.url) }
            .map { ($0.url, $0.sizeBytes) }

        isCleaning = true
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> TrashMover.Outcome in
                let o = TrashMover.move(items)
                if emptyTrash { TrashService.empty() }
                return o
            }.value
            await MainActor.run {
                self.isCleaning = false
                self.lastCleanResult = CleanResult(movedCount: outcome.movedCount, freedBytes: outcome.freedBytes,
                                                   emptiedTrash: emptyTrash, restorePairs: outcome.restorePairs)
                UndoHistoryStore.shared.recordTrash(
                    title: "Cleaned \(outcome.movedCount) item\(outcome.movedCount == 1 ? "" : "s") (\(outcome.freedBytes.formattedBytes))",
                    restorePairs: outcome.restorePairs)
                self.scan()   // now correct: cleaned items really are gone
            }
        }
    }

    /// Restores the last cleanup from the Trash (emptied-Trash items can't come back).
    func undoLastClean() {
        guard let result = lastCleanResult, !result.restorePairs.isEmpty else { return }
        Task {
            let restored = await Task.detached(priority: .userInitiated) {
                AppUninstallerService.restore(result.restorePairs)
            }.value
            await MainActor.run {
                if restored > 0 { self.lastCleanResult = nil; self.scan() }
            }
        }
    }
}
