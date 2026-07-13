import Foundation

/// How to lay out an in-place organize. Unlike Move (which sends files to another folder),
/// Organize tidies a folder's OWN loose files into subfolders — and can build a multi-level
/// tree (e.g. Images/2024-06/, Documents/Invoices/), not just one flat level.
enum OrganizeScheme: String, CaseIterable, Identifiable {
    case byType = "By type"
    case byTypeThenDate = "By type, then month"
    case byTypeThenTopic = "By type, then topic (AI)"
    case byTopic = "By topic (AI)"

    var id: String { rawValue }

    var detail: String {
        switch self {
        case .byType: return "Images / Documents / Videos / … one level."
        case .byTypeThenDate: return "Images / 2024-06 / … — nested by last-modified month."
        case .byTypeThenTopic: return "Documents / Invoices / … — nested by on-device AI topic."
        case .byTopic: return "Invoices / Vacation / … — grouped by meaning, on-device."
        }
    }

    /// True when this scheme produces a nested folder tree rather than a single level.
    var isNested: Bool { self == .byTypeThenDate || self == .byTypeThenTopic }

    /// True when the scheme reads file content/metadata on-device (Vision + EXIF) rather than
    /// just names — used to show an honest "Reading files…" label while it works.
    var usesAI: Bool { self == .byTopic || self == .byTypeThenTopic }
}

/// A planned destination for one file — the relative folder path components + the file.
struct OrganizePlanItem: Identifiable {
    var id: String { file.path }
    let file: URL
    let sizeBytes: Int64
    let folderComponents: [String]   // e.g. ["Images", "2024-06"]
    var folderPath: String { folderComponents.joined(separator: "/") }
}

enum OrganizeService {
    /// Builds the plan WITHOUT moving anything — the UI shows this so the user sees the exact
    /// tree that will be created before committing. Only the folder's own loose files are
    /// organized; existing subfolders are left untouched.
    static func plan(for folder: URL, scheme: OrganizeScheme) -> [OrganizePlanItem] {
        let files = looseFiles(in: folder)
        guard !files.isEmpty else { return [] }

        // Sync topic pass (name-meaning + Vision content) — used when the on-device LLM path
        // isn't taken. See planAsync for the LLM-backed version.
        var topicForPath: [String: String] = [:]
        if scheme.usesAI {
            let nodes = fileNodes(files)
            if scheme == .byTopic {
                for group in SmartOrganizer.groups(for: nodes) {
                    for f in group.files { topicForPath[f.path] = group.name }
                }
            } else {
                let byType = Dictionary(grouping: nodes) { MoveService.category(for: $0.url) }
                for (_, typeNodes) in byType {
                    for group in SmartOrganizer.groups(for: typeNodes) {
                        for f in group.files { topicForPath[f.path] = group.name }
                    }
                }
            }
        }
        return mapItems(files, scheme: scheme, topicForPath: topicForPath)
    }

    /// LLM-backed plan: for the AI schemes it names folders with the on-device model (macOS 26+),
    /// falling back to the sync `plan` when the model isn't available. Non-AI schemes just defer
    /// to the sync plan. `progress` reports (done, total) while the model works.
    static func planAsync(for folder: URL, scheme: OrganizeScheme,
                          progress: (@Sendable (Int, Int) -> Void)? = nil) async -> [OrganizePlanItem] {
        guard scheme.usesAI, #available(macOS 26.0, *), FolderNamingService.isAvailable else {
            return plan(for: folder, scheme: scheme)
        }
        let files = looseFiles(in: folder)
        guard !files.isEmpty else { return [] }
        let nodes = fileNodes(files)

