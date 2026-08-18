import Foundation

@MainActor
final class CleanupViewModel: ObservableObject {
    /// Scan data is shared with Smart Scan via this store, so navigating between them never
    /// triggers a duplicate scan. This view model owns only the SELECTION and the clean action.
    private let store = JunkScanStore.shared

    /// Category ids the user has selected to clean (recommended ones start selected).
    @Published var selectedCategoryIDs: Set<String> = []
    /// Individual item paths the user unticked inside an expanded category.
    @Published var excludedItemPaths: Set<String> = []
    @Published var isCleaning = false
    @Published var lastCleanResult: CleanResult?
    @Published var isDeletingSnapshots = false
    @Published var snapshotMessage: String?
    /// Real outcome of an Empty Trash attempt — success detail and failure reason are both shown
    /// rather than assuming it worked.
    @Published var trashMessage: String?
    @Published var trashError: String?
    @Published var isEmptyingTrash = false
    /// What's waiting in the Trash — cleaning only MOVES files there (a same-volume rename frees
    /// zero bytes), so this is the amount still to be reclaimed by emptying it.
    @Published private(set) var pendingTrashBytes: Int64 = 0
    @Published private(set) var pendingTrashCount: Int = 0
    private var didInitSelection = false

    // Data mirrored from the shared store (the View also observes the store so it re-renders).
    var categories: [JunkCategory] { store.categories }
    var snapshots: [TMSnapshot] { store.snapshots }
    var hasScanned: Bool { store.hasScanned }
    var isScanning: Bool { store.isScanning }

    func isItemExcluded(_ url: URL) -> Bool { excludedItemPaths.contains(url.path) }

    func toggleItem(_ url: URL) {
        if excludedItemPaths.contains(url.path) { excludedItemPaths.remove(url.path) }
        else { excludedItemPaths.insert(url.path) }
    }

    func includedItems(in category: JunkCategory) -> [JunkItem] {
        category.items.filter { !excludedItemPaths.contains($0.url.path) }
    }

    private func includedBytes(in category: JunkCategory) -> Int64 {
        includedItems(in: category).reduce(0) { $0 + $1.sizeBytes }
    }

    var selectedBytes: Int64 {
        categories.filter { selectedCategoryIDs.contains($0.id) }.reduce(0) { $0 + includedBytes(in: $1) }
    }
    var totalBytes: Int64 { store.totalBytes }

    /// Called on appear / when the store's categories change — picks the default (recommended)
    /// selection once, without wiping the user's subsequent choices.
    func applyDefaultSelection() {
        guard !didInitSelection, !categories.isEmpty else { return }
        selectedCategoryIDs = Set(categories.filter { $0.recommended }.map { $0.id })
        didInitSelection = true
    }

    /// Force a fresh scan (the Rescan button). Normal navigation reuses the shared result.
    func scan() {
        didInitSelection = false
        excludedItemPaths.removeAll()
        Task { await store.scan(); applyDefaultSelection() }
    }

    func cancel() { store.cancel() }

    func toggle(_ id: String) {
        if selectedCategoryIDs.contains(id) { selectedCategoryIDs.remove(id) }
        else { selectedCategoryIDs.insert(id) }
    }

    struct CleanResult {
        let movedCount: Int
        let freedBytes: Int64
        let emptiedTrash: Bool
        let restorePairs: [AppUninstallerService.RestorePair]
    }

