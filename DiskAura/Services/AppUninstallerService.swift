import Foundation
import CoreServices
import AppKit

/// Lists installed apps in /Applications and, for a chosen app, finds leftover
/// data across the common per-app data locations by matching bundle identifier
/// or app name — the CleanMyMac "app leftovers" feature.
enum AppUninstallerService {
    /// Everywhere an app commonly scatters files — user AND system domains. A shallow
    /// `~/Library`-only search misses the bulk of what a real uninstall must remove
    /// (LaunchAgents/Daemons, group containers, privileged helpers, audio plug-ins,
    /// package receipts), which is why "uninstalling" left tons behind.
    private static let leftoverRoots: [String] = [
        "~/Library/Application Support",
        "~/Library/Caches",
        "~/Library/Preferences",
        "~/Library/Containers",
        "~/Library/Group Containers",
        "~/Library/Saved Application State",
        "~/Library/HTTPStorages",
        "~/Library/WebKit",
        "~/Library/Logs",
        "~/Library/Cookies",
        "~/Library/Application Scripts",
        "~/Library/LaunchAgents",
        "~/Library/Caches/com.apple.helpd",
        "/Library/Application Support",
        "/Library/Caches",
        "/Library/Preferences",
        "/Library/LaunchAgents",
        "/Library/LaunchDaemons",
        "/Library/PrivilegedHelperTools",
        "/Library/Logs",
        "/Library/Extensions",
        "/Library/Audio/Plug-Ins/HAL",
        "/var/db/receipts",
        // Additional app-leftover locations (plug-ins, prefpanes, screensavers, quicklook,
        // spotlight importers, services, input methods, mail bundles) — where apps commonly
        // scatter components that a basic "drag to Trash" leaves behind.
        "~/Library/Internet Plug-Ins",
        "~/Library/PreferencePanes",
        "~/Library/Screen Savers",
        "~/Library/QuickLook",
        "~/Library/Spotlight",
        "~/Library/Services",
        "~/Library/Input Methods",
        "~/Library/Mail/Bundles",
        "~/Library/Application Support/CrashReporter",
        "/Library/Internet Plug-Ins",
        "/Library/PreferencePanes",
        "/Library/QuickLook",
        "/Library/Spotlight",
        "/Library/Services",
    ]