        var topicForPath: [String: String] = [:]
        if scheme == .byTopic {
            let outcome = await AIFolderOrganizer.organize(nodes, progress: progress)
            for g in outcome.groups { for f in g.files { topicForPath[f.path] = g.name } }
        } else {
            // Topic within each type — Documents cluster separately from Images.
            let byType = Dictionary(grouping: nodes) { MoveService.category(for: $0.url) }
            for (_, typeNodes) in byType {
                let outcome = await AIFolderOrganizer.organize(typeNodes)
                for g in outcome.groups { for f in g.files { topicForPath[f.path] = g.name } }
            }
        }
        return mapItems(files, scheme: scheme, topicForPath: topicForPath)
    }

    /// Builds an organize plan for a SPECIFIC set of files (e.g. the files a Smart Rule matched),
    /// rather than every loose file in the folder. Same scheme logic as `plan` — byType is instant,
    /// byTopic uses the on-device AI when available.
    static func planForFiles(_ urls: [URL], scheme: OrganizeScheme, in folder: URL) async -> [OrganizePlanItem] {
        guard !urls.isEmpty else { return [] }
        var topicForPath: [String: String] = [:]
        if scheme.usesAI {
            let nodes = fileNodes(urls)
            if #available(macOS 26.0, *), FolderNamingService.isAvailable {
                let outcome = await AIFolderOrganizer.organize(nodes)
                for group in outcome.groups { for f in group.files { topicForPath[f.path] = group.name } }
            } else {
                for group in SmartOrganizer.groups(for: nodes) {
                    for f in group.files { topicForPath[f.path] = group.name }
                }
            }
        }
        return mapItems(urls, scheme: scheme, topicForPath: topicForPath)
    }

    // MARK: - Shared building blocks

    /// Loose files directly in the folder — existing subfolders are never reorganized.
    private static func looseFiles(in folder: URL) -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == false }
    }

    /// Splits a "/"-separated topic path into folder levels, or nil when there's no usable path.
    private static func pathComponents(_ path: String?) -> [String]? {
        guard let path else { return nil }
        let parts = path.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts
    }

    private static func fileNodes(_ files: [URL]) -> [FileNode] {
        files.map { url in
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return FileNode(url: url, isDirectory: false,
                            sizeBytes: Int64(values?.fileSize ?? 0),
                            modifiedAt: values?.contentModificationDate)
        }
    }

    private static func mapItems(_ files: [URL], scheme: OrganizeScheme,
                                 topicForPath: [String: String]) -> [OrganizePlanItem] {
        files.map { url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0
            let components: [String]
            switch scheme {
            case .byType:
                components = [MoveService.category(for: url)]
            case .byTypeThenDate:
                components = [MoveService.category(for: url), monthFolder(for: url)]
            case .byTopic:
                // The topic is a nested path ("Company/NeuroBodyGym") — split it into real folder
                // levels. Falls back to the broad type, never a blind "Other".
                components = pathComponents(topicForPath[url.path]) ?? [MoveService.category(for: url)]
            case .byTypeThenTopic:
                // "By type, THEN topic": the file's type category is the top level and the AI topic
                // nests inside it (Documents / Invoices). Prepend the type unless the topic path
                // already starts with it, so we never double it up (Documents / Documents / …).
                let type = MoveService.category(for: url)
                if let topic = pathComponents(topicForPath[url.path]) {
                    components = topic.first == type ? topic : [type] + topic
                } else {
                    components = [type]
                }
            }
            return OrganizePlanItem(file: url, sizeBytes: size, folderComponents: components)
        }
        .sorted { $0.folderPath < $1.folderPath }
    }

    struct OrganizeResult {
        let movedCount: Int
        let foldersCreated: Int
        let movedPairs: [(from: URL, to: URL)]   // for the Undo Center
    }

    /// Executes a plan — creates the (possibly nested) folders and moves each file in, never
    /// overwriting (collisions get a numeric suffix).
    @discardableResult
    static func organize(_ items: [OrganizePlanItem], in folder: URL) throws -> OrganizeResult {
        let fm = FileManager.default
        var moved: [(from: URL, to: URL)] = []
        var createdFolders = Set<String>()
        for item in items {
            let targetDir = item.folderComponents.reduce(folder) { $0.appendingPathComponent($1, isDirectory: true) }
            if !fm.fileExists(atPath: targetDir.path) { createdFolders.insert(targetDir.path) }
            try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)
            let dest = uniqueDestination(targetDir.appendingPathComponent(item.file.lastPathComponent), fm: fm)
            // Don't move a file onto itself (already organized).
            if dest.path == item.file.path { continue }
            try fm.moveItem(at: item.file, to: dest)
            moved.append((from: item.file, to: dest))
        }
        return OrganizeResult(movedCount: moved.count, foldersCreated: createdFolders.count, movedPairs: moved)
    }

    private static func monthFolder(for url: URL) -> String {
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? nil
        guard let date else { return "Undated" }
        let comps = Calendar.current.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
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
