import Foundation

struct TMSnapshot: Identifiable {
    var id: String { name }
    let name: String       // com.apple.TimeMachine.2024-06-10-120000.local
    let dateToken: String  // 2024-06-10-120000  (what `tmutil deletelocalsnapshots` wants)
    let date: Date?
}

/// Surfaces APFS Time Machine LOCAL snapshots — the #1 reason "I deleted files but free space
/// didn't come back." macOS keeps hourly local snapshots that pin the on-disk blocks of files
/// you delete, so the space stays "purgeable" until the snapshots are thinned. DaisyDisk and
/// CleanMyMac both surface this; we list them and can delete them via `tmutil`.
enum TimeMachineSnapshotService {
    /// Lists local snapshots of the boot volume via `tmutil listlocalsnapshots /`.
    static func list() -> [TMSnapshot] {
        guard let out = run(["/usr/bin/tmutil", "listlocalsnapshots", "/"]) else { return [] }
        return out
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { $0.contains("com.apple.TimeMachine.") }
            .compactMap { line in
                // Token is the date between the prefix and the trailing ".local".
                let token = line
                    .replacingOccurrences(of: "com.apple.TimeMachine.", with: "")
                    .replacingOccurrences(of: ".local", with: "")
                return TMSnapshot(name: line, dateToken: token, date: parseDate(token))
            }
    }

    struct DeleteResult { let deleted: Int; let failed: Int; let needsPrivileges: Bool }

    /// Deletes the given local snapshots. On modern macOS, deleting a specific local snapshot
    /// of the boot volume works for the logged-in admin without sudo; if the OS refuses, we
    /// report `needsPrivileges` so the UI can tell the user to run it from Terminal rather than
    /// silently failing.
    static func delete(_ snapshots: [TMSnapshot]) -> DeleteResult {
        var deleted = 0, failed = 0, privilege = false
        for snap in snapshots {
            let (ok, output) = runWithStatus(["/usr/bin/tmutil", "deletelocalsnapshots", snap.dateToken])
            if ok { deleted += 1 }
            else {
                failed += 1
                if output.lowercased().contains("privile") || output.lowercased().contains("not permitted") || output.lowercased().contains("operation not permitted") {
                    privilege = true
                }
            }
        }
        return DeleteResult(deleted: deleted, failed: failed, needsPrivileges: privilege)
    }

    private static func parseDate(_ token: String) -> Date? {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd-HHmmss"
        fmt.timeZone = TimeZone.current
        return fmt.date(from: token)
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
            let text = String(data: data, encoding: .utf8) ?? ""
            return (proc.terminationStatus == 0, text)
        } catch {
            return (false, error.localizedDescription)
        }
    }
}
