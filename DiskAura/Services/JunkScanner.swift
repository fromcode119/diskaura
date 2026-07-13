import Foundation

/// Scans well-known, safe-to-clean locations and groups what it finds into categories —
/// the CleanMyMac "System Junk / Cleanup" feature. Everything here regenerates on demand
/// (caches, logs) or is already discarded (Trash), so cleaning it is low-risk; it's all
/// moved to Trash (recoverable), never hard-deleted. Nothing outside the user's own
/// Library is touched, and system-protected paths are simply skipped when unreadable.
enum JunkScanner {
    /// A category definition: where to look and how to describe it.
    private struct Source {
        let id: String
        let title: String
        let icon: String
        let explanation: String
        let recommended: Bool
        let roots: [String]        // tilde-expandable directories whose CHILDREN are the items
    }

    private static let sources: [Source] = [
        Source(id: "user-caches", title: "User Caches", icon: "shippingbox.fill",
               explanation: "App cache files. Safe to remove — apps rebuild them as needed.",
               recommended: true, roots: ["~/Library/Caches"]),
        Source(id: "logs", title: "Logs", icon: "doc.text.fill",
               explanation: "Diagnostic logs left by apps and the system.",
               recommended: true, roots: ["~/Library/Logs"]),
        Source(id: "xcode", title: "Xcode & Simulator Junk", icon: "hammer.fill",
               explanation: "Derived data, old device support and simulator caches — Xcode regenerates these.",
               recommended: true, roots: [
                "~/Library/Developer/Xcode/DerivedData",
                "~/Library/Developer/Xcode/iOS DeviceSupport",
                "~/Library/Developer/CoreSimulator/Caches",
               ]),
        // Package-manager / build caches — the single biggest reclaimable category on a dev
        // Mac (research-backed: 50–150GB across a dev's projects). Every one of these is a
        // download/build cache that its tool re-creates on demand, so removal is safe. Left
        // OFF by default (dev-specific); the per-item checkboxes let you keep any you want.
        // Non-existent roots are skipped automatically, so listing many tools is harmless.
        // NOTE: iOS *simulator runtimes* are deliberately NOT here — those are read-only DMG
        // mounts under CoreSimulator and must be removed via `xcrun simctl delete unavailable`,
        // never by trashing files, so we don't offer to delete them unsafely.
        Source(id: "dev-caches", title: "Developer Caches", icon: "terminal.fill",
               explanation: "Package-manager & build caches (npm, pnpm, Yarn, Gradle, Maven, Cargo, Go, Bun, .NET, Composer, Dart…) — all re-downloaded on demand.",
               recommended: false, roots: [
                // JS / Node ecosystem
                "~/.npm/_cacache",
                "~/.yarn/cache",
                "~/.yarn/berry/cache",
                "~/Library/pnpm/store",
                "~/.pnpm-store",
                "~/.bun/install/cache",
                "~/.deno",
                "~/.node-gyp",
                "~/.electron-gyp",
                // JVM ecosystem
                "~/.gradle/caches",
                "~/.m2/repository",
                "~/.ivy2/cache",
                // Rust
                "~/.cargo/registry/cache",
                "~/.cargo/registry/src",
                "~/.rustup/downloads",
                // Go
                "~/go/pkg/mod",
                // .NET / PHP / Dart / Ruby / Python
                "~/.nuget/packages",
                "~/.composer/cache",
                "~/.pub-cache",
                "~/.gem",
                // Apple / CocoaPods spec repos (re-cloneable)
                "~/.cocoapods/repos",
               ]),
        // The XDG cache home — by convention EVERYTHING under ~/.cache is disposable and
        // regenerated on demand (go-build, pip, Puppeteer/Playwright browsers, Hugging Face
        // model downloads, etc.). Often the single biggest reclaimable folder on a dev Mac.
        // OFF by default and per-item selectable so you can keep e.g. large ML model caches.
        Source(id: "cache-home", title: "App Cache Home (~/.cache)", icon: "externaldrive.fill",
               explanation: "The ~/.cache folder — disposable caches many CLI tools keep here (build caches, headless browsers, downloaded ML models). Regenerated on demand.",
               recommended: false, roots: ["~/.cache"]),
        Source(id: "crash-reports", title: "Crash Reports & Diagnostics", icon: "exclamationmark.triangle.fill",
               explanation: "Crash logs and diagnostic reports left by apps and the system.",
               recommended: true, roots: [
                "~/Library/Logs/DiagnosticReports",
                "~/Library/Application Support/CrashReporter",
               ]),
        Source(id: "saved-state", title: "Saved Application State", icon: "arrow.uturn.backward",
               explanation: "Window/position snapshots apps use to reopen where you left off.",
               recommended: false, roots: ["~/Library/Saved Application State"]),
        Source(id: "ios-backups", title: "iOS Device Backups", icon: "iphone",
               explanation: "Backups of iPhones/iPads — can be large. NOT deleted by default; review first.",
               recommended: false, roots: ["~/Library/Application Support/MobileSync/Backup"]),
        Source(id: "ios-updates", title: "iOS Software Updates", icon: "arrow.triangle.2.circlepath",
               explanation: "Downloaded iOS/iPadOS update images — re-downloaded when needed.",
               recommended: true, roots: [
                "~/Library/iTunes/iPhone Software Updates",
                "~/Library/iTunes/iPad Software Updates",
               ]),
        Source(id: "downloads-installers", title: "Old Installers", icon: "arrow.down.circle.fill",
               explanation: "Disk images and archives sitting in Downloads — usually safe once installed.",
               recommended: false, roots: ["~/Downloads"]),
        // Heavy, recreatable dev artefacts that are NOT caches — deleting them doesn't harm
        // macOS, but you lose real state you'd have to rebuild: simulator/emulator devices and
        // shipped app archives (dSYMs). OFF by default, per-item selectable, and flagged as
        // "review" so nobody trashes an emulator or an archive by accident.
        Source(id: "dev-heavy", title: "Emulators, Simulators & Archives", icon: "cube.box.fill",
               explanation: "Xcode Archives (old builds/dSYMs), iOS Simulator devices and Android emulators. Safe for your Mac, but you'll have to recreate anything you delete — review before cleaning.",
               recommended: false, roots: [
                "~/Library/Developer/Xcode/Archives",
                "~/Library/Developer/CoreSimulator/Devices",
                "~/.android/avd",
               ]),
    ]

