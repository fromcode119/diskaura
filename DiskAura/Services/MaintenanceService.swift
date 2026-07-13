import Foundation

/// Whether a maintenance task needs administrator rights (one macOS auth prompt) or runs as the user.
enum MaintenancePrivilege { case user, admin }

/// A single, well-known macOS maintenance action. `commands` run in order through a shell.
struct MaintenanceTask: Identifiable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    let privilege: MaintenancePrivilege
    let commands: [String]
    var needsAdmin: Bool { privilege == .admin }
}

/// Outcome of running a task — carries trimmed command output so the UI can show a real result.
enum MaintenanceOutcome: Equatable {
    case success(String)
    case failure(String)
    case cancelled
}

/// Runs standard macOS upkeep — freeing RAM, flushing caches, rebuilding system databases.
/// Privileged tasks are escalated with a single `osascript … with administrator privileges`
/// prompt (the OS shows the auth dialog; the app never sees the password). Same escalation
/// pattern the uninstaller uses for root-owned apps.
enum MaintenanceService {
    static let catalog: [MaintenanceTask] = [
        MaintenanceTask(
            id: "free-ram",
            title: "Free up memory",
            detail: "Flushes inactive memory back to the free pool (purge). Helps when apps feel sluggish.",
            icon: "memorychip.fill", privilege: .admin,
            commands: ["/usr/sbin/purge"]),
        MaintenanceTask(
            id: "flush-dns",
            title: "Flush DNS cache",
            detail: "Clears cached name lookups. Fixes sites that won't load after a network change.",
            icon: "network", privilege: .admin,
            commands: ["/usr/bin/dscacheutil -flushcache",
                       "/usr/bin/killall -HUP mDNSResponder"]),
        MaintenanceTask(
            id: "reindex-spotlight",
            title: "Rebuild Spotlight index",
            detail: "Erases and rebuilds the search index for your startup disk. Fixes bad search results (reindex runs in the background afterwards).",
            icon: "magnifyingglass", privilege: .admin,
            commands: ["/usr/bin/mdutil -E /"]),
        MaintenanceTask(
            id: "periodic",
            title: "Run macOS maintenance scripts",
            detail: "Runs the built-in daily / weekly / monthly upkeep (log rotation, temp cleanup) that only runs if your Mac is awake overnight.",
            icon: "calendar.badge.clock", privilege: .admin,
            commands: ["/usr/sbin/periodic daily weekly monthly"]),
        MaintenanceTask(
            id: "launch-services",
            title: "Rebuild Launch Services",
            detail: "Rebuilds the ‘Open With’ database. Fixes duplicate or wrong app associations in Finder.",
            icon: "app.badge", privilege: .user,
            commands: ["/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -kill -r -domain local -domain system -domain user"]),
        MaintenanceTask(
            id: "font-caches",
            title: "Clear font caches",
            detail: "Removes your user font cache. Fixes garbled text and font-picker glitches.",
            icon: "textformat", privilege: .user,
            commands: ["/System/Library/Frameworks/ApplicationServices.framework/Frameworks/ATS.framework/Support/atsutil databases -removeUser"]),
        MaintenanceTask(
            id: "quicklook",
            title: "Reset QuickLook thumbnails",
            detail: "Rebuilds the preview/thumbnail cache. Fixes wrong or missing Finder previews.",
            icon: "eye", privilege: .user,
            commands: ["/usr/bin/qlmanage -r cache"]),
        MaintenanceTask(
            id: "restart-finder",
            title: "Restart Finder",
            detail: "Relaunches Finder. Clears UI glitches and frees memory it may be holding.",
            icon: "macwindow", privilege: .user,
            commands: ["/usr/bin/killall Finder"]),
        MaintenanceTask(
            id: "restart-dock",
            title: "Restart Dock & menu bar",
            detail: "Relaunches the Dock (and menu-bar extras). Fixes a frozen or laggy Dock.",
            icon: "dock.rectangle", privilege: .user,
            commands: ["/usr/bin/killall Dock"]),
    ]

    /// Runs one task. Admin tasks trigger a single auth prompt; user tasks run directly.
    static func run(_ task: MaintenanceTask) async -> MaintenanceOutcome {
        await Task.detached(priority: .userInitiated) {
            task.needsAdmin ? runAdmin(task.commands) : runUser(task.commands)
        }.value
    }

    /// Runs every user-level task's commands directly, plus all admin commands behind ONE prompt.
    /// Returns per-task outcomes keyed by task id, so "Run all" is a single password prompt.
    static func runAll(_ tasks: [MaintenanceTask]) async -> [String: MaintenanceOutcome] {
        await Task.detached(priority: .userInitiated) { () -> [String: MaintenanceOutcome] in
            var results: [String: MaintenanceOutcome] = [:]
            for task in tasks where task.privilege == .user {
                results[task.id] = runUser(task.commands)
            }
            let adminTasks = tasks.filter { $0.privilege == .admin }
            if !adminTasks.isEmpty {
                let outcome = runAdmin(adminTasks.flatMap { $0.commands })
                for task in adminTasks { results[task.id] = outcome }
            }
            return results
        }.value
    }

    // MARK: - Execution

    private static func runUser(_ commands: [String]) -> MaintenanceOutcome {
        let (ok, out) = shell("/bin/sh", ["-c", commands.joined(separator: " && ")])
        return ok ? .success(clean(out)) : .failure(clean(out))
    }

    private static func runAdmin(_ commands: [String]) -> MaintenanceOutcome {
        let script = commands.joined(separator: " && ")
        let appleScript = "do shell script \"\(escapeForAppleScript(script))\" with administrator privileges"
        let (ok, out) = shell("/usr/bin/osascript", ["-e", appleScript])
        if ok { return .success(clean(out)) }
        // osascript exits non-zero when the user cancels the auth dialog (error -128).
        return out.contains("-128") || out.localizedCaseInsensitiveContains("cancel")
            ? .cancelled : .failure(clean(out))
    }

    private static func shell(_ launch: String, _ args: [String]) -> (Bool, String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launch)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (proc.terminationStatus == 0, String(data: data, encoding: .utf8) ?? "")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    private static func clean(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Done." : String(t.prefix(400))
    }

    private static func escapeForAppleScript(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
