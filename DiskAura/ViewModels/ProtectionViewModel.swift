import Foundation

/// Drives the Protection tab: scans launch items for adware/suspicious entries and quarantines
/// the selected ones to the Trash.
@MainActor
final class ProtectionViewModel: ObservableObject {
    @Published private(set) var threats: [Threat] = []
    @Published private(set) var scanning = false
    @Published private(set) var hasScanned = false
    @Published private(set) var removing = false
    @Published var selected: Set<String> = []
    @Published private(set) var lastRemoved: Int?

    func scan() {
        guard !scanning else { return }
        scanning = true
        lastRemoved = nil
        Task {
            let found = await Task.detached(priority: .userInitiated) { ProtectionService.scan() }.value
            threats = found
            selected = Set(found.filter { $0.severity == .high }.map { $0.id })  // pre-select confirmed adware
            scanning = false
            hasScanned = true
        }
    }

    func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    func quarantine() {
        let toRemove = threats.filter { selected.contains($0.id) }
        guard !removing, !toRemove.isEmpty else { return }
        removing = true
        Task {
            let count = await Task.detached(priority: .userInitiated) { ProtectionService.quarantine(toRemove) }.value
            removing = false
            lastRemoved = count
            scan()
        }
    }
}
