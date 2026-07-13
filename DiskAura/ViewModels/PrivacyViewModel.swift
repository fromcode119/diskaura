import Foundation

/// Drives the Privacy tab: scans browser traces, tracks selection, and cleans to Trash.
@MainActor
final class PrivacyViewModel: ObservableObject {
    @Published private(set) var items: [PrivacyItem] = []
    @Published private(set) var scanning = false
    @Published private(set) var hasScanned = false
    @Published private(set) var cleaning = false
    @Published var selected: Set<String> = []
    @Published private(set) var lastCleaned: (count: Int, bytes: Int64)?

    var totalBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }
    var selectedBytes: Int64 { items.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.sizeBytes } }

    func scan() {
        guard !scanning else { return }
        scanning = true
        lastCleaned = nil
        Task {
            let found = await Task.detached(priority: .userInitiated) { PrivacyService.scan() }.value
            items = found
            // Pre-select the safe caches; leave cookies/history unchecked by default.
            selected = Set(found.filter { $0.category == .caches }.map { $0.id })
            scanning = false
            hasScanned = true
        }
    }

    func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    func clean() {
        let toClean = items.filter { selected.contains($0.id) }
        guard !cleaning, !toClean.isEmpty else { return }
        cleaning = true
        Task {
            let result = await Task.detached(priority: .userInitiated) { PrivacyService.clean(toClean) }.value
            cleaning = false
            lastCleaned = (count: result.cleaned, bytes: result.bytes)
            scan()
        }
    }
}
