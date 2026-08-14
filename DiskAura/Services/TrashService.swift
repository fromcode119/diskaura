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
    static func empty() throws -> Int64 {
        let before = size()
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
        return max(0, before - size())
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
