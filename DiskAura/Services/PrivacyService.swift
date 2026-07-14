import Foundation
import AppKit

/// A browser we can clean privacy data for.
enum PrivacyBrowser: String, CaseIterable {
    case safari = "Safari"
    case chrome = "Google Chrome"
    case firefox = "Firefox"

    var bundleID: String {
        switch self {
        case .safari: return "com.apple.Safari"
        case .chrome: return "com.google.Chrome"
        case .firefox: return "org.mozilla.firefox"
        }
    }
    var icon: String {
        switch self {
        case .safari: return "safari.fill"
        case .chrome: return "globe"
        case .firefox: return "flame"
        }
    }
}

/// What kind of trace a `PrivacyItem` is — caches are safe to clear anytime; cookies/history
/// hold sign-ins and browsing history, and clearing them while the browser runs can corrupt
/// the profile (so the UI guards those when the browser is open).
enum PrivacyCategory: String {
    case caches = "Caches"
    case cookies = "Cookies"
    case history = "History"
    var sensitive: Bool { self != .caches }
    var detail: String {
        switch self {
        case .caches: return "Cached pages and images — safe to clear anytime."
        case .cookies: return "Sign-ins and tracking cookies. Clears saved logins."
        case .history: return "Sites you've visited and downloads."
        }
    }
}

struct PrivacyItem: Identifiable {
    let id: String
    let browser: PrivacyBrowser
    let category: PrivacyCategory
    let paths: [URL]
    let sizeBytes: Int64
    let browserRunning: Bool
}

/// Finds and clears browser privacy traces (caches / cookies / history) for the installed
/// browsers. Everything is moved to the Trash (recoverable), never hard-deleted.
enum PrivacyService {
    static func scan() -> [PrivacyItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var items: [PrivacyItem] = []
        for browser in PrivacyBrowser.allCases {
            let running = isRunning(browser)
            for (category, candidates) in paths(for: browser, home: home) {
                let existing = candidates.filter { FileManager.default.fileExists(atPath: $0.path) }
                guard !existing.isEmpty else { continue }
                let size = existing.reduce(Int64(0)) { $0 + directorySize(at: $1) }
                guard size > 0 else { continue }
                items.append(PrivacyItem(id: "\(browser.rawValue)-\(category.rawValue)",
                                         browser: browser, category: category,
                                         paths: existing, sizeBytes: size, browserRunning: running))
            }
        }
        return items
    }

    static func isRunning(_ browser: PrivacyBrowser) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID).isEmpty
    }

    /// Moves each selected item's files to the Trash. Returns count + bytes reclaimed.
    static func clean(_ items: [PrivacyItem]) -> (cleaned: Int, bytes: Int64, failed: Int) {
        var cleaned = 0
        var bytes: Int64 = 0
        var failed = 0
        for item in items {
            var anyCleaned = false
            for url in item.paths {
                do {
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                    cleaned += 1
                    anyCleaned = true
                } catch {
                    // Safari's data (and some others) lives in TCC-protected locations that need
                    // Full Disk Access; trashItem fails there. Surface that instead of silently
                    // doing nothing.
                    failed += 1
                }
            }
            if anyCleaned { bytes += item.sizeBytes }
        }
        return (cleaned, bytes, failed)
    }

    // MARK: - Known locations

    private static func paths(for browser: PrivacyBrowser, home: URL) -> [(PrivacyCategory, [URL])] {
        func lib(_ p: String) -> URL { home.appendingPathComponent("Library/\(p)") }
        switch browser {
        case .safari:
            return [
                (.caches, [lib("Caches/com.apple.Safari"),
                           lib("Containers/com.apple.Safari/Data/Library/Caches")]),
                (.history, [lib("Safari/History.db"), lib("Safari/History.db-wal"), lib("Safari/History.db-shm")]),
            ]
        case .chrome:
            let support = "Application Support/Google/Chrome/Default"
            return [
                (.caches, [lib("Caches/Google/Chrome")]),
                (.cookies, [lib("\(support)/Cookies"), lib("\(support)/Network/Cookies")]),
                (.history, [lib("\(support)/History")]),
            ]
        case .firefox:
            let profiles = firefoxProfiles(home: home)
            return [
                (.caches, [lib("Caches/Firefox")]),
                (.cookies, profiles.map { $0.appendingPathComponent("cookies.sqlite") }),
                (.history, profiles.map { $0.appendingPathComponent("places.sqlite") }),
            ]
        }
    }

    private static func firefoxProfiles(home: URL) -> [URL] {
        let base = home.appendingPathComponent("Library/Application Support/Firefox/Profiles")
        return (try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? []
    }

    private static func directorySize(at url: URL) -> Int64 {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return 0 }
        if (info.st_mode & S_IFMT) != S_IFDIR { return Int64(info.st_blocks) * 512 }
        guard let en = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in en {
            var s = stat()
            if lstat(f.path, &s) == 0, (s.st_mode & S_IFMT) != S_IFLNK { total += Int64(s.st_blocks) * 512 }
        }
        return total
    }
}
