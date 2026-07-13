import Foundation
import AppKit

/// Polls live process stats (CPU%, memory, disk I/O rate) using libproc.
/// CPU/memory are available for any process; disk I/O rate is computed from
/// deltas between successive `proc_pid_rusage` samples.
///
/// This is an actor (not a plain class called from MainActor) because `sample()` makes
/// 1000+ synchronous syscalls (proc_pidinfo per pid) — running that on the main thread
/// is what made tab switches feel slow. Callers `await` it from a background context.
actor ProcessMonitor {
    private var previousCPUTime: [Int32: UInt64] = [:]
    private var previousDiskIO: [Int32: (read: UInt64, write: UInt64)] = [:]
    private var previousSampleTime: Date = Date()

    func sample() -> [ProcessSnapshot] {
        let now = Date()
        let elapsed = max(now.timeIntervalSince(previousSampleTime), 0.001)
        defer { previousSampleTime = now }

        // Running GUI apps, keyed by pid, so each process row can show its real Dock icon
        // and be classified as "Application" vs "Background" — same signal Activity Monitor uses.
        var appsByPID: [Int32: NSRunningApplication] = [:]
        for app in NSWorkspace.shared.runningApplications {
            appsByPID[app.processIdentifier] = app
        }

        // CleanMyMac's actual split is "System processes" (owned by root/other system
        // accounts) vs "User processes" (owned by you) — not just GUI-app-or-not. A
        // process's owning UID comes from PROC_PIDTBSDINFO.
        let currentUID = getuid()

        var pids = [Int32](repeating: 0, count: 4096)
        let bytesReturned = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * MemoryLayout<Int32>.size))
        guard bytesReturned > 0 else { return [] }
        let pidCount = Int(bytesReturned) / MemoryLayout<Int32>.size

        var results: [ProcessSnapshot] = []
        results.reserveCapacity(pidCount)

        for i in 0..<pidCount {
            let pid = pids[i]
            guard pid > 0 else { continue }

            // PROC_PIDTBSDINFO (name, owning UID) succeeds cross-user without elevated
            // privileges; PROC_PIDTASKINFO (CPU/memory) does NOT — it silently fails for
            // processes owned by another user (i.e. almost everything root owns) unless
            // the caller is privileged. The old code required TASKINFO to succeed just to
            // include a process at all, which silently dropped every root/system daemon
            // from the list — confirmed live: "System" showed 0 processes. Now a process
            // is included whenever we can at least name/classify it; CPU/memory are 0
            // when genuinely unreadable rather than the whole row vanishing.
            var bsdInfo = proc_bsdinfo()
            let bsdSize = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsdInfo, Int32(MemoryLayout<proc_bsdinfo>.size))
            guard bsdSize == Int32(MemoryLayout<proc_bsdinfo>.size) else { continue }
            let isSystemProcess = bsdInfo.pbi_uid != currentUID

            var nameBuffer = [CChar](repeating: 0, count: 256)
            let nameLength = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
            let name = nameLength > 0 ? String(cString: nameBuffer) : "pid \(pid)"

            var taskInfo = proc_taskinfo()
            let taskSize = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, Int32(MemoryLayout<proc_taskinfo>.size))
            let hasTaskInfo = taskSize == Int32(MemoryLayout<proc_taskinfo>.size)

            let totalCPUTime = hasTaskInfo ? taskInfo.pti_total_user + taskInfo.pti_total_system : 0
            let previousTime = previousCPUTime[pid] ?? totalCPUTime
            let deltaCPUNanos = totalCPUTime > previousTime ? totalCPUTime - previousTime : 0
            previousCPUTime[pid] = totalCPUTime
            let cpuPercent = hasTaskInfo ? (Double(deltaCPUNanos) / 1_000_000_000.0) / elapsed * 100.0 : 0

            var rusage = rusage_info_current()
            var currentRead: UInt64 = 0
            var currentWrite: UInt64 = 0
            let rc = withUnsafeMutablePointer(to: &rusage) { ptr -> Int32 in
                ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rptr in
                    proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, rptr)
                }
            }
            if rc == 0 {
                currentRead = rusage.ri_diskio_bytesread
                currentWrite = rusage.ri_diskio_byteswritten
            }

            let previousIO = previousDiskIO[pid] ?? (read: currentRead, write: currentWrite)
            let deltaRead = currentRead > previousIO.read ? currentRead - previousIO.read : 0
            let deltaWrite = currentWrite > previousIO.write ? currentWrite - previousIO.write : 0
            previousDiskIO[pid] = (read: currentRead, write: currentWrite)

            let readPerSec = UInt64(Double(deltaRead) / elapsed)
            let writePerSec = UInt64(Double(deltaWrite) / elapsed)

            let app = appsByPID[pid]
            results.append(ProcessSnapshot(
                id: pid,
                name: app?.localizedName ?? name,
                cpuPercent: max(cpuPercent, 0),
                memoryBytes: hasTaskInfo ? UInt64(taskInfo.pti_resident_size) : 0,
                diskReadBytesPerSec: readPerSec,
                diskWriteBytesPerSec: writePerSec,
                isApp: app != nil,
                isSystemProcess: isSystemProcess,
                icon: app?.icon
            ))
        }

        return results
    }
}
