import Foundation
import Security

/// Result of a shred run — how many files were destroyed and how much space they held.
enum ShredOutcome: Equatable {
    case done(files: Int, bytes: Int64)
    case failed(String)
}

/// Securely erases files: overwrites their bytes with cryptographic random data (one or more
/// passes, synced to disk each pass) BEFORE unlinking, so the contents can't be recovered by
/// undelete tools. Refuses anything `CleanupSafety` considers protected. Note: on APFS with
/// copy-on-write/SSD wear-levelling, overwrite-in-place is best-effort — this raises the bar
/// well above a normal delete, which is the honest promise made in the UI.
enum SecureShredService {
    static func shred(_ urls: [URL], passes: Int) async -> ShredOutcome {
        await Task.detached(priority: .userInitiated) { () -> ShredOutcome in
            let fm = FileManager.default
            var fileCount = 0
            var byteTotal: Int64 = 0
            for url in urls {
                guard ShredSafety.isShreddable(url) else {
                    return .failed("Refused to shred a protected location: “\(url.lastPathComponent)”.")
                }
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
                do {
                    if isDir.boolValue {
                        let (c, b) = try shredDirectory(url, passes: passes, fm: fm)
                        fileCount += c; byteTotal += b
                    } else {
                        byteTotal += try shredFile(url, passes: passes)
                        fileCount += 1
                    }
                } catch {
                    return .failed(error.localizedDescription)
                }
            }
            return .done(files: fileCount, bytes: byteTotal)
        }.value
    }

    private static func shredDirectory(_ dir: URL, passes: Int, fm: FileManager) throws -> (Int, Int64) {
        var count = 0
        var bytes: Int64 = 0
        if let en = fm.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let f as URL in en {
                if (try? f.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                    bytes += try shredFile(f, passes: passes)
                    count += 1
                }
            }
        }
        try fm.removeItem(at: dir)
        return (count, bytes)
    }

    /// Overwrites the file's existing length with random bytes `passes` times, syncing each
    /// pass, then removes it. Returns the file's size in bytes.
    private static func shredFile(_ url: URL, passes: Int) throws -> Int64 {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        if size > 0 {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            for _ in 0..<max(1, passes) {
                try handle.seek(toOffset: 0)
                var remaining = size
                let chunk = 1 << 20  // 1 MiB
                while remaining > 0 {
                    let n = Int(min(Int64(chunk), remaining))
                    var buf = Data(count: n)
                    buf.withUnsafeMutableBytes { ptr in
                        _ = SecRandomCopyBytes(kSecRandomDefault, n, ptr.baseAddress!)
                    }
                    handle.write(buf)
                    remaining -= Int64(n)
                }
                try handle.synchronize()
            }
        }
        try FileManager.default.removeItem(at: url)
        return size
    }
}
