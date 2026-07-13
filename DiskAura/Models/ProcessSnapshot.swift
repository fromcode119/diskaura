import Foundation
import AppKit

struct ProcessSnapshot: Identifiable, Equatable {
    let id: Int32 // pid
    let name: String
    var cpuPercent: Double
    var memoryBytes: UInt64
    var diskReadBytesPerSec: UInt64
    var diskWriteBytesPerSec: UInt64
    /// True when this pid matches a GUI app in NSWorkspace's running-applications list —
    /// Activity Monitor's "Applications" vs "background processes" split rests on the same signal.
    var isApp: Bool
    /// True when the process is owned by a different user (root, _windowserver, etc.) rather
    /// than the current account — CleanMyMac's actual "System processes" vs "User processes" split.
    var isSystemProcess: Bool
    var icon: NSImage?

    static func == (lhs: ProcessSnapshot, rhs: ProcessSnapshot) -> Bool {
        lhs.id == rhs.id
            && lhs.cpuPercent == rhs.cpuPercent
            && lhs.memoryBytes == rhs.memoryBytes
            && lhs.diskReadBytesPerSec == rhs.diskReadBytesPerSec
            && lhs.diskWriteBytesPerSec == rhs.diskWriteBytesPerSec
    }
}

enum ProcessFilter: String, CaseIterable, Identifiable {
    case all = "All Processes"
    case apps = "Applications"
    case system = "System"

    var id: String { rawValue }
}
