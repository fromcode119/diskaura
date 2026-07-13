import Foundation
import AppKit

/// Full Disk Access gate. macOS TCC keeps protected locations (Mail, Messages, Safari,
/// other apps' containers, most of /Library) unreadable until the user grants an app Full
/// Disk Access — which is exactly what a cleanup/uninstall tool needs to see every leftover
/// and empty every cache. There's no public API to query TCC, so we probe a known-protected
/// path: if we can list it, FDA is effectively granted; if it throws, it isn't.
enum FullDiskAccessService {
    /// A TCC-protected path that a non-FDA app cannot read. `~/Library/Mail` is the standard
    /// probe — present on virtually every Mac and gated behind Full Disk Access.
    private static var probeURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mail", isDirectory: true)
    }

    /// True when the protected probe path is readable (FDA granted) OR simply doesn't exist
    /// (nothing to gate — treat as not-blocking rather than nagging on a Mac without Mail).
    static func isGranted() -> Bool {
        let fm = FileManager.default
        let path = probeURL.path
        guard fm.fileExists(atPath: path) else { return true }
        return (try? fm.contentsOfDirectory(atPath: path)) != nil
    }

    /// Opens System Settings → Privacy & Security → Full Disk Access, ready for the user to
    /// flip DiskAura on. Deep-link URL is the documented TCC anchor for that pane.
    static func openSettingsPane() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }
}