    /// Fast listing: bundle names/IDs only, no recursive size scan. Computing every app's
    /// on-disk size (directorySize) up front is what made the Uninstaller sit on a blank
    /// spinner for a long time before showing a single row — this returns instantly so the
    /// list can render right away, with sizes filled in afterward via `appSizeBytes(for:)`.
    static func listInstalledApps() -> [InstalledApp] {
        let fm = FileManager.default
        // Both the system-wide and per-user Applications folders — many apps (and drag-installed
        // ones) live under ~/Applications, which the old /Applications-only scan missed entirely.
        let roots = [URL(fileURLWithPath: "/Applications"),
                     fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        let entries = roots.flatMap { root in
            (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        }

        return entries
            .filter { $0.pathExtension == "app" }
            .map { url in
                let bundle = Bundle(url: url)
                let name = (bundle?.infoDictionary?["CFBundleName"] as? String) ?? url.deletingPathExtension().lastPathComponent
                // lastUsedDate is a Spotlight (MDItem) lookup — doing it synchronously per app
                // here made the whole list wait behind dozens of metadata queries. Filled in
                // by the async pass instead so rows appear instantly.
                return InstalledApp(
                    bundlePath: url.path,
                    name: name,
                    bundleIdentifier: bundle?.bundleIdentifier,
                    appSizeBytes: -1,
                    lastUsedDate: nil
                )
            }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    /// Spotlight's kMDItemLastUsedDate — the timestamp LaunchServices stamps every time the
    /// app is opened. Cheap MDItem lookup, no NSMetadataQuery needed for a known path.
    static func lastUsedDate(for path: String) -> Date? {
        guard let item = MDItemCreate(nil, path as CFString) else { return nil }
        guard let value = MDItemCopyAttribute(item, kMDItemLastUsedDate) else { return nil }
        return (value as? Date)
    }

    static func appSizeBytes(for app: InstalledApp) -> Int64 {
        directorySize(at: URL(fileURLWithPath: app.bundlePath))
    }

    /// Match tokens derived from the bundle id + app name. e.g. Zoom (us.zoom.xos) yields
    /// "us.zoom.xos", the vendor prefix "us.zoom" (catches us.zoom.xos.*), and "zoom" — so
    /// preference plists, group containers and audio plug-ins all get found.
    /// Vendor prefixes that are FAR too broad to match on — "com.apple" alone matches nearly
    /// every file in ~/Library, which is what made scanning Safari surface "millions of things"
    /// and hang. We never uninstall these vendors' system apps anyway.
    private static let bannedVendorPrefixes: Set<String> = ["com.apple", "com.microsoft"]

    static func matchNeedles(for app: InstalledApp) -> [String] {
        var needles = Set<String>()
        if let id = app.bundleIdentifier?.lowercased(), !id.isEmpty {
            needles.insert(id)
            let parts = id.split(separator: ".")
            if parts.count >= 2 {
                let vendor = parts.prefix(2).joined(separator: ".")
                if !bannedVendorPrefixes.contains(vendor) { needles.insert(vendor) } // vendor prefix
            }
        }
        let name = app.name.lowercased().replacingOccurrences(of: " ", with: "")
        if name.count >= 4 { needles.insert(name) }
        return Array(needles)
    }

    /// Finds leftovers across user + system domains by matching any of the derived needles.
    /// System (Apple) apps are skipped entirely — their files are the OS, not removable cruft.
    /// Results are capped so a pathologically broad match can never enumerate the whole disk.
    static func findLeftovers(for app: InstalledApp, limit: Int = 300) -> [LeftoverItem] {
        guard !app.isSystemApp else { return [] }
        let fm = FileManager.default
        let needles = matchNeedles(for: app)
        guard !needles.isEmpty else { return [] }
        var seen = Set<String>()
        var results: [LeftoverItem] = []

        outer: for root in leftoverRoots {
            let expanded = (root as NSString).expandingTildeInPath
            guard let entries = try? fm.contentsOfDirectory(atPath: expanded) else { continue }
            let locationLabel = (expanded as NSString).lastPathComponent
            let isSystem = expanded.hasPrefix("/Library") || expanded.hasPrefix("/var") || expanded.hasPrefix("/private/var")

            for entry in entries {
                let entryLower = entry.lowercased()
                guard needles.contains(where: { entryLower.contains($0) }) else { continue }
                let fullPath = (expanded as NSString).appendingPathComponent(entry)
                guard !seen.contains(fullPath) else { continue }
                seen.insert(fullPath)
                let url = URL(fileURLWithPath: fullPath)
                let size = directorySize(at: url)
                results.append(LeftoverItem(url: url, sizeBytes: size,
                                            requiresAdmin: isSystem, location: locationLabel))
                if results.count >= limit { break outer }
            }
        }

        return results.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    struct UninstallResult {
        let trashedCount: Int
        let freedBytes: Int64
        /// Items that couldn't be moved to Trash (almost always system-level ones needing
        /// admin rights) — surfaced so the user knows exactly what to remove by hand.
        let failed: [LeftoverItem]
        /// original → in-Trash location pairs, so an Undo can move every item back exactly
        /// where it came from (a real restore, not just "open the Trash and hunt").
        let restorePairs: [RestorePair]
    }

    struct RestorePair {
        let original: URL
        let trashed: URL
    }

    /// Moves previously-trashed items back to their original locations. Returns how many were
    /// restored — a genuine one-click undo of an uninstall.
    @discardableResult
    static func restore(_ pairs: [RestorePair]) -> Int {
        let fm = FileManager.default
        var restored = 0
        for pair in pairs {
            // Don't clobber something that already reappeared at the origin.
            guard !fm.fileExists(atPath: pair.original.path) else { continue }
            if (try? fm.moveItem(at: pair.trashed, to: pair.original)) != nil { restored += 1 }
        }
        return restored
    }

    /// Actually uninstalls: quits the app if running, then moves the .app bundle and every
    /// selected leftover to the Trash (recoverable). Per-item so we can report exactly what
    /// couldn't be removed instead of failing the whole batch on one protected file.
    static func uninstall(app: InstalledApp, leftovers: [LeftoverItem]) -> UninstallResult {
        // Quit it first — a running app can hold files open and its .app can't be fully removed.
        // Wait briefly for it to actually exit so a user-owned app doesn't spuriously fail the
        // trash (which would trigger an unnecessary admin prompt in the escalation below).
        if let id = app.bundleIdentifier {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            running.forEach { $0.terminate() }
            var waited = 0.0
            while waited < 3.0,
                  !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty {
                Thread.sleep(forTimeInterval: 0.15); waited += 0.15
            }
        }

        let fm = FileManager.default
        let appItem = LeftoverItem(url: URL(fileURLWithPath: app.bundlePath),
                                   sizeBytes: max(app.appSizeBytes, 0), requiresAdmin: false, location: "Applications")
        var trashed = 0
        var freed: Int64 = 0
        var failed: [LeftoverItem] = []
        var restorePairs: [RestorePair] = []

        for item in [appItem] + leftovers {
            var resultURL: NSURL?
            do {
                try fm.trashItem(at: item.url, resultingItemURL: &resultURL)
                trashed += 1
                freed += max(item.sizeBytes, 0)
                if let dest = resultURL as URL? {
                    restorePairs.append(RestorePair(original: item.url, trashed: dest))
                }
            } catch {
                failed.append(item)
            }
        }

        // Many apps (Zoom, printer drivers, anything installed by a .pkg) live in /Applications
        // owned by root:wheel — FileManager can't trash those without admin rights, so they land in
        // `failed`. Rather than tell the user to do it by hand, escalate once with the standard
        // macOS admin prompt and move them to the Trash (still recoverable — not rm).
        if !failed.isEmpty {
            let movedPaths = escalatedTrash(failed.map { $0.url })
            var stillFailed: [LeftoverItem] = []
            for item in failed {
                if movedPaths.contains(item.url.standardizedFileURL.path) {
                    trashed += 1
                    freed += max(item.sizeBytes, 0)
                    // Restore-via-app would need admin too, so these are recoverable from the
                    // Trash's own "Put Back" rather than our Undo — no restore pair recorded.
                } else {
                    stillFailed.append(item)
                }
            }
            failed = stillFailed
        }

        return UninstallResult(trashedCount: trashed, freedBytes: freed,
                               failed: failed, restorePairs: restorePairs)
    }

    /// Moves root-owned items to the Trash using a single admin-authenticated shell command (one
    /// password prompt for the whole batch). Returns the source paths that were actually moved.
    /// Uses `mv` into ~/.Trash so it stays recoverable; never `rm`.
    private static func escalatedTrash(_ urls: [URL]) -> Set<String> {
        guard !urls.isEmpty else { return [] }
        let fm = FileManager.default
        let trash = fm.homeDirectoryForCurrentUser.appendingPathComponent(".Trash", isDirectory: true)
        var commands: [String] = []
        for url in urls {
            let dest = uniqueTrashDestination(for: url, trash: trash, fm: fm)
            commands.append("/bin/mv -f \(shellQuote(url.path)) \(shellQuote(dest.path))")
        }
        let shellCommand = commands.joined(separator: " && ")
        let appleScript = "do shell script \"\(escapeForAppleScript(shellCommand))\" with administrator privileges"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run(); process.waitUntilExit() } catch { return [] }
        guard process.terminationStatus == 0 else { return [] }   // cancelled or auth failed
        // Success = the source no longer exists.
        return Set(urls.filter { !fm.fileExists(atPath: $0.path) }.map { $0.standardizedFileURL.path })
    }

    private static func uniqueTrashDestination(for url: URL, trash: URL, fm: FileManager) -> URL {
        var candidate = trash.appendingPathComponent(url.lastPathComponent)
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        var i = 1
        while fm.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base) \(i)" : "\(base) \(i).\(ext)"
            candidate = trash.appendingPathComponent(name)
            i += 1
        }
        return candidate
    }

    private static func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func escapeForAppleScript(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func directorySize(at url: URL) -> Int64 {
        var statInfo = stat()
        guard lstat(url.path, &statInfo) == 0 else { return 0 }

        if (statInfo.st_mode & S_IFMT) != S_IFDIR {
            return Int64(statInfo.st_blocks) * 512
        }

        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            var s = stat()
            if lstat(fileURL.path, &s) == 0, (s.st_mode & S_IFMT) != S_IFLNK {
                total += Int64(s.st_blocks) * 512
            }
        }
        return total
    }
}
