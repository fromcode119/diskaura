import Foundation

struct LeftoverItem: Identifiable {
    var id: String { url.path }
    let url: URL
    let sizeBytes: Int64
    /// System-level items (/Library, /var, PrivilegedHelperTools, LaunchDaemons) can't be
    /// moved to Trash without admin rights, so the UI flags them for manual removal.
    var requiresAdmin: Bool = false
    /// A short label for where this lives ("Caches", "LaunchAgents", …) — helps the user
    /// judge what each leftover is.
    var location: String = ""
}

struct InstalledApp: Identifiable {
    var id: String { bundlePath }
    let bundlePath: String
    let name: String
    let bundleIdentifier: String?
    var appSizeBytes: Int64
    /// Last time the app was launched (Spotlight's kMDItemLastUsedDate). nil if never
    /// recorded / not indexed. Drives the "Unused" filter and the "last opened" label.
    var lastUsedDate: Date?
    var leftovers: [LeftoverItem] = []

    var totalLeftoverBytes: Int64 {
        leftovers.reduce(0) { $0 + $1.sizeBytes }
    }

    /// Apple's BUILT-IN apps (Safari, Mail, Photos, …) can't be uninstalled and their files
    /// must never be swept as "leftovers" — the com.apple.* files ARE the system. But several
    /// Apple apps ARE removable (Xcode, iWork, GarageBand, iMovie) — those are allow-listed so
    /// the uninstaller still works on them.
    private static let removableAppleApps: Set<String> = [
        "com.apple.dt.xcode", "com.apple.iwork.pages", "com.apple.iwork.numbers",
        "com.apple.iwork.keynote", "com.apple.garageband10", "com.apple.imovieapp",
        "com.apple.podcasts", "com.apple.shortcuts",
    ]
    var isSystemApp: Bool {
        if bundlePath.hasPrefix("/System/") { return true }
        if let id = bundleIdentifier?.lowercased() {
            if Self.removableAppleApps.contains(id) { return false }
            if id.hasPrefix("com.apple.") { return true }
        }
        return false
    }

    /// True only when we KNOW it hasn't been opened in 6+ months. A missing last-used date
    /// means "unknown", NOT "unused" — Spotlight simply doesn't record it for some apps
    /// (notably Apple's), so treating nil as unused wrongly flagged apps you use daily.
    var isUnused: Bool {
        guard let lastUsedDate else { return false }
        return lastUsedDate < Calendar.current.date(byAdding: .month, value: -6, to: Date())!
    }

    var lastUsedDescription: String {
        guard let lastUsedDate else { return "Last use unknown" }
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .full
        return "Opened " + fmt.localizedString(for: lastUsedDate, relativeTo: Date())
    }
}
