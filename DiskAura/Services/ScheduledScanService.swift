import Foundation

/// Periodically re-scans the last-scanned root in the background so the history/diff
/// view has something to compare against without the user remembering to re-scan manually.
@MainActor
final class ScheduledScanService: ObservableObject {
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
    }
    @Published var intervalHours: Double {
        didSet { UserDefaults.standard.set(intervalHours, forKey: Self.intervalKey) }
    }
    /// When on, each scheduled tick also moves the safe, recommended junk (caches, logs, crash
    /// reports) to the Trash — recoverable, never emptied automatically, and logged in Recovery.
    @Published var autoCleanEnabled: Bool {
        didSet { UserDefaults.standard.set(autoCleanEnabled, forKey: Self.autoCleanKey) }
    }
    @Published var lastAutoCleanSummary: String?

    private static let enabledKey = "com.kristian.diskaura.scheduledScanEnabled"
    private static let intervalKey = "com.kristian.diskaura.scheduledScanIntervalHours"
    private static let autoCleanKey = "com.kristian.diskaura.scheduledAutoClean"

    private var timer: Timer?
    private weak var scanVM: ScanViewModel?

    init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        let savedInterval = UserDefaults.standard.double(forKey: Self.intervalKey)
        self.intervalHours = savedInterval > 0 ? savedInterval : 6
        self.autoCleanEnabled = UserDefaults.standard.bool(forKey: Self.autoCleanKey)
    }

    func attach(to scanVM: ScanViewModel) {
        self.scanVM = scanVM
        reschedule()
    }

    func reschedule() {
        timer?.invalidate()
        timer = nil
        guard isEnabled else { return }

        timer = Timer.scheduledTimer(withTimeInterval: intervalHours * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.fireScheduledScan() }
        }
    }

    private func fireScheduledScan() {
        if let scanVM, let lastRoot = scanVM.result?.root.url {
            scanVM.scan(url: lastRoot)
        }
        if autoCleanEnabled { autoClean() }
    }

    /// Runs the app's own automatic maintenance NOW (also used by the "Run now" button). Moves
    /// only the recommended, self-regenerating junk to the Trash — never empties it, never touches
    /// risky categories, and every item passes the `CleanupSafety` guard. Recorded in Recovery.
    func runAutoCleanNow() { autoClean() }

    private func autoClean() {
        let matcher = ExclusionStore().matcher()
        Task.detached(priority: .background) {
            let categories = JunkScanner.scan(exclusions: matcher)
                .filter { $0.recommended && $0.id != "trash" }   // never auto-empty the Trash
            let items: [(url: URL, sizeBytes: Int64)] = categories
                .flatMap { $0.items }
                .filter { CleanupSafety.isSafeToClean($0.url) }
                .map { ($0.url, $0.sizeBytes) }
            guard !items.isEmpty else { return }
            let outcome = TrashMover.move(items)
            await MainActor.run {
                UndoHistoryStore.shared.recordTrash(
                    title: "Auto-clean: \(outcome.movedCount) item\(outcome.movedCount == 1 ? "" : "s") (\(outcome.freedBytes.formattedBytes))",
                    restorePairs: outcome.restorePairs)
                self.lastAutoCleanSummary = "Moved \(outcome.freedBytes.formattedBytes) of junk to Trash on \(Date().formatted(date: .abbreviated, time: .shortened))"
                NotificationService.postAutoClean(freedBytes: outcome.freedBytes, count: outcome.movedCount)
            }
        }
    }
}
