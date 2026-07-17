import Foundation
import SwiftUI

/// Polls volume free-space every 30s for the menu bar extra — a lightweight,
/// always-on presence CleanMyMac has and DaisyDisk/GrandPerspective/OmniDiskSweeper don't.
@MainActor
final class MenuBarVolumeMonitor: ObservableObject {
    @Published var stats: VolumeStats?

    private var timer: Timer?
    private var wasLow = false

    /// Below this fraction of free space, the menu bar icon switches to a warning state.
    static let lowSpaceThreshold: Double = 0.10

    var isLow: Bool {
        guard let stats, stats.totalBytes > 0 else { return false }
        return Double(stats.freeBytes) / Double(stats.totalBytes) < Self.lowSpaceThreshold
    }

    func start() {
        NotificationService.requestAuthorizationIfNeeded()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        // Read through the shared store so the menu bar and every in-app surface show one number.
        VolumeStatsStore.shared.refresh()
        stats = VolumeStatsStore.shared.stats

        // Edge-triggered: only fire once when crossing into "low", not every 30s tick.
        if isLow, !wasLow, let stats {
            NotificationService.postLowSpaceWarning(freeBytes: stats.freeBytes)
        }
        wasLow = isLow
    }
}
