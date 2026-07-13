import Foundation
import CryptoKit

/// Finds duplicate files within a folder: group by exact size first (cheap), then
/// SHA-256 hash the survivors of each size group (expensive, only run where it matters).
/// Cancellable and progress-reporting — on a big root (a whole home folder) the hashing
/// pass can be long, so callers get live "hashed / total" counts and can stop it.
enum DuplicateFinderService {
    struct Progress: Sendable {
        let phase: String   // "Scanning" or "Hashing"
        let done: Int
        let total: Int
    }

    static func findDuplicates(
        in rootURL: URL,
        minSizeBytes: Int64 = 1024,
        exclusions: ExclusionMatcher = ExclusionMatcher(paths: []),
        isCancelled: @escaping @Sendable () -> Bool = { false },
        onProgress: @escaping @Sendable (Progress) -> Void = { _ in }
    ) async -> [DuplicateGroup] {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsPackageDescendants]
        ) else { return [] }

        var bySize: [Int64: [URL]] = [:]
        var scanned = 0

        while let fileURL = enumerator.nextObject() as? URL {
            if isCancelled() { return [] }
            if exclusions.isExcluded(fileURL) { continue }
            var statInfo = stat()
            guard lstat(fileURL.path, &statInfo) == 0,
                  (statInfo.st_mode & S_IFMT) == S_IFREG else { continue }
            let size = Int64(statInfo.st_size)
            guard size >= minSizeBytes else { continue }
            bySize[size, default: []].append(fileURL)
            scanned += 1
            if scanned % 2000 == 0 { onProgress(Progress(phase: "Scanning", done: scanned, total: 0)) }
        }

        // Only size-collisions need hashing — that's the expensive part, so report against it.
        let hashTotal = bySize.values.filter { $0.count > 1 }.reduce(0) { $0 + $1.count }
        var hashed = 0
        var groups: [DuplicateGroup] = []

        for (size, urls) in bySize where urls.count > 1 {
            if isCancelled() { return [] }
            var byHash: [String: [URL]] = [:]
            for url in urls {
                if isCancelled() { return [] }
                if let hash = Self.sha256(of: url) {
                    byHash[hash, default: []].append(url)
                }
                hashed += 1
                if hashed % 50 == 0 { onProgress(Progress(phase: "Hashing", done: hashed, total: hashTotal)) }
            }
            for (_, matchedURLs) in byHash where matchedURLs.count > 1 {
                let files = matchedURLs.map { url -> DuplicateFile in
                    var statInfo = stat()
                    let modified: Date? = lstat(url.path, &statInfo) == 0
                        ? Date(timeIntervalSince1970: Double(statInfo.st_mtimespec.tv_sec)) : nil
                    return DuplicateFile(url: url, sizeBytes: size, modifiedAt: modified)
                }
                groups.append(DuplicateGroup(files: files))
            }
        }

        return groups.sorted { $0.reclaimableBytes > $1.reclaimableBytes }
    }

    private static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
