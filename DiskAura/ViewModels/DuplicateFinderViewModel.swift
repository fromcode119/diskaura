import Foundation

enum DuplicateMode: String, CaseIterable, Identifiable {
    case exact = "Exact"
    case similar = "Similar images"
    var id: String { rawValue }
    var detail: String {
        switch self {
        case .exact: return "Byte-for-byte identical files"
        case .similar: return "Look-alike photos — resized, edited, re-exported"
        }
    }
}

@MainActor
final class DuplicateFinderViewModel: ObservableObject {
    @Published var groups: [DuplicateGroup] = []
    @Published var isScanning = false
    @Published var scannedRoot: URL?
    @Published var progressText: String = ""
    @Published var progressFraction: Double = 0
    @Published var mode: DuplicateMode = .exact

    private var scanTask: Task<Void, Never>?
    /// Set from the main actor, read from the background hashing loop — box it so the
    /// `@Sendable` closure can observe cancellation without capturing the actor-isolated VM.
    private final class CancelFlag: @unchecked Sendable { var cancelled = false }
    private var cancelFlag = CancelFlag()

    var totalReclaimable: Int64 {
        groups.reduce(0) { $0 + $1.reclaimableBytes }
    }

    func scan(url: URL) {
        cancel()
        isScanning = true
        scannedRoot = url
        groups = []
        progressText = "Scanning…"
        progressFraction = 0

        let flag = CancelFlag()
        cancelFlag = flag
        let matcher = ExclusionStore().matcher()

        let mode = self.mode
        scanTask = Task {
            let progress: @Sendable (DuplicateFinderService.Progress) -> Void = { p in
                Task { @MainActor [weak self] in
                    guard let self, self.isScanning else { return }
                    if p.total > 0 {
                        self.progressText = "\(p.phase) \(p.done) of \(p.total)…"
                        self.progressFraction = Double(p.done) / Double(p.total)
                    } else {
                        self.progressText = "\(p.phase) \(p.done)…"
                    }
                }
            }
            let result: [DuplicateGroup]
            switch mode {
            case .exact:
                result = await DuplicateFinderService.findDuplicates(
                    in: url, exclusions: matcher, isCancelled: { flag.cancelled }, onProgress: progress)
            case .similar:
                result = await SimilarImageFinder.find(
                    in: url, exclusions: matcher, isCancelled: { flag.cancelled }, onProgress: progress)
            }
            await MainActor.run {
                guard !flag.cancelled else { return }
                self.groups = result
                self.isScanning = false
            }
        }
    }

    func cancel() {
        cancelFlag.cancelled = true
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }
}
