import Foundation
import SwiftUI

@MainActor
final class ActionQueueViewModel: ObservableObject {
    @Published var pendingActions: [PendingAction] = []
    @Published var isExecuting = false
    @Published var executionError: String?
    /// Bumped after every successful executeAll so any view showing a scan can re-scan and
    /// drop the rows it just deleted — previously deleted files kept showing until manual rescan.
    @Published var executedGeneration = 0
    @Published var lastExecutedCount = 0
    @Published var archiveDestinationPath: String {
        didSet {
            UserDefaults.standard.set(archiveDestinationPath, forKey: Self.archiveKey)
        }
    }

    private static let archiveKey = "com.kristian.diskaura.archiveDestination"
    private let executor = ActionExecutor()

    init() {
        self.archiveDestinationPath = UserDefaults.standard.string(forKey: Self.archiveKey)
            ?? "/Volumes/Storage/Mac"
    }

    var totalBytes: Int64 {
        pendingActions.reduce(0) { $0 + $1.node.sizeBytes }
    }

    func queue(_ node: FileNode, kind: ActionKind) {
        pendingActions.removeAll { $0.node.path == node.path }
        pendingActions.append(PendingAction(node: node, kind: kind))
    }

    func remove(_ action: PendingAction) {
        pendingActions.removeAll { $0.id == action.id }
    }

    /// Lets a view check/toggle queue membership by path — used by Duplicate Finder and
    /// Large & Old Files so a queued row can show "queued" state and be un-queued again,
    /// instead of only ever being able to add to the queue.
    func isQueued(_ node: FileNode) -> Bool {
        pendingActions.contains { $0.node.path == node.path }
    }

    func unqueue(_ node: FileNode) {
        pendingActions.removeAll { $0.node.path == node.path }
    }

    func clear() {
        pendingActions.removeAll()
    }

    func executeAll() async {
        isExecuting = true
        executionError = nil
        let destinationURL = URL(fileURLWithPath: archiveDestinationPath)

        var done = 0
        for action in pendingActions {
            do {
                try await executor.execute(action, archiveDestinationRoot: destinationURL)
                done += 1
            } catch {
                executionError = error.localizedDescription
            }
        }

        pendingActions.removeAll()
        isExecuting = false
        lastExecutedCount = done
        executedGeneration += 1
    }
}
