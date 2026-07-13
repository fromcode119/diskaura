import Foundation

/// Real physical memory used, matching what Activity Monitor's Memory tab shows —
/// NOT a sum of per-process resident set sizes. Summing RSS across processes
/// double/triple-counts shared frameworks and libraries mapped into multiple
/// processes at once; confirmed live it reported 55GB "used" on a 42GB RAM machine.
/// `host_statistics64` reports true active/wired/compressed pages instead.
enum SystemMemoryService {
    struct Stats {
        let usedBytes: UInt64
        let totalBytes: UInt64
        // Real per-category breakdown (matches Activity Monitor's memory pressure
        // categories) — lets the UI show an actual Active/Wired/Compressed/Free donut
        // instead of one flat "used" bar.
        let activeBytes: UInt64
        let wiredBytes: UInt64
        let compressedBytes: UInt64
        let freeBytes: UInt64
    }

    static func current() -> Stats? {
        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return nil }

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let pageBytes = UInt64(pageSize)
        let activeBytes = UInt64(stats.active_count) * pageBytes
        let wiredBytes = UInt64(stats.wire_count) * pageBytes
        let compressedBytes = UInt64(stats.compressor_page_count) * pageBytes
        let freeBytes = UInt64(stats.free_count) * pageBytes

        // Active + wired + compressed matches Activity Monitor's "Memory Used" — excludes
        // free and purgeable-but-inactive pages the OS can reclaim on demand.
        let usedBytes = activeBytes + wiredBytes + compressedBytes

        var totalBytes: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &totalBytes, &size, nil, 0)

        return Stats(usedBytes: usedBytes, totalBytes: totalBytes,
                     activeBytes: activeBytes, wiredBytes: wiredBytes,
                     compressedBytes: compressedBytes, freeBytes: freeBytes)
    }
}
