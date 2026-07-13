import Foundation

enum ActionKind: String, Codable {
    case trash
    case permanentDelete
    case archiveMove
}

struct PendingAction: Identifiable {
    var id: String { node.path }
    let node: FileNode
    let kind: ActionKind
}

struct ActionLogEntry: Codable {
    let path: String
    let kind: ActionKind
    let destination: String?
    let sizeBytes: Int64
    let timestamp: Date
}
