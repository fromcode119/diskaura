import Foundation
import AppKit

enum ActionExecutorError: LocalizedError {
    case moveFailed(String)
    case deleteFailed(String)
    case trashFailed(String)

    var errorDescription: String? {
        switch self {
        case .moveFailed(let reason): return "Move failed: \(reason)"
        case .deleteFailed(let reason): return "Delete failed: \(reason)"
        case .trashFailed(let reason): return "Trash failed: \(reason)"
        }
    }
}

/// Executes tagged actions (Trash / permanent delete / archive-move) and appends
/// every executed action to a JSON audit log. This is a history log only — v1 does not
/// offer automated restore, since kristian opted for the permanent-delete flow over
/// a full undo system.
struct ActionExecutor {
    static let logURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("DiskAura", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("actions.log")
    }()

    func execute(_ action: PendingAction, archiveDestinationRoot: URL?) async throws {
        switch action.kind {
        case .trash:
            try await trash(action.node)
        case .permanentDelete:
            try permanentlyDelete(action.node)
        case .archiveMove:
            guard let archiveDestinationRoot else {
                throw ActionExecutorError.moveFailed("No archive destination configured")
            }
            try move(action.node, to: archiveDestinationRoot)
        }
        appendLog(action, destination: archiveDestinationRoot)
    }

    private func trash(_ node: FileNode) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.recycle([node.url]) { _, error in
                if let error {
                    continuation.resume(throwing: ActionExecutorError.trashFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func permanentlyDelete(_ node: FileNode) throws {
        do {
            try FileManager.default.removeItem(at: node.url)
        } catch {
            throw ActionExecutorError.deleteFailed(error.localizedDescription)
        }
    }

    private func move(_ node: FileNode, to destinationRoot: URL) throws {
        do {
            try FileManager.default.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
            let destination = destinationRoot.appendingPathComponent(node.name)
            var finalDestination = destination
            var counter = 1
            while FileManager.default.fileExists(atPath: finalDestination.path) {
                finalDestination = destinationRoot.appendingPathComponent("\(node.name)-\(counter)")
                counter += 1
            }
            try FileManager.default.moveItem(at: node.url, to: finalDestination)
        } catch {
            throw ActionExecutorError.moveFailed(error.localizedDescription)
        }
    }

    private func appendLog(_ action: PendingAction, destination: URL?) {
        let entry = ActionLogEntry(
            path: action.node.path,
            kind: action.kind,
            destination: destination?.path,
            sizeBytes: action.node.sizeBytes,
            timestamp: Date()
        )

        var entries: [ActionLogEntry] = []
        if let data = try? Data(contentsOf: Self.logURL),
           let existing = try? JSONDecoder().decode([ActionLogEntry].self, from: data) {
            entries = existing
        }
        entries.append(entry)

        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: Self.logURL)
        }
    }

    static func loadLog() -> [ActionLogEntry] {
        guard let data = try? Data(contentsOf: logURL),
              let entries = try? JSONDecoder().decode([ActionLogEntry].self, from: data) else {
            return []
        }
        return entries.sorted { $0.timestamp > $1.timestamp }
    }
}
