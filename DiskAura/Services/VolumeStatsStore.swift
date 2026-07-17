import Foundation

/// The single source of truth for volume free-space across the whole app. Polls periodically and
/// is force-refreshed by every destructive action, so no two surfaces (menu bar, Smart Scan hero,
/// Scan dashboard) can ever disagree or go stale. Reads the strict "real free" number.
@MainActor
final class VolumeStatsStore: ObservableObject {
    static let shared = VolumeStatsStore()

    @Published private(set) var stats: VolumeStats?

    private var timer: Timer?
    private let url = FileManager.default.homeDirectoryForCurrentUser

    private init() { refresh() }

    func startPolling(interval: TimeInterval = 10) {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stopPolling() { timer?.invalidate(); timer = nil }

    /// Force an immediate re-read — call right after any action that changes disk usage
    /// (cleanup, empty-trash, privacy clear, shredder) so the displayed free space moves at once.
    func refresh() { stats = VolumeInfoService.stats(for: url) }
}
