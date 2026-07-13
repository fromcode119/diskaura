import Foundation

enum ThreatSeverity: Int, Comparable {
    case low = 0, medium = 1, high = 2
    static func < (a: ThreatSeverity, b: ThreatSeverity) -> Bool { a.rawValue < b.rawValue }
    var label: String { self == .high ? "High" : self == .medium ? "Medium" : "Low" }
}

struct Threat: Identifiable {
    let id: String
    let name: String
    let detail: String
    let path: URL
    let severity: ThreatSeverity
}

/// On-device adware / suspicious-launch-item scanner. It is NOT a full antivirus — it matches
/// launch agents & daemons against a curated list of documented macOS adware/PUP families and a
/// set of heuristics (scripts that curl|bash, run from /tmp or /Users/Shared, point at a missing
/// binary). Everything is quarantined to the Trash (recoverable), never hard-deleted, and the
/// scan is entirely local — no cloud lookups.
enum ProtectionService {
    /// Documented macOS adware / PUP family tokens (lowercased). Matched against a launch item's
    /// label, program path and arguments.
    private static let knownAdware: [String] = [
        "genieo", "installmac", "vsearch", "conduit", "trovi", "mackeeper", "spigot",
        "pirrit", "mughthesec", "advancedmaccleaner", "macautofixer", "search-quick",
        "chill-tab", "searchmine", "geneio", "omnitab", "safefinder", "mymacupdater",
        "maconpc", "cleanupmymac", "weknow", "bundlore", "adload", "shlayer", "crossrider",
    ]

    /// Suspicious tokens in a launch item's arguments that indicate a script-based dropper.
    private static let suspiciousArgTokens = ["curl ", "| sh", "|sh", "| bash", "|bash",
                                              "base64", "/tmp/", "/users/shared/", "wget ", "eval "]

    static func scan() -> [Threat] {
        var threats: [Threat] = []
        for dir in launchItemDirectories() {
            let plists = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
                .filter { $0.pathExtension == "plist" } ?? []
            for plist in plists {
                if let t = evaluate(plist) { threats.append(t) }
            }
        }
        return threats.sorted { $0.severity > $1.severity }
    }

    /// Moves each threat's launch-item file to the Trash (so it won't load again at login) —
    /// recoverable. Returns how many were quarantined.
    static func quarantine(_ threats: [Threat]) -> Int {
        var removed = 0
        for threat in threats {
            do { try FileManager.default.trashItem(at: threat.path, resultingItemURL: nil); removed += 1 }
            catch { continue }
        }
        return removed
    }

    // MARK: - Evaluation

    private static func launchItemDirectories() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("Library/LaunchAgents"),
            URL(fileURLWithPath: "/Library/LaunchAgents"),
            URL(fileURLWithPath: "/Library/LaunchDaemons"),
        ]
    }

    private static func evaluate(_ plist: URL) -> Threat? {
        guard let dict = NSDictionary(contentsOf: plist) as? [String: Any] else { return nil }
        let label = (dict["Label"] as? String ?? plist.lastPathComponent)
        let program = dict["Program"] as? String
        let args = (dict["ProgramArguments"] as? [String]) ?? []
        let haystack = ([label, program].compactMap { $0 } + args).joined(separator: " ").lowercased()

        // 1. Known adware family → high severity.
        if let family = knownAdware.first(where: { haystack.contains($0) }) {
            return Threat(id: plist.path, name: "Known adware: \(family)",
                          detail: "Launch item “\(label)” matches the \(family) adware family.",
                          path: plist, severity: .high)
        }
        // 2. Script-dropper heuristics → medium.
        if suspiciousArgTokens.contains(where: { haystack.contains($0) }) {
            return Threat(id: plist.path, name: "Suspicious launch item",
                          detail: "“\(label)” runs a script that looks like a dropper (downloads or executes code).",
                          path: plist, severity: .medium)
        }
        // 3. Points at a missing executable → low (orphaned/hijack candidate).
        if let exe = program ?? args.first, exe.hasPrefix("/"),
           !FileManager.default.fileExists(atPath: exe) {
            return Threat(id: plist.path, name: "Broken launch item",
                          detail: "“\(label)” points at a program that no longer exists (\(exe)).",
                          path: plist, severity: .low)
        }
        return nil
    }
}
