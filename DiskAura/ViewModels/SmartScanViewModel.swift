import Foundation

/// Drives Smart Scan: runs the aggregated analyzers and holds the routed findings.
@MainActor
final class SmartScanViewModel: ObservableObject {
    @Published private(set) var findings: [SmartFinding] = []
    @Published private(set) var scanning = false
    @Published private(set) var hasScanned = false

    var totalBytes: Int64 { findings.reduce(0) { $0 + $1.bytes } }

    func scan() {
        guard !scanning else { return }
        scanning = true
        Task {
            let results = await SmartScanService.scan()
            findings = results
            scanning = false
            hasScanned = true
        }
    }
}
