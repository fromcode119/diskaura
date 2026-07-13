import Foundation

struct ClassificationRule: Codable, Identifiable, Hashable {
    enum MatchKind: String, Codable {
        case folderName
        case pathSuffix
        case absolutePath
    }

    var id: String { name }
    let name: String
    let kind: MatchKind
    let pattern: String
    let tag: NodeTag
    let note: String?

    func matches(url: URL) -> Bool {
        let path = url.path
        switch kind {
        case .folderName:
            return url.lastPathComponent == pattern
        case .pathSuffix:
            return path.hasSuffix(pattern)
        case .absolutePath:
            let expanded = (pattern as NSString).expandingTildeInPath
            return path == expanded || path.hasPrefix(expanded + "/")
        }
    }
}

enum DefaultRules {
    static func load() -> [ClassificationRule] {
        guard
            let url = Bundle.main.url(forResource: "DefaultRules", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let rules = try? JSONDecoder().decode([ClassificationRule].self, from: data)
        else {
            return fallback
        }
        return rules
    }

    // Used if the bundled JSON fails to load for any reason.
    static let fallback: [ClassificationRule] = [
        ClassificationRule(name: "node_modules", kind: .folderName, pattern: "node_modules", tag: .clean, note: "Reinstalled via npm/pnpm install"),
        ClassificationRule(name: "Rust target", kind: .folderName, pattern: "target", tag: .clean, note: "Rebuilt via cargo build"),
        ClassificationRule(name: "Xcode DerivedData", kind: .absolutePath, pattern: "~/Library/Developer/Xcode/DerivedData", tag: .clean, note: "Rebuilt by Xcode"),
        ClassificationRule(name: "Docker VM", kind: .absolutePath, pattern: "~/Library/Containers/com.docker.docker", tag: .clean, note: "Prune from Docker Desktop instead"),
        ClassificationRule(name: "CoreSimulator", kind: .absolutePath, pattern: "~/Library/Developer/CoreSimulator", tag: .clean, note: "Simulators re-download"),
    ]
}