    private static let installerExtensions: Set<String> = ["dmg", "pkg", "zip", "iso"]

    static func scan(exclusions: ExclusionMatcher = ExclusionMatcher(paths: []),
                     isCancelled: @escaping () -> Bool = { false }) -> [JunkCategory] {
        var categories: [JunkCategory] = []
        let fm = FileManager.default

        for source in sources {
            if isCancelled() { break }
            var items: [JunkItem] = []
            for root in source.roots {
                let expanded = (root as NSString).expandingTildeInPath
                guard let entries = try? fm.contentsOfDirectory(atPath: expanded) else { continue }
                for entry in entries {
                    if isCancelled() { break }
                    if entry.hasPrefix(".") { continue }
                    let path = (expanded as NSString).appendingPathComponent(entry)
                    let url = URL(fileURLWithPath: path)
                    if exclusions.isExcluded(url) { continue }
                    // The "Old Installers" category is file-type filtered; the rest take every child.
                    if source.id == "downloads-installers",
                       !installerExtensions.contains(url.pathExtension.lowercased()) { continue }
                    let size = directorySize(at: url)
                    if size > 0 { items.append(JunkItem(url: url, sizeBytes: size)) }
                }
            }
            items.sort { $0.sizeBytes > $1.sizeBytes }
            categories.append(JunkCategory(
                id: source.id, title: source.title, icon: source.icon,
                explanation: source.explanation, items: items, recommended: source.recommended
            ))
        }

        // Trash as its own category (uses the existing TrashService total). Skipped when the
        // scan was cancelled so a cancelled scan returns nothing rather than a lone Trash row.
        let trashBytes = isCancelled() ? 0 : TrashService.size()
        if trashBytes > 0 {
            let trashItem = JunkItem(url: TrashService.trashURL, sizeBytes: trashBytes)
            categories.insert(JunkCategory(
                id: "trash", title: "Trash", icon: "trash.fill",
                explanation: "Items already in the Trash — emptying frees the space for good.",
                items: [trashItem], recommended: true
            ), at: 0)
        }

        return categories.filter { !$0.isEmpty }
    }

    private static func directorySize(at url: URL) -> Int64 {
        var statInfo = stat()
        guard lstat(url.path, &statInfo) == 0 else { return 0 }
        if (statInfo.st_mode & S_IFMT) != S_IFDIR {
            return Int64(statInfo.st_blocks) * 512
        }
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: nil, options: [.skipsPackageDescendants]
        ) else { return 0 }
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
