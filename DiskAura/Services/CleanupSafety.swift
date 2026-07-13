import Foundation

/// A hard, defensive guard on what Cleanup is ever allowed to remove. Every path the junk
/// scanner produces already lives under the user's home, but this re-checks each item right
/// before it's trashed — so even a future bug that introduced a bad path can NEVER let Cleanup
/// touch macOS system files. The rules mirror Apple/DaisyDisk guidance: only inside ~, never
/// /System or /Library, and never a whole protected top-level user folder.
enum CleanupSafety {
    private static var home: String {
        FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
    }

    /// Top-level home folders that must never be removed wholesale (their *contents* under
    /// Caches/Logs are fine — this only blocks the folders themselves).
    private static var protectedRoots: Set<String> {
        Set(["Library", "Documents", "Desktop", "Pictures", "Movies", "Music", "Applications", "Public", ".ssh", ".config"]
            .map { home + "/" + $0 })
    }

    static func isSafeToClean(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        // 1. Must be strictly INSIDE the user's home directory (never home itself).
        guard path.hasPrefix(home + "/"), path != home else { return false }
        // 2. Never a protected top-level folder itself.
        guard !protectedRoots.contains(path) else { return false }
        // 3. Never anything that resolves into the OS system trees, even via a symlink.
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
        for systemTree in ["/System", "/Library", "/private/var/db", "/usr", "/bin", "/sbin", "/Applications"] {
            if resolved == systemTree || resolved.hasPrefix(systemTree + "/") { return false }
        }
        return true
    }
}
