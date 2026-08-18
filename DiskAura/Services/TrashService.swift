import Foundation
import AppKit

enum TrashService {
    static var trashURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
    }

    static func size() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: trashURL,
            includingPropertiesForKeys: nil,
            options: [],
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
    }

    static func itemCount() -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: trashURL.path))?.count ?? 0
    }

    /// Empties Trash via Finder's AppleEvent so it goes through the normal, permission-safe path
    /// (warnings, in-progress deletions, etc.) rather than us recursively rm-ing the folder ourselves.
    ///
    /// THROWS on failure. The previous version discarded the error dictionary entirely, so a denied
    /// Apple Event was indistinguishable from success — the UI reported "Done" with a full Trash.
    /// Returns the bytes actually reclaimed, measured before vs after.
    @discardableResult
    static func empty() throws -> EmptyOutcome {
        let trashBefore = size()
        let freeBefore = VolumeInfoService.stats(for: URL(fileURLWithPath: "/"))?.freeBytes ?? 0
        let script = """
        tell application "Finder"
            empty trash
        end tell
        """
        guard let appleScript = NSAppleScript(source: script) else { throw TrashError.failed("couldn't compile script") }
        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
        if let error {
            let code = (error[NSAppleScript.errorNumber] as? Int) ?? 0
            // -1743 = not authorized to send Apple Events. -600 = Finder not running.
            if code == -1743 || code == -600 { throw TrashError.automationDenied }
            throw TrashError.failed((error[NSAppleScript.errorMessage] as? String) ?? "error \(code)")
        }
        // Finder empties asynchronously; give it a moment before measuring, or a large Trash
        // reports as "reclaimed nothing" purely because we looked too early.
        Thread.sleep(forTimeInterval: 1.5)
        let removed = max(0, trashBefore - size())
        let freeAfter = VolumeInfoService.stats(for: URL(fileURLWithPath: "/"))?.freeBytes ?? 0
        let reclaimed = max(0, freeAfter - freeBefore)
        // Space can leave the Trash without returning to the volume: APFS local snapshots (Time
        // Machine) pin those blocks for up to 24h. Detect that instead of leaving the user staring
        // at an unchanged free-space number.
        let held = removed > 0 && reclaimed < removed / 2
        return EmptyOutcome(bytesRemovedFromTrash: removed, bytesReclaimedOnDisk: reclaimed,
                            heldBySnapshots: held && hasLocalSnapshots())
    }

    /// Bytes that left the Trash vs bytes that actually came back to the volume — NOT the same
    /// number when snapshots hold the blocks, which is exactly the "I deleted 30GB and got 2GB"
    /// confusion this reports honestly.
    struct EmptyOutcome {
        let bytesRemovedFromTrash: Int64
        let bytesReclaimedOnDisk: Int64
        let heldBySnapshots: Bool
    }

    /// True when APFS local (Time Machine) snapshots exist — they retain deleted blocks, so disk
    /// space can lag an emptied Trash by up to 24 hours.
    static func hasLocalSnapshots() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        p.arguments = ["listlocalsnapshots", "/"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return out.contains("com.apple.TimeMachine")
    }

    enum TrashError: Error, LocalizedError {
        case automationDenied, failed(String)
        var errorDescription: String? {
            switch self {
            case .automationDenied:
                return "DiskAura needs permission to control Finder to empty the Trash. Allow it in "
                     + "System Settings → Privacy & Security → Automation → DiskAura → Finder."
            case .failed(let m): return "Couldn't empty the Trash: \(m)"
            }
        }
    }
}
