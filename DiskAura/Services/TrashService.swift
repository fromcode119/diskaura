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
    static func empty() {
        let script = """
        tell application "Finder"
            empty trash
        end tell
        """
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }
}
