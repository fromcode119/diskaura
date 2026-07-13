import Foundation

/// Turns a passive "big/old files" list into GUIDANCE: for each file it estimates how safe it is
/// to remove and WHY, so the user isn't left guessing. Purely heuristic and local — it reads the
/// file's location, type, age and size, never its contents. The reason string is what makes the
/// score trustworthy ("Installer in Downloads, 8 months old").
enum CleanupAdvisor {
    enum Level: String {
        case safe = "Safe to remove"
        case review = "Review"
        case caution = "Keep unless sure"
    }

    struct Advice {
        let score: Int          // 0–100, higher = safer to remove
        let level: Level
        let reason: String
    }

    private static let installerExtensions: Set<String> = ["dmg", "pkg", "iso", "app"]
    private static let archiveExtensions: Set<String> = ["zip", "rar", "7z", "tar", "gz", "bz2"]
    private static let regenerableExtensions: Set<String> = ["log", "tmp", "cache", "crash"]
    private static let preciousExtensions: Set<String> = [
        "sketch", "psd", "ai", "key", "pages", "numbers", "docx", "xlsx", "pptx", "sql",
    ]

    static func advise(for node: FileNode) -> Advice {
        var score = 50
        var reasons: [String] = []
        let ext = node.url.pathExtension.lowercased()
        let path = node.url.path
        let inDownloads = path.contains("/Downloads/")
        let underDocsOrDesktop = path.contains("/Documents/") || path.contains("/Desktop/")

        // Location — Downloads is a transient staging area; Documents/Desktop are curated.
        if inDownloads { score += 20; reasons.append("in Downloads") }
        else if underDocsOrDesktop { score -= 20; reasons.append("in Documents/Desktop") }

        // Type — installers/archives are usually disposable once used; source files are precious.
        if installerExtensions.contains(ext) { score += 20; reasons.append("installer") }
        else if archiveExtensions.contains(ext) { score += 10; reasons.append("archive") }
        else if regenerableExtensions.contains(ext) { score += 25; reasons.append("regenerable file") }
        else if preciousExtensions.contains(ext) { score -= 25; reasons.append("editable document") }

        // Age — stale files are safer; the older, the safer.
        if let months = monthsOld(node.modifiedAt) {
            if months >= 12 { score += 20; reasons.append("\(months / 12)y+ old") }
            else if months >= 6 { score += 12; reasons.append("\(months) months old") }
            else if months <= 1 { score -= 12; reasons.append("recent") }
        }

        score = max(0, min(100, score))
        let level: Level = score >= 70 ? .safe : (score >= 45 ? .review : .caution)
        let reason = reasons.isEmpty ? "No strong signal" : reasons.joined(separator: ", ").capitalizedFirst
        return Advice(score: score, level: level, reason: reason)
    }

    private static func monthsOld(_ date: Date?) -> Int? {
        guard let date else { return nil }
        let seconds = Date().timeIntervalSince(date)
        guard seconds > 0 else { return 0 }
        return Int(seconds / (30 * 24 * 3600))
    }
}

private extension String {
    var capitalizedFirst: String { isEmpty ? self : prefix(1).uppercased() + dropFirst() }
}
