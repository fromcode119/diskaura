import Foundation

/// Applies the built-in rule set plus any user overrides (persisted to UserDefaults)
/// to decide a folder's tag: Keep / Clean / Archive / System.
final class ClassificationEngine: ObservableObject {
    @Published var rules: [ClassificationRule]
    private var overrides: [String: NodeTag]

    private static let overridesKey = "com.kristian.diskaura.tagOverrides"

    init() {
        self.rules = DefaultRules.load()
        self.overrides = Self.loadOverrides()
    }

    func tag(for url: URL) -> NodeTag {
        if let override = overrides[url.path] {
            return override
        }
        for rule in rules {
            if rule.matches(url: url) {
                return rule.tag
            }
        }
        return .keep
    }

    func matchedRule(for url: URL) -> ClassificationRule? {
        rules.first { $0.matches(url: url) }
    }

    func setOverride(_ tag: NodeTag, for node: FileNode) {
        overrides[node.path] = tag
        node.tag = tag
        persistOverrides()
    }

    func clearOverride(for node: FileNode) {
        overrides.removeValue(forKey: node.path)
        node.tag = tag(for: node.url)
        persistOverrides()
    }

    private func persistOverrides() {
        let encoded = overrides.mapValues { $0.rawValue }
        UserDefaults.standard.set(encoded, forKey: Self.overridesKey)
    }

    private static func loadOverrides() -> [String: NodeTag] {
        guard let raw = UserDefaults.standard.dictionary(forKey: overridesKey) as? [String: String] else {
            return [:]
        }
        var result: [String: NodeTag] = [:]
        for (path, rawTag) in raw {
            if let tag = NodeTag(rawValue: rawTag) {
                result[path] = tag
            }
        }
        return result
    }
}
