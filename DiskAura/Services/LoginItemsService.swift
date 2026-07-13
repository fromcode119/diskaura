import Foundation

/// Enumerates and manages background startup items — LaunchAgents and LaunchDaemons. These
/// plists are what macOS runs automatically at login/boot; trimming the ones you don't need is
/// the classic "speed up my Mac's startup" win. User agents can be removed without admin;
/// system agents/daemons under /Library are flagged as needing admin (removed by hand).
enum LoginItemsService {
    private static let sources: [(root: String, domain: LaunchDomain)] = [
        ("~/Library/LaunchAgents", .userAgent),
        ("/Library/LaunchAgents", .systemAgent),
        ("/Library/LaunchDaemons", .daemon),
    ]

    static func list() -> [LaunchItem] {
        let fm = FileManager.default
        let disabled = disabledLabels()
        var items: [LaunchItem] = []
        for source in sources {
            let dir = (source.root as NSString).expandingTildeInPath
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for entry in entries where entry.hasSuffix(".plist") {
                let url = URL(fileURLWithPath: (dir as NSString).appendingPathComponent(entry))
                let (label, program, runAtLoad) = parse(url)
                items.append(LaunchItem(url: url, label: label, program: program,
                                        runAtLoad: runAtLoad, domain: source.domain,
                                        enabled: !disabled.contains(label)))
            }
        }
        return items.sorted { $0.label.lowercased() < $1.label.lowercased() }
    }

    /// Labels launchctl has marked disabled in the GUI domain — these won't start at login even
    /// though their plist is still present.
    private static func disabledLabels() -> Set<String> {
        let out = run(["/bin/launchctl", "print-disabled", "gui/\(getuid())"]) ?? ""
        var set = Set<String>()
        for line in out.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            // lines look like:  "com.foo.bar" => true   (true == disabled)
            if t.contains("=> true"), let q1 = t.firstIndex(of: "\""),
               let q2 = t[t.index(after: q1)...].firstIndex(of: "\"") {
                set.insert(String(t[t.index(after: q1)..<q2]))
            }
        }
        return set
    }

    /// Enable or disable a login item WITHOUT deleting its plist, via launchctl's persistent
    /// override database. Works for user (GUI-domain) agents without admin; takes effect at the
    /// next login/load. Returns false if launchctl refused (e.g. a system daemon needing sudo).
    @discardableResult
    static func setEnabled(_ item: LaunchItem, enabled: Bool) -> Bool {
        guard item.domain == .userAgent else { return false }
        let verb = enabled ? "enable" : "disable"
        return runWithStatus(["/bin/launchctl", verb, "gui/\(getuid())/\(item.label)"]).0
    }

    private static func parse(_ url: URL) -> (label: String, program: String, runAtLoad: Bool) {
        let fallbackLabel = url.deletingPathExtension().lastPathComponent
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else { return (fallbackLabel, "—", false) }

        let label = (plist["Label"] as? String) ?? fallbackLabel
        let runAtLoad = (plist["RunAtLoad"] as? Bool) ?? false
        let program: String
        if let args = plist["ProgramArguments"] as? [String], let first = args.first {
            program = first
        } else if let p = plist["Program"] as? String {
            program = p
        } else {
            program = "—"
        }
        return (label, program, runAtLoad)
    }

    private static func run(_ args: [String]) -> String? { runWithStatus(args).1 }

    private static func runWithStatus(_ args: [String]) -> (Bool, String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: args[0])
        proc.arguments = Array(args.dropFirst())
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (proc.terminationStatus == 0, String(data: data, encoding: .utf8) ?? "")
        } catch { return (false, error.localizedDescription) }
    }

    struct RemoveResult { let removed: Int; let failed: Int; let restorePairs: [AppUninstallerService.RestorePair] }

    /// Moves the selected launch-item plists to the Trash (recoverable). System ones needing
    /// admin will fail the move; we report the count so the UI can tell the user to remove them
    /// manually rather than silently dropping them.
    static func remove(_ items: [LaunchItem]) -> RemoveResult {
        let outcome = TrashMover.move(items.map { ($0.url, Int64(0)) })
        return RemoveResult(removed: outcome.movedCount, failed: outcome.failedCount, restorePairs: outcome.restorePairs)
    }
}
