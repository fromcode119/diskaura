import Foundation

/// The user's Ignore List — folders DiskAura must never scan, count, or offer to clean
/// (CleanMyMac's "Ignore List"). Persisted in UserDefaults. Matching is prefix-based on the
/// standardized path, so excluding `~/Work` also excludes everything beneath it.
@MainActor
final class ExclusionStore: ObservableObject {
    @Published private(set) var paths: [String] = []

    private static let key = "com.kristian.diskaura.exclusions"

    init() {
        paths = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
    }

    func add(_ url: URL) {
        let p = Self.normalize(url.path)
        guard !paths.contains(p) else { return }
        paths.append(p)
        paths.sort()
        persist()
    }

    func remove(_ path: String) {
        paths.removeAll { $0 == path }
        persist()
    }

    /// A plain snapshot of the paths for handing to background scanners (which aren't on the
    /// main actor). Matching is done by `ExclusionMatcher` so it needs no actor hop.
    func matcher() -> ExclusionMatcher {
        ExclusionMatcher(paths: paths)
    }

    private func persist() {
        UserDefaults.standard.set(paths, forKey: Self.key)
    }

    nonisolated static func normalize(_ path: String) -> String {
        var p = (path as NSString).standardizingPath
        if p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return p
    }
}

/// Sendable value type used off the main actor to test membership without touching the store.
struct ExclusionMatcher: Sendable {
    let paths: [String]

    func isExcluded(_ url: URL) -> Bool {
        isExcluded(path: url.path)
    }

    func isExcluded(path: String) -> Bool {
        guard !paths.isEmpty else { return false }
        let target = ExclusionStore.normalize(path)
        for excluded in paths {
            if target == excluded || target.hasPrefix(excluded + "/") { return true }
        }
        return false
    }
}
