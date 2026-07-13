import Foundation

/// Where a launch item lives — drives whether removing it needs admin rights.
enum LaunchDomain: String {
    case userAgent = "User"
    case systemAgent = "System"
    case daemon = "Daemon"
}

/// A background startup item — a LaunchAgent/LaunchDaemon plist that macOS runs automatically.
/// These are the "why is my Mac slow at login / what's running in the background" items that
/// CleanMyMac's Optimization module surfaces.
struct LaunchItem: Identifiable {
    var id: String { url.path }
    let url: URL
    let label: String        // the plist's Label, e.g. us.zoom.ZoomDaemon
    let program: String      // the executable it runs (first ProgramArguments entry / Program)
    let runAtLoad: Bool
    let domain: LaunchDomain
    var enabled: Bool = true  // false when launchctl has it disabled (won't start at login)

    /// System agents and daemons live under /Library — removing them needs admin rights.
    var requiresAdmin: Bool { domain != .userAgent }
    var appName: String {
        // A friendlier name: the plist filename without the reverse-DNS noise.
        let base = url.deletingPathExtension().lastPathComponent
        return base
    }
}
