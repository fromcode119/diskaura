import Foundation

/// Explains the macOS "System Data" black hole — the mysterious tens-of-GB chunk Finder shows but
/// never itemises. It splits that space into named buckets: what you can safely reclaim (caches,
/// logs, snapshots, Xcode junk, Trash — reused from the junk scanner) and what is real system
/// working storage you should NOT touch (VM swap, the sleep image), shown for transparency so the
/// number stops being a mystery.
enum SystemDataService {
    struct Bucket: Identifiable {
        let id: String
        let title: String
        let icon: String
        let bytes: Int64
        let explanation: String
        let reclaimable: Bool
    }

    struct Report {
        let volumeTotalBytes: Int64
        let volumeUsedBytes: Int64
        let volumeFreeBytes: Int64
        let reclaimable: [Bucket]      // caches, logs, snapshots, trash, … (sorted, biggest first)
        let systemManaged: [Bucket]    // VM swap, sleep image — informational only
        let snapshotCount: Int

        var reclaimableTotal: Int64 { reclaimable.reduce(0) { $0 + $1.bytes } }
        var systemManagedTotal: Int64 { systemManaged.reduce(0) { $0 + $1.bytes } }
    }

    /// Runs off the main thread — the junk scan walks real directories.
    static func analyze(exclusions: ExclusionMatcher = ExclusionMatcher(paths: []),
                        isCancelled: @escaping () -> Bool = { false }) -> Report {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let volume = VolumeInfoService.stats(for: home)

        // Reclaimable — reuse the junk scanner so the numbers always match the Cleanup tab.
        let categories = JunkScanner.scan(exclusions: exclusions, isCancelled: isCancelled)
        let reclaimable = categories
            .map { Bucket(id: $0.id, title: $0.title, icon: $0.icon, bytes: $0.totalBytes,
                          explanation: $0.explanation, reclaimable: true) }
            .filter { $0.bytes > 0 }
            .sorted { $0.bytes > $1.bytes }

        // System-managed — real working storage macOS owns; sized for transparency, never offered
        // for deletion (removing swap/sleepimage risks the OS and they're regenerated anyway).
        let vmDir = "/private/var/vm"
        let swapBytes = directorySize(atPath: vmDir, matching: { $0.hasPrefix("swapfile") })
        let sleepBytes = fileSize(atPath: "\(vmDir)/sleepimage")
        var systemManaged: [Bucket] = []
        if swapBytes > 0 {
            systemManaged.append(Bucket(id: "vm-swap", title: "Virtual Memory (swap)", icon: "memorychip",
                bytes: swapBytes,
                explanation: "Memory paged to disk when RAM fills. macOS manages this automatically — it can't be safely removed.",
                reclaimable: false))
        }
        if sleepBytes > 0 {
            systemManaged.append(Bucket(id: "sleepimage", title: "Sleep Image", icon: "powersleep",
                bytes: sleepBytes,
                explanation: "A copy of RAM written before hibernation so you don't lose work on sleep. System-owned.",
                reclaimable: false))
        }

        return Report(
            volumeTotalBytes: volume?.totalBytes ?? 0,
            volumeUsedBytes: volume?.usedBytes ?? 0,
            volumeFreeBytes: volume?.freeBytes ?? 0,
            reclaimable: reclaimable,
            systemManaged: systemManaged.sorted { $0.bytes > $1.bytes },
            snapshotCount: TimeMachineSnapshotService.list().count
        )
    }

    // MARK: - Sizing helpers (stat only — never reads file contents, so no permission needed)

    private static func fileSize(atPath path: String) -> Int64 {
        var s = stat()
        guard lstat(path, &s) == 0 else { return 0 }
        return Int64(s.st_blocks) * 512
    }

    private static func directorySize(atPath path: String, matching: (String) -> Bool) -> Int64 {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: path) else { return 0 }
        return entries.filter(matching).reduce(0) { $0 + fileSize(atPath: "\(path)/\($1)") }
    }
}
