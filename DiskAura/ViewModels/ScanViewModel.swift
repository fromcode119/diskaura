import Foundation
import SwiftUI

@MainActor
final class ScanViewModel: ObservableObject {
    @Published var result: ScanResult?
    @Published var isScanning = false
    @Published var progressPath: String = ""
    @Published var nodesScanned = 0
    @Published var selectedNode: FileNode?
    @Published var errorMessage: String?

    let classification = ClassificationEngine()
    let recentLocations = RecentLocationsStore()
    let history = ScanHistoryStore()
    let exclusions = ExclusionStore()
    private var scanner: DiskScanner?

    func scan(url: URL) {
        isScanning = true
        progressPath = ""
        nodesScanned = 0
        errorMessage = nil
        recentLocations.recordVisit(url)

        let scanner = DiskScanner()
        self.scanner = scanner
        let matcher = exclusions.matcher()

        Task {
            let scanResult = await scanner.scan(rootURL: url, classification: classification, exclusions: matcher) { [weak self] progress in
                Task { @MainActor in
                    self?.progressPath = progress.currentPath
                    self?.nodesScanned = progress.nodesScanned
                }
            }
            await MainActor.run {
                self.result = scanResult
                self.selectedNode = scanResult.root
                self.isScanning = false
                self.recordAndCheckGrowth(scanResult)
            }
        }
    }

    func cancelScan() {
        Task { await scanner?.cancel() }
        isScanning = false
    }

    /// Records this scan into history and, if it grew significantly since the last scan
    /// of the same root, posts a notification — this is what makes scheduled background
    /// scans actually useful instead of just quietly accumulating snapshots nobody reads.
    private func recordAndCheckGrowth(_ scanResult: ScanResult) {
        let previousSnapshot = history.latest(for: scanResult.root.path)
        history.record(scanResult)

        guard let previousSnapshot else { return }
        let delta = scanResult.root.sizeBytes - previousSnapshot.totalBytes
        let significantGrowth: Int64 = 1_000_000_000 // 1GB
        if delta >= significantGrowth {
            NotificationService.postScanGrowthAlert(deltaBytes: delta, rootName: scanResult.root.name)
        }
    }
}
