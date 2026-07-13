import Foundation

/// Groups files into meaningfully-named folders using the on-device LLM, but spends LLM calls
/// only where they're needed — the "some files are easy, some need reading" pipeline the user
/// asked for:
///   • Photos with a confident Vision scene → that scene (instant, no LLM).
///   • Documents whose NAME already says what they are (invoice, receipt, boarding pass…) →
///     mapped directly (instant, no LLM).
///   • Everything ambiguous → the file's content is read (text/OCR/metadata) and the on-device
///     LLM names an open-vocabulary folder, reusing folders already chosen this run.
/// Results are cached per file and the number of LLM calls is bounded so a huge folder stays
/// responsive; anything past the budget falls back to a type folder (never a blind "Other").
@available(macOS 26.0, *)
enum AIFolderOrganizer {
    /// Upper bound on LLM calls per run — keeps a massive folder from taking minutes. Files past
    /// the budget fall back to their type folder; `Outcome.cappedCount` reports how many, so the
    /// UI can be honest rather than silently truncating.
    static let maxAICalls = 400

    struct Outcome {
        let groups: [SmartOrganizer.Group]
        let aiCalls: Int
        let cappedCount: Int
    }

    private static let cache = NSCache<NSString, NSString>()

    static func organize(_ files: [FileNode],
                         progress: (@Sendable (Int, Int) -> Void)? = nil) async -> Outcome {
        let service = FolderNamingService()
        var buckets: [String: [FileNode]] = [:]
        var vocabulary: [String] = []          // folders chosen so far, offered back for reuse
        var aiCalls = 0
        var capped = 0
        let total = files.count
        var done = 0

        func assign(_ file: FileNode, to folder: String) {
            // If a file only got a bare top-level type (no sub-topic), give it structure so it's
            // never a flat dump: split by file KIND, and for documents add the YEAR too, so a pile
            // of generic PDFs becomes "Documents/PDFs/2025", "Documents/PDFs/2024", …
            var path = folder
            if !folder.contains("/") {
                path = "\(folder)/\(kindSubfolder(for: file.url))"
                if folder == "Documents", let year = fileYear(file) { path += "/\(year)" }
            }
            buckets[path, default: []].append(file)
            if !vocabulary.contains(path) { vocabulary.append(path) }
        }

        // Pass 1 — resolve everything the cheap way (cache / image pixels / filename keyword) and
        // collect only the genuinely-ambiguous files for the model.
        var ambiguous: [FileNode] = []
        for file in files {
            if let cached = cache.object(forKey: cacheKey(file)) as String? {
                assign(file, to: cached); done += 1; progress?(done, total); continue
            }
            if MediaTopicClassifier.isImage(file.url) {
                let path = MediaTopicClassifier.photoFolder(for: file.url)
                cache.setObject(path as NSString, forKey: cacheKey(file))
                assign(file, to: path); done += 1; progress?(done, total); continue
            }
            if let keyworded = keywordFolder(for: file.name) {
                cache.setObject(keyworded as NSString, forKey: cacheKey(file))
                assign(file, to: keyworded); done += 1; progress?(done, total); continue
            }
            ambiguous.append(file)
        }

        // Pass 2 — read the ambiguous files' content CONCURRENTLY (OCR/text extraction is the other
        // slow part; this overlaps it instead of doing it one-by-one). Naming stays PER-FILE and
        // serial so each folder is high-quality and the running vocabulary keeps folders consolidated
        // (batching the model was ~4× faster but returned misaligned/shallow paths — unsafe for real
        // files). Each warmed call is only ~0.3s, so serial here is already fast.
        let signals = await extractSignals(for: ambiguous)
        for (index, file) in ambiguous.enumerated() {
            let category = MoveService.category(for: file.url)
            var folder = category
            if aiCalls < maxAICalls {
                aiCalls += 1
                if let path = await service.folderPath(for: signals[index], category: category,
                                                       existingFolders: vocabulary) {
                    folder = path
                }
            } else {
                capped += 1
            }
            cache.setObject(folder as NSString, forKey: cacheKey(file))
            assign(file, to: folder)
            done += 1
            progress?(done, total)
        }
        progress?(total, total)

        let groups = buckets
            .map { SmartOrganizer.Group(name: $0.key, files: $0.value) }
            .sorted { $0.files.count > $1.files.count }
        return Outcome(groups: groups, aiCalls: aiCalls, cappedCount: capped)
    }

    /// Reads each ambiguous file's signal off the main actor, bounded-concurrently, preserving order.
    private static func extractSignals(for files: [FileNode]) async -> [FileSignalExtractor.Signal] {
        await withTaskGroup(of: (Int, FileSignalExtractor.Signal).self) { group in
            for (index, file) in files.enumerated() {
                let url = file.url
                group.addTask { (index, FileSignalExtractor.signal(for: url)) }
            }
            var results = [FileSignalExtractor.Signal?](repeating: nil, count: files.count)
            for await (index, signal) in group { results[index] = signal }
            return results.map { $0 ?? FileSignalExtractor.Signal(filename: "", kind: "", content: "") }
        }
    }

    // MARK: - Fast paths

    private static func cacheKey(_ file: FileNode) -> NSString {
        let stamp = file.modifiedAt?.timeIntervalSince1970 ?? 0
        return "\(file.path)@\(Int(stamp))" as NSString
    }

    /// Common document types whose filename is a dead giveaway — resolved without reading them,
    /// as a nested path so they sit under a sensible top-level type.
    private static let keywordMap: [(needles: [String], folder: String)] = [
        (["invoice"], "Documents/Finance/Invoices"),
        (["receipt"], "Documents/Finance/Receipts"),
        (["statement", "bank"], "Documents/Finance/Bank Statements"),
        (["payslip", "payroll", "salary"], "Documents/Finance/Payslips"),
        (["boarding", "ticket", "itinerary", "flight"], "Documents/Travel"),
        (["contract", "agreement", "nda"], "Documents/Legal/Contracts"),
        (["resume", "curriculum-vitae"], "Documents/Personal/Resumes"),
        (["report"], "Documents/Reports"),
        (["presentation", "slides", "keynote"], "Documents/Presentations"),
        (["screenshot", "screen-shot", "screen shot"], "Photos/Screenshots"),
    ]

    /// The file's year (from its content/modification date) for grouping otherwise-undifferentiated
    /// files temporally. Nil when no date is available.
    private static func fileYear(_ file: FileNode) -> String? {
        guard let date = file.modifiedAt else { return nil }
        let year = Calendar.current.component(.year, from: date)
        return year > 1970 ? String(year) : nil
    }

    /// A file-kind sub-bucket so a bare "Documents" splits into "Documents/PDFs",
    /// "Documents/Spreadsheets", … instead of one flat pile.
    private static func kindSubfolder(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf": return "PDFs"
        case "doc", "docx", "pages", "rtf", "odt": return "Word"
        case "xls", "xlsx", "csv", "numbers", "ods": return "Spreadsheets"
        case "ppt", "pptx", "key", "odp": return "Presentations"
        case "txt", "md", "log": return "Text"
        case "json", "xml", "yaml", "yml", "js", "ts", "py", "swift", "sh", "html", "css": return "Code & Data"
        case "zip", "rar", "7z", "tar", "gz", "dmg", "pkg", "iso": return "Archives"
        default: return "Files"
        }
    }

    private static func keywordFolder(for filename: String) -> String? {
        let lower = filename.lowercased()
        for entry in keywordMap where entry.needles.contains(where: { lower.contains($0) }) {
            return entry.folder
        }
        return nil
    }
}
