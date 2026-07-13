import Foundation
import UserNotifications

enum NotificationService {
    private static let categoryID = "diskaura.alert"

    /// Only prompts if the user has never decided — macOS remembers the decision per app
    /// identity, so re-asking every launch is both unnecessary and what makes permission
    /// prompts feel like they "never stop asking." Also registers an "Open DiskAura" action
    /// so notifications are actionable, not just informational.
    static func requestAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        let open = UNNotificationAction(identifier: "diskaura.open", title: "Open DiskAura", options: [.foreground])
        center.setNotificationCategories([UNNotificationCategory(identifier: categoryID, actions: [open],
                                                                 intentIdentifiers: [], options: [])])
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    /// The app logo shipped as a loose bundle resource so it can be turned into a file-URL
    /// notification attachment (asset-catalog images can't be attached — attachments need a URL).
    private static func logoAttachment() -> UNNotificationAttachment? {
        guard let url = Bundle.main.url(forResource: "notification-logo", withExtension: "png") else { return nil }
        return try? UNNotificationAttachment(identifier: "diskaura.logo", url: url, options: nil)
    }

    private static func post(id: String, title: String, subtitle: String?, body: String, critical: Bool = false) {
        let content = UNMutableNotificationContent()
        content.title = title
        if let subtitle { content.subtitle = subtitle }
        content.body = body
        content.sound = .default
        content.categoryIdentifier = categoryID
        content.interruptionLevel = critical ? .timeSensitive : .active
        if let attachment = logoAttachment() { content.attachments = [attachment] }
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "\(id)-\(Date().timeIntervalSince1970)", content: content, trigger: nil)
        )
    }

    static func postLowSpaceWarning(freeBytes: Int64) {
        post(id: "low-space",
             title: "Low disk space",
             subtitle: "\(freeBytes.formattedBytes) free",
             body: "Your startup disk is running low. Open DiskAura to scan for large files, duplicates and junk to reclaim space.",
             critical: true)
    }

    static func postScanGrowthAlert(deltaBytes: Int64, rootName: String) {
        post(id: "growth",
             title: "\(rootName) is growing",
             subtitle: "+\(deltaBytes.formattedBytes) since last scan",
             body: "This folder grew by \(deltaBytes.formattedBytes). Open DiskAura to see exactly what changed.")
    }

    /// Fired when the user trashes an app and it leaves caches/prefs behind — the "Sentinel" nudge.
    static func postAppRemovedLeftovers(appName: String, count: Int, bytes: Int64) {
        post(id: "leftovers",
             title: "\(appName) left \(bytes.formattedBytes) behind",
             subtitle: "\(count) leftover file\(count == 1 ? "" : "s")",
             body: "You removed \(appName), but its caches and preferences are still on disk. Open DiskAura's Uninstaller to clean them up.")
    }

    /// Fired after automatic maintenance moved junk to the Trash — reassures the user it ran and
    /// reminds them it's recoverable.
    static func postAutoClean(freedBytes: Int64, count: Int) {
        post(id: "autoclean",
             title: "Auto-clean freed \(freedBytes.formattedBytes)",
             subtitle: "\(count) item\(count == 1 ? "" : "s") moved to Trash",
             body: "DiskAura tidied up self-regenerating junk automatically. It's in the Trash — recoverable from Recovery until you empty it.")
    }

    /// Fired after a scheduled scan finds a meaningful amount of removable junk — turns the
    /// background scan into an actionable nudge instead of a silent snapshot.
    static func postCleanupOpportunity(junkBytes: Int64) {
        post(id: "cleanup",
             title: "\(junkBytes.formattedBytes) of junk to clean",
             subtitle: "Caches, logs & developer junk",
             body: "DiskAura found \(junkBytes.formattedBytes) of safely-removable junk. Open Cleanup to review and reclaim it.")
    }
}
