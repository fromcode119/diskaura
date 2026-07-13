import Foundation

/// Guard for the Secure Shredder. Unlike `CleanupSafety` (which only permits known junk under
/// ~), the Shredder acts on files the user explicitly picked — anywhere: Downloads, Desktop,
/// external drives, temp. So this blocks only genuine hazards: the filesystem root, whole
/// volume roots, the macOS system trees, and the user's home / top-level personal folders
/// *themselves* (their contents are fine — you can shred a file inside Documents, just not the
/// Documents folder wholesale).
enum ShredSafety {
    static func isShreddable(_ url: URL) -> Bool {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
        guard resolved != "/" else { return false }

        // Whole-volume roots: "/Volumes" and "/Volumes/<Name>" (exactly 3 components: "", "Volumes", "Name").
        if resolved == "/Volumes" { return false }
        if resolved.hasPrefix("/Volumes/"),
           resolved.split(separator: "/", omittingEmptySubsequences: true).count == 1 { return false }

        for tree in ["/System", "/Library", "/usr", "/bin", "/sbin",
                     "/private/var/db", "/private/etc", "/Applications", "/cores", "/opt"] {
            if resolved == tree || resolved.hasPrefix(tree + "/") { return false }
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        guard resolved != home else { return false }
        let protectedHome = ["Library", "Documents", "Desktop", "Pictures", "Movies", "Music", "Public", ".ssh", ".config"]
            .map { home + "/" + $0 }
        guard !protectedHome.contains(resolved) else { return false }

        return true
    }
}
