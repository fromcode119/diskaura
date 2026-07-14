import Foundation

/// A plain, availability-free representation of a parsed tidy-up rule. Kept separate from the LLM's
/// `@Generable` type (which is macOS 26-only) so the matching/applying engine runs on any OS.
struct FileRule {
    let extensions: [String]
    let olderThanDays: Int
    let largerThanMB: Int
    let nameContains: String
    let action: String        // "move" | "trash"
    let destination: String
}

/// Finds the files in a folder that match a parsed rule, and applies the rule (move to a subfolder,
/// or send to Trash) — always reversibly (moves are recorded; trashing is recoverable). Only the
/// folder's OWN loose files are considered, never existing subfolders, so a rule can't recurse into
/// and scramble already-organized trees.
enum FileRuleEngine {
    struct Match: Identifiable {
        let url: URL
        let sizeBytes: Int64
        var id: String { url.path }
        var name: String { url.lastPathComponent }
    }

    /// The organize scheme a rule asked for, derived from the destination hint the model captured.
    static func organizeScheme(_ rule: FileRule) -> OrganizeScheme {
        let hint = rule.destination.lowercased()
        if hint.contains("topic") || hint.contains("ai") || hint.contains("smart") { return .byTopic }
        if hint.contains("date") || hint.contains("month") || hint.contains("year") { return .byTypeThenDate }
        return .byType
    }

    /// A human-readable summary of what the rule will do, for the confirmation UI.
    static func describe(_ rule: FileRule) -> String {
        if rule.action == "organize" {
            return "Organize this folder’s files — \(organizeScheme(rule).rawValue.lowercased())"
        }
        var parts: [String] = []
        if !rule.extensions.isEmpty { parts.append(rule.extensions.map { ".\($0)" }.joined(separator: "/")) }
        else { parts.append("all files") }
        if rule.olderThanDays > 0 { parts.append("older than \(rule.olderThanDays) days") }
        if rule.largerThanMB > 0 { parts.append("larger than \(rule.largerThanMB) MB") }
        if !rule.nameContains.isEmpty { parts.append("named like “\(rule.nameContains)”") }
        let target = rule.action == "trash" ? "→ Trash"
            : "→ \(rule.destination.isEmpty ? "a subfolder" : rule.destination)"
        return parts.joined(separator: ", ") + " \(target)"
    }

    /// Why a rule matched nothing: how many loose files are of the requested TYPE (ignoring the
    /// age/size/name filters), and how many loose files there are in total. Lets the UI say
    /// "found 21 PDFs, but none are older than 30 days" instead of a vague "no matches".
    struct Diagnosis { let typeMatches: Int; let total: Int }

    static func diagnose(for rule: FileRule, in folder: URL) -> Diagnosis {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return Diagnosis(typeMatches: 0, total: 0) }
        let wantedExt = Set(rule.extensions.map { $0.lowercased() })
        var typeMatches = 0
        var total = 0
        for url in entries {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true { continue }
            total += 1
            if wantedExt.isEmpty || wantedExt.contains(url.pathExtension.lowercased()) { typeMatches += 1 }
        }
        return Diagnosis(typeMatches: typeMatches, total: total)
    }

    static func matches(for rule: FileRule, in folder: URL) -> [Match] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]) else { return [] }

        let wantedExt = Set(rule.extensions.map { $0.lowercased() })
        let now = Date()
        return entries.compactMap { url -> Match? in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
            if values?.isDirectory == true { return nil }
            if !wantedExt.isEmpty, !wantedExt.contains(url.pathExtension.lowercased()) { return nil }
            let size = Int64(values?.fileSize ?? 0)
            if rule.largerThanMB > 0, size < Int64(rule.largerThanMB) * 1_048_576 { return nil }
            if rule.olderThanDays > 0 {
                guard let modified = values?.contentModificationDate,
                      now.timeIntervalSince(modified) >= Double(rule.olderThanDays) * 86_400 else { return nil }
            }
            if !rule.nameContains.isEmpty,
               !url.lastPathComponent.lowercased().contains(rule.nameContains.lowercased()) { return nil }
            return Match(url: url, sizeBytes: size)
        }
        .sorted { $0.sizeBytes > $1.sizeBytes }
    }

    struct ApplyResult {
        let affected: Int
        let movedPairs: [(from: URL, to: URL)]
        let trashRestorePairs: [AppUninstallerService.RestorePair]
        let trashed: Bool
    }

    /// Executes the rule on the matches. Move → into `destination` subfolder of the folder; trash →
    /// recoverable Trash. Returns the pairs so the caller can record an Undo entry.
    static func apply(_ rule: FileRule, matches: [Match], in folder: URL) -> ApplyResult {
        let fm = FileManager.default
        if rule.action == "trash" {
            let outcome = TrashMover.move(matches.map { ($0.url, $0.sizeBytes) })
            return ApplyResult(affected: outcome.movedCount, movedPairs: [],
                               trashRestorePairs: outcome.restorePairs, trashed: true)
        }
        let dest = folder.appendingPathComponent(rule.destination.isEmpty ? "Sorted" : rule.destination, isDirectory: true)
        var moved: [(from: URL, to: URL)] = []
        for match in matches {
            do {
                try fm.createDirectory(at: dest, withIntermediateDirectories: true)
                let target = uniqueDestination(dest.appendingPathComponent(match.name), fm: fm)
                try fm.moveItem(at: match.url, to: target)
                moved.append((from: match.url, to: target))
            } catch { continue }
        }
        return ApplyResult(affected: moved.count, movedPairs: moved, trashRestorePairs: [], trashed: false)
    }

    private static func uniqueDestination(_ url: URL, fm: FileManager) -> URL {
        guard fm.fileExists(atPath: url.path) else { return url }
        let dir = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        var i = 1
        while true {
            let name = ext.isEmpty ? "\(base)-\(i)" : "\(base)-\(i).\(ext)"
            let candidate = dir.appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            i += 1
        }
    }
}