    /// Cleans the selected categories NOW — moves items to the Trash and empties it if selected.
    /// Afterwards the cleaned items are dropped from the shared store optimistically, so the list
    /// just updates in place instead of kicking off a jarring full re-scan.
    func clean() {
        let selected = categories.filter { selectedCategoryIDs.contains($0.id) }
        guard !selected.isEmpty else { return }
        let emptyTrash = selected.contains { $0.id == "trash" }
        let items: [(url: URL, sizeBytes: Int64)] = selected
            .filter { $0.id != "trash" }
            .flatMap { includedItems(in: $0) }
            .filter { CleanupSafety.isSafeToClean($0.url) }
            .map { ($0.url, $0.sizeBytes) }

        isCleaning = true
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> (TrashMover.Outcome, String?) in
                let o = TrashMover.move(items)
                guard emptyTrash else { return (o, nil) }
                // Report a failed empty instead of silently reporting the Trash as emptied.
                do { _ = try TrashService.empty(); return (o, nil) }
                catch { return (o, error.localizedDescription) }
            }.value
            let outcome = result.0
            self.isCleaning = false
            if let failure = result.1 { self.trashError = failure }
            self.lastCleanResult = CleanResult(movedCount: outcome.movedCount, freedBytes: outcome.freedBytes,
                                               emptiedTrash: emptyTrash && result.1 == nil, restorePairs: outcome.restorePairs)
            UndoHistoryStore.shared.recordTrash(
                title: "Cleaned \(outcome.movedCount) item\(outcome.movedCount == 1 ? "" : "s") (\(outcome.freedBytes.formattedBytes))",
                restorePairs: outcome.restorePairs)
            // Optimistic update — no full re-scan.
            self.store.applyCleaned(itemPaths: Set(items.map { $0.url.path }), emptiedTrash: emptyTrash)
            self.selectedCategoryIDs = self.selectedCategoryIDs.filter { id in self.categories.contains { $0.id == id } }
            // Surface how much is now waiting in the Trash — moving files there frees nothing until
            // it's emptied, and that gap is what made cleaning look like it did nothing.
            self.refreshPendingTrash()
            VolumeStatsStore.shared.refresh()
        }
    }

    /// Empties the Trash so space cleaned into it is *physically* reclaimed, then refreshes the
    /// free-space number. This is the missing link between "I cleaned" and "I see more free space":
    /// cleanup moves to Trash (recoverable), so free space only rises once the Trash is emptied.
    func emptyTrashToReclaim() {
        isEmptyingTrash = true
        Task {
            defer { isEmptyingTrash = false }
            do {
                // Only claim it was emptied if it ACTUALLY was. A denied Apple Event used to be
                // swallowed here, so the UI reported success over a still-full Trash.
                let out = try await Task.detached(priority: .userInitiated) { try TrashService.empty() }.value
                if var r = self.lastCleanResult {
                    r = CleanResult(movedCount: r.movedCount, freedBytes: r.freedBytes,
                                    emptiedTrash: true, restorePairs: r.restorePairs)
                    self.lastCleanResult = r
                }
                self.trashMessage = Self.emptyOutcomeMessage(out)
            } catch {
                self.trashError = error.localizedDescription
            }
            self.refreshPendingTrash()
            VolumeStatsStore.shared.refresh()
        }
    }

    /// Reports the DISK figure, not the Trash figure — they differ when snapshots pin the blocks,
    /// which is the whole reason "I deleted 30GB and only got 2GB back" looked like a lie.
    static func emptyOutcomeMessage(_ out: TrashService.EmptyOutcome) -> String {
        if out.bytesRemovedFromTrash == 0 { return "The Trash was already empty." }
        if out.heldBySnapshots {
            return "Emptied \(out.bytesRemovedFromTrash.formattedBytes) from the Trash, but only "
                 + "\(out.bytesReclaimedOnDisk.formattedBytes) came back so far — Time Machine's local "
                 + "snapshots still hold the rest. macOS releases it automatically, usually within 24 hours."
        }
        return "Emptied the Trash — reclaimed \(out.bytesReclaimedOnDisk.formattedBytes) of disk space."
    }

    /// How much is sitting in the Trash right now: the bridge between "cleaned" and "actually freed".
    func refreshPendingTrash() {
        Task.detached(priority: .utility) {
            let bytes = TrashService.size()
            let count = TrashService.itemCount()
            await MainActor.run { self.pendingTrashBytes = bytes; self.pendingTrashCount = count }
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
            self.isDeletingSnapshots = false
            self.store.setSnapshots(TimeMachineSnapshotService.list())
            if result.needsPrivileges {
                self.snapshotMessage = "macOS needs elevated rights to remove these. In Terminal: sudo tmutil deletelocalsnapshots /"
            } else if result.deleted > 0 {
                self.snapshotMessage = "Removed \(result.deleted) local snapshot\(result.deleted == 1 ? "" : "s")."
            } else if result.failed > 0 {
                self.snapshotMessage = "Couldn't remove the snapshots automatically."
            }
        }
    }

    /// Restores the last cleanup from the Trash (a rescan here is warranted since files reappear).
    func undoLastClean() {
        guard let result = lastCleanResult, !result.restorePairs.isEmpty else { return }
        Task {
            let restored = await Task.detached(priority: .userInitiated) {
                AppUninstallerService.restore(result.restorePairs)
            }.value
            if restored > 0 { self.lastCleanResult = nil; self.scan() }
        }
    }
}
