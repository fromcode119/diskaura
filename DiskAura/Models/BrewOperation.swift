import Foundation

/// A running (or finished) brew command. Installs take minutes, so the operation carries its own
/// streamed log — a multi-minute wait with no output reads as a frozen app.
struct BrewOperation: Identifiable {
    enum Kind: String {
        case install, uninstall, upgrade, cleanup, autoremove
        var verb: String {
            switch self {
            case .install: return "Installing"
            case .uninstall: return "Uninstalling"
            case .upgrade: return "Upgrading"
            case .cleanup: return "Cleaning up"
            case .autoremove: return "Removing orphaned dependencies"
            }
        }
    }
    enum State: Equatable { case running, succeeded(String), failed(String) }

    let id = UUID()
    let kind: Kind
    /// Package name, or empty for whole-system operations like cleanup.
    let target: String
    var state: State = .running
    var log: [String] = []
    var startedAt = Date()

    var title: String { target.isEmpty ? kind.verb : "\(kind.verb) \(target)" }
    var isRunning: Bool { state == .running }
    /// Last meaningful line — brew's own progress text is the best status we can show.
    var currentLine: String { log.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? "" }
}
