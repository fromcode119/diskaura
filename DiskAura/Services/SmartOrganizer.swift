import Foundation
import NaturalLanguage

/// Groups files by the *meaning* of their names, fully on-device — uses Apple's
/// NaturalLanguage word embeddings (ships with macOS, no model download, no network) to
/// cluster filenames into topical folders like "Invoices", "Screenshots", "Training".
/// This is the "small local AI" organize option; it degrades gracefully to type-based
/// grouping when embeddings can't place a file.
enum SmartOrganizer {
    /// One proposed destination subfolder + the files assigned to it.
    struct Group {
        let name: String
        let files: [FileNode]
    }

    private static let stopwords: Set<String> = [
        "the", "and", "for", "img", "image", "photo", "final", "copy", "new", "old",
        "version", "draft", "file", "document", "doc", "untitled", "screenshot", "screen",
        "shot", "export", "exported", "download", "downloaded", "backup", "temp", "tmp",
        "data", "output", "test", "sample"
    ]

    /// Assigns each file to a topical group. Runs synchronously; callers should call it off
    /// the main thread for large sets.
    ///
    /// Images are grouped by what's actually IN them (Vision content topic, then EXIF month) —
    /// because camera filenames like `DSC00776.ARW` carry no words and would otherwise all land
    /// in "Other". Everything else is grouped by the meaning of its name (word embeddings).
    static func groups(for files: [FileNode], maxGroups: Int = 12) -> [Group] {
        let images = files.filter { MediaTopicClassifier.isImage($0.url) }
        let others = files.filter { !MediaTopicClassifier.isImage($0.url) }

        // Reading pixels is the expensive step; past a large batch, skip Vision and group photos
        // by their capture month only (still meaningful, and instant).
        let useContent = images.count <= 1500

        var imageBuckets: [String: [FileNode]] = [:]
        for file in images {
            let topic = (useContent ? MediaTopicClassifier.contentTopic(for: file.url) : nil)
                ?? MediaTopicClassifier.dateTopic(for: file.url)
                ?? "Photos"
            imageBuckets[topic, default: []].append(file)
        }

        var candidates: [Group] = imageBuckets.map { Group(name: $0.key, files: $0.value) }
        candidates.append(contentsOf: embeddingGroups(for: others))

        // Keep the biggest groups; fold the long tail (and any singletons) into "Other".
        candidates.sort { $0.files.count > $1.files.count }
        var result: [Group] = []
        var overflow: [FileNode] = []
        for (i, group) in candidates.enumerated() {
            if i < maxGroups && group.files.count >= 2 {
                result.append(group)
            } else {
                overflow.append(contentsOf: group.files)
            }
        }
        if !overflow.isEmpty { result.append(Group(name: "Other", files: overflow)) }
        return result
    }

    /// Name-meaning clustering for non-image files (invoices, resumes, exports…).
    private static func embeddingGroups(for files: [FileNode]) -> [Group] {
        guard !files.isEmpty else { return [] }
        guard files.count <= 3000, let embedding = NLEmbedding.wordEmbedding(for: .english) else {
            return fallbackByType(files)
        }

        struct Cluster {
            var centroid: [Double]
            var keyword: String
            var files: [FileNode]
        }
        var clusters: [Cluster] = []
        var unplaced: [FileNode] = []
        let threshold = 0.55

        for file in files {
            let keywords = self.keywords(from: file.name)
            guard let best = keywords.first(where: { embedding.vector(for: $0) != nil }),
                  let vec = embedding.vector(for: best) else {
                unplaced.append(file); continue
            }
            var bestIndex = -1
            var bestSim = threshold
            for (i, cluster) in clusters.enumerated() {
                let sim = cosine(vec, cluster.centroid)
                if sim > bestSim { bestSim = sim; bestIndex = i }
            }
            if bestIndex >= 0 {
                clusters[bestIndex].files.append(file)
                clusters[bestIndex].centroid = average(clusters[bestIndex].centroid, vec, count: clusters[bestIndex].files.count)
            } else {
                clusters.append(Cluster(centroid: vec, keyword: best, files: [file]))
            }
        }

        var groups = clusters.map { Group(name: $0.keyword.capitalized, files: $0.files) }
        // Name-less non-images fall back to their file type rather than a blind "Other".
        if !unplaced.isEmpty {
            let byType = Dictionary(grouping: unplaced) { MoveService.category(for: $0.url) }
            groups.append(contentsOf: byType.map { Group(name: $0.key, files: $0.value) })
        }
        return groups
    }

    /// Meaningful tokens from a filename — split on separators, drop numbers/dates/exts and
    /// stopwords, longest first (longer words carry more meaning).
    private static func keywords(from filename: String) -> [String] {
        let base = (filename as NSString).deletingPathExtension.lowercased()
        let parts = base.components(separatedBy: CharacterSet(charactersIn: " _-.()[]").union(.decimalDigits))
        return parts
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 3 && !stopwords.contains($0) }
            .sorted { $0.count > $1.count }
    }

    private static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count else { return 0 }
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in 0..<a.count { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
        let denom = (na.squareRoot() * nb.squareRoot())
        return denom == 0 ? 0 : dot / denom
    }

    private static func average(_ centroid: [Double], _ v: [Double], count: Int) -> [Double] {
        guard centroid.count == v.count, count > 1 else { return v }
        let n = Double(count)
        return zip(centroid, v).map { ($0 * (n - 1) + $1) / n }
    }

    private static func fallbackByType(_ files: [FileNode]) -> [Group] {
        let grouped = Dictionary(grouping: files) { MoveService.category(for: $0.url) }
        return grouped.map { Group(name: $0.key, files: $0.value) }.sorted { $0.files.count > $1.files.count }
    }
}
