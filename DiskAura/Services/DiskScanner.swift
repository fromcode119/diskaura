import Foundation

/// Recursively scans a directory tree, computing real on-disk sizes (matches `du`, not `ls`).
/// Runs off the main actor; reports incremental progress so the UI can update live.
actor DiskScanner {
    struct Progress {
        let currentPath: String
        let nodesScanned: Int
    }

    private(set) var isCancelled = false

    private static let packageExtensions: Set<String> = [
        "app", "framework", "bundle", "plugin", "kext", "prefpane", "qlgenerator",
        "appex", "component", "systemextension", "docset", "photoslibrary"
    ]

    func cancel() {
        isCancelled = true
    }

    /// Scans `rootURL`, refusing to cross onto a different filesystem/volume than the root
    /// (this is what keeps mounted iOS Simulator disk images from being double-counted).
    private var exclusions = ExclusionMatcher(paths: [])

    func scan(
        rootURL: URL,
        classification: ClassificationEngine,
        exclusions: ExclusionMatcher = ExclusionMatcher(paths: []),
        onProgress: @escaping @Sendable (Progress) -> Void
    ) async -> ScanResult {
        isCancelled = false
        self.exclusions = exclusions
        var skipped: [String] = []
        var denied: [String] = []
        var nodesScanned = 0

        let rootDeviceID = deviceID(for: rootURL)

        let root = buildNode(
            url: rootURL,
            rootDeviceID: rootDeviceID,
            classification: classification,
            skipped: &skipped,
            denied: &denied,
            nodesScanned: &nodesScanned,
            onProgress: onProgress
        )

        let volumeStats = VolumeInfoService.stats(for: rootURL)

        return ScanResult(
            root: root ?? FileNode(url: rootURL, isDirectory: true),
            scannedAt: Date(),
            volume: volumeStats,
            skippedPaths: skipped,
            deniedPaths: denied
        )
    }

    private func deviceID(for url: URL) -> Int32? {
        guard let statInfo = Self.statWithTimeout(url.path) else { return nil }
        return statInfo.st_dev
    }

    private func buildNode(
        url: URL,
        rootDeviceID: Int32?,
        classification: ClassificationEngine,
        skipped: inout [String],
        denied: inout [String],
        nodesScanned: inout Int,
        onProgress: @escaping @Sendable (Progress) -> Void
    ) -> FileNode? {
        if isCancelled { return nil }

        // Honor the user's Ignore List — never scan/count an excluded folder.
        if exclusions.isExcluded(url) {
            skipped.append(url.path)
            return nil
        }

        // A stale network share or wedged FUSE mount can block a syscall indefinitely at the
        // kernel level — confirmed live (contentsOfDirectory hung >2min on one bad path with
        // 0% CPU, not even SIGKILL-interruptible). Every blocking filesystem call in this scanner
        // is timeout-guarded so one unresponsive path can't freeze the whole scan forever.
        guard let statInfo = Self.statWithTimeout(url.path) else {
            denied.append(url.path)
            return nil
        }

        // Don't cross onto a different mounted volume (e.g. CoreSimulator disk images).
        if let rootDeviceID, statInfo.st_dev != rootDeviceID {
            skipped.append(url.path)
            return nil
        }

        let isSymlink = (statInfo.st_mode & S_IFMT) == S_IFLNK
        if isSymlink {
            return nil
        }

        let isDirectory = (statInfo.st_mode & S_IFMT) == S_IFDIR

        nodesScanned += 1
        if nodesScanned % 500 == 0 {
            onProgress(Progress(currentPath: url.path, nodesScanned: nodesScanned))
        }

        if !isDirectory {
            let size = Int64(statInfo.st_blocks) * 512
            let modified = Date(timeIntervalSince1970: Double(statInfo.st_mtimespec.tv_sec))
            return FileNode(url: url, isDirectory: false, sizeBytes: size, modifiedAt: modified)
        }

        let tag = classification.tag(for: url)

        // Don't descend into folders we already classify as a single clearable/system unit —
        // saves time and keeps e.g. "node_modules" as one row rather than thousands of children.
        //
        // Same treatment for app bundles and other package-style directories (.app, .framework,
        // .bundle, .plugin, .kext): Finder treats these as one opaque item, not a folder of
        // thousands of loose files. Materializing every file inside every .app's
        // Contents/Resources/*.lproj tree is what caused a single /Applications scan to
        // create 377,000+ retained FileNode objects and push the app to ~1GB RAM (confirmed
        // live — RAM stayed high with zero other views ever opened). Apps are still sized
        // correctly via directorySize(), just not materialized node-by-node internally.
        let isPackage = Self.packageExtensions.contains(url.pathExtension.lowercased())
        if tag == .clean || tag == .system || isPackage {
            let size = directorySize(at: url)
            return FileNode(url: url, isDirectory: true, sizeBytes: size, tag: tag)
        }

        guard let entries = Self.contentsOfDirectoryWithTimeout(url) else {
            denied.append(url.path)
            return FileNode(url: url, isDirectory: true, tag: tag)
        }

        var children: [FileNode] = []
        var totalSize: Int64 = 0

        for entry in entries {
            if isCancelled { break }
            if let child = buildNode(
                url: entry,
                rootDeviceID: rootDeviceID,
                classification: classification,
                skipped: &skipped,
                denied: &denied,
                nodesScanned: &nodesScanned,
                onProgress: onProgress
            ) {
                children.append(child)
                totalSize += child.sizeBytes
            }
        }

        return FileNode(url: url, isDirectory: true, sizeBytes: totalSize, tag: tag, children: children)
    }

    /// Fast total size for a subtree we won't materialize node-by-node (e.g. inside node_modules).
    /// Timeout-budgeted as a whole: if a hung file mid-enumeration eats the budget, returns
    /// whatever partial total was accumulated rather than blocking forever.
    private func directorySize(at url: URL) -> Int64 {
        Self.withTimeout(seconds: 15, fallback: 0) {
            guard let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsPackageDescendants],
                errorHandler: nil
            ) else { return 0 }

            var total: Int64 = 0
            for case let fileURL as URL in enumerator {
                var statInfo = stat()
                if lstat(fileURL.path, &statInfo) == 0, (statInfo.st_mode & S_IFMT) != S_IFLNK {
                    total += Int64(statInfo.st_blocks) * 512
                }
            }
            return total
        } ?? 0
    }

    private static func statWithTimeout(_ path: String, seconds: TimeInterval = 3) -> stat? {
        withTimeout(seconds: seconds, fallback: nil) {
            var info = stat()
            return lstat(path, &info) == 0 ? info : nil
        } ?? nil
    }

    private static func contentsOfDirectoryWithTimeout(_ url: URL, seconds: TimeInterval = 5) -> [URL]? {
        withTimeout(seconds: seconds, fallback: nil) {
            try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsPackageDescendants]
            )
        } ?? nil
    }

    /// Runs a blocking filesystem call on a dedicated (not Dispatch-pooled) thread so a
    /// leaked, permanently-blocked call from a wedged mount can never starve the app's
    /// limited global concurrent-queue thread pool.
    private static func withTimeout<T>(seconds: TimeInterval, fallback: T?, work: @escaping () -> T?) -> T? {
        let semaphore = DispatchSemaphore(value: 0)
        let box = ResultBox<T>()

        let thread = Thread {
            box.value = work()
            semaphore.signal()
        }
        thread.stackSize = 4 << 20
        thread.start()

        if semaphore.wait(timeout: .now() + seconds) == .timedOut {
            return fallback
        }
        return box.value
    }

    private final class ResultBox<T>: @unchecked Sendable {
        var value: T?
    }
}
