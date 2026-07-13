import Foundation

/// Persists recently/commonly scanned folder paths for one-click re-scan from the sidebar.
final class RecentLocationsStore: ObservableObject {
    @Published private(set) var paths: [String]

    private static let key = "com.kristian.diskaura.recentLocations"
    private static let maxEntries = 8

    static let defaults: [String] = [
        FileManager.default.homeDirectoryForCurrentUser.path,
        "/Applications",
        (FileManager.default.homeDirectoryForCurrentUser.path as NSString).appendingPathComponent("Library"),
        (FileManager.default.homeDirectoryForCurrentUser.path as NSString).appendingPathComponent("Downloads"),
    ]

    init() {
        if let saved = UserDefaults.standard.stringArray(forKey: Self.key), !saved.isEmpty {
            self.paths = saved
        } else {
            self.paths = Self.defaults
        }
    }

    func recordVisit(_ url: URL) {
        var updated = paths.filter { $0 != url.path }
        updated.insert(url.path, at: 0)
        paths = Array(updated.prefix(Self.maxEntries))
        UserDefaults.standard.set(paths, forKey: Self.key)
    }

    func remove(_ path: String) {
        paths.removeAll { $0 == path }
        UserDefaults.standard.set(paths, forKey: Self.key)
    }
}
