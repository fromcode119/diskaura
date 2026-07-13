import Foundation

enum MoveOrganize: String, CaseIterable, Identifiable {
    case flat = "Leave as-is"
    case byType = "Sort into type folders"
    case byDate = "Sort into date folders"
    case smart = "Group by topic (on-device AI)"

    var id: String { rawValue }

    var detail: String {
        switch self {
        case .flat: return "Move everything straight into the folder."
        case .byType: return "Images, Videos, Documents, Archives, …"
        case .byDate: return "Year-Month folders by last-modified date."
        case .smart: return "Clusters files by what their names mean — private, no network."
        }
    }
}

enum MoveServiceError: LocalizedError {
    case failed(String)
    var errorDescription: String? { if case .failed(let r) = self { return r }; return nil }
}

/// Moves selected files to a destination folder, optionally organizing them into subfolders
/// by file type or by date. Rule-based and predictable — no data loss: collisions get a
/// numeric suffix rather than overwriting.
struct MoveService {
    static func category(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "tiff", "tif", "bmp", "svg",
             "raw", "cr2", "cr3", "nef", "dng", "arw", "orf", "rw2", "raf", "srw", "pef", "sr2", "nrw", "3fr":
            return "Images"
        case "mov", "mp4", "avi", "mkv", "m4v", "webm", "wmv", "flv":
            return "Videos"
        case "mp3", "wav", "aac", "flac", "m4a", "aiff", "aif", "ogg":
            return "Audio"
        case "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "rtf", "pages", "numbers", "key", "md", "csv":
            return "Documents"
        case "zip", "rar", "7z", "tar", "gz", "bz2", "dmg", "pkg", "iso":
            return "Archives"
        case "swift", "js", "ts", "py", "java", "c", "cpp", "h", "hpp", "json", "html", "css", "sh", "rb", "go", "rs":
            return "Code"
        default:
            return ext.isEmpty ? "Other" : "Other"
        }
    }

    /// One destination subfolder and the files headed into it — used to preview the move
    /// (with thumbnails) BEFORE anything is touched. Folder "" means the destination root.
    struct PlanGroup {
        let folder: String
        let files: [FileNode]
    }

    /// Computes exactly where each file would land, without moving anything. Mirrors `move`'s
    /// grouping so the preview and the real move can never disagree.
    static func plan(_ nodes: [FileNode], organize: MoveOrganize) -> [PlanGroup] {
        var smartFolder: [String: String] = [:]
        if organize == .smart {
            for group in SmartOrganizer.groups(for: nodes) {
                for file in group.files { smartFolder[file.path] = group.name }
            }
        }
        func folder(for node: FileNode) -> String {
            switch organize {
            case .flat: return ""
            case .byType: return category(for: node.url)
            case .byDate: return dateFolder(for: node)
            case .smart: return smartFolder[node.path] ?? "Other"
            }
        }
        return Dictionary(grouping: nodes, by: folder)
            .map { PlanGroup(folder: $0.key, files: $0.value) }
            .sorted { $0.files.reduce(0) { $0 + $1.sizeBytes } > $1.files.reduce(0) { $0 + $1.sizeBytes } }
    }

    /// Async plan: like `plan`, but the `.smart` mode names folders with the on-device LLM
    /// (macOS 26+), falling back to the sync clusterer when the model isn't available. Other
    /// modes are deterministic and defer to `plan`. `progress` reports (done, total).
    static func planAsync(_ nodes: [FileNode], organize: MoveOrganize,
                          progress: (@Sendable (Int, Int) -> Void)? = nil) async -> [PlanGroup] {
        guard organize == .smart, #available(macOS 26.0, *), FolderNamingService.isAvailable else {
            return plan(nodes, organize: organize)
        }
        let outcome = await AIFolderOrganizer.organize(nodes, progress: progress)
        return outcome.groups
            .map { PlanGroup(folder: $0.name, files: $0.files) }
            .sorted { $0.files.reduce(0) { $0 + $1.sizeBytes } > $1.files.reduce(0) { $0 + $1.sizeBytes } }
    }

    /// Executes a PRECOMPUTED plan — so the move lands files exactly where the preview showed,
    /// and the (possibly expensive) LLM naming runs once, not again at move time. Returns the
    /// (from, to) pairs so the move can be recorded as reversible in the Undo Center.
    @discardableResult
    static func move(plan: [PlanGroup], to destination: URL) throws -> [(from: URL, to: URL)] {
        let fm = FileManager.default
        var moved: [(from: URL, to: URL)] = []
        for group in plan {
            // The folder may be a nested path ("Documents/Company/NeuroBodyGym") — build each level.
            let levels = group.folder.split(separator: "/").map(String.init).filter { !$0.isEmpty }
            let targetDir = levels.reduce(destination) { $0.appendingPathComponent($1, isDirectory: true) }
            for node in group.files {
                do {
                    try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)
                    let dest = uniqueDestination(targetDir.appendingPathComponent(node.name), fm: fm)
                    try fm.moveItem(at: node.url, to: dest)
                    moved.append((from: node.url, to: dest))
                } catch {
                    throw MoveServiceError.failed("Couldn't move \(node.name): \(error.localizedDescription)")
                }
            }
        }
        return moved
    }

    private static func dateFolder(for node: FileNode) -> String {
        guard let date = node.modifiedAt else { return "Undated" }
        let comps = Calendar.current.dateComponents([.year, .month], from: date)
        let year = comps.year ?? 0
        let month = comps.month ?? 0
        return String(format: "%04d-%02d", year, month)
    }

    private static func uniqueDestination(_ url: URL, fm: FileManager) -> URL {
        guard fm.fileExists(atPath: url.path) else { return url }
        let dir = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        var i = 1
        while true {
            let candidateName = ext.isEmpty ? "\(base)-\(i)" : "\(base)-\(i).\(ext)"
            let candidate = dir.appendingPathComponent(candidateName)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            i += 1
        }
    }
}
