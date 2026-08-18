import Foundation

/// Locates the Homebrew installation. "Not installed" is a normal, expected state the UI handles
/// explicitly — never an error and never an empty list, which would read as "you have no packages".
struct BrewEnvironment: Equatable {
    let binaryPath: String
    /// Install root (`/opt/homebrew` on Apple Silicon, `/usr/local` on Intel).
    let prefix: String

    /// Standard brew locations, Apple Silicon first.
    static let defaultCandidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]

    /// Returns the first candidate that exists and is executable, or nil when Homebrew is absent.
    /// `candidates` is injectable so tests never depend on the developer's own machine.
    static func locate(candidates: [String] = defaultCandidates,
                       fileManager: FileManager = .default) -> BrewEnvironment? {
        for path in candidates where fileManager.isExecutableFile(atPath: path) {
            // <prefix>/bin/brew — strip the two trailing components to get the prefix.
            let prefix = URL(fileURLWithPath: path).deletingLastPathComponent()
                .deletingLastPathComponent().path
            return BrewEnvironment(binaryPath: path, prefix: prefix)
        }
        return nil
    }

    var cellarURL: URL { URL(fileURLWithPath: prefix).appendingPathComponent("Cellar") }
    var caskroomURL: URL { URL(fileURLWithPath: prefix).appendingPathComponent("Caskroom") }
}
