import Foundation

/// Drives the Maintenance tab: tracks which tasks are running and their last outcome.
@MainActor
final class MaintenanceViewModel: ObservableObject {
    @Published private(set) var running: Set<String> = []
    @Published private(set) var results: [String: MaintenanceOutcome] = [:]
    @Published private(set) var runningAll = false

    let tasks = MaintenanceService.catalog

    func isRunning(_ id: String) -> Bool { running.contains(id) }

    func run(_ task: MaintenanceTask) {
        guard !running.contains(task.id) else { return }
        running.insert(task.id)
        Task {
            let outcome = await MaintenanceService.run(task)
            running.remove(task.id)
            results[task.id] = outcome
        }
    }

    func runAll() {
        guard !runningAll else { return }
        runningAll = true
        running = Set(tasks.map { $0.id })
        Task {
            let outcomes = await MaintenanceService.runAll(tasks)
            results = outcomes
            running = []
            runningAll = false
        }
    }
}
