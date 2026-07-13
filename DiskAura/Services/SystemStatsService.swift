import Foundation

/// Lightweight system glance for the menu-bar panel: real memory pressure and the OS thermal
/// state. Temperature in °C requires a privileged sensor helper (what iStat Menus ships), which
/// a sandbox-free but unprivileged app can't read reliably — so we surface Apple's public
/// thermal-pressure state (Normal / Fair / Serious / Critical) instead of a fake number.
enum SystemStatsService {
    struct MemoryStats {
        let usedBytes: Int64
        let totalBytes: Int64
        var usedFraction: Double { totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0 }
    }

    /// Previous CPU tick sample — system-wide load is the delta between two reads, so we keep the
    /// last one. First call returns 0 (no baseline yet).
    private static var previousCPUTicks: host_cpu_load_info?

    /// System-wide CPU busy fraction (0–1) since the previous call. Cheap: one `host_statistics`.
    static func cpuLoad() -> Double {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        var info = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        defer { previousCPUTicks = info }
        guard let previous = previousCPUTicks else { return 0 }
        let user = Double(info.cpu_ticks.0 &- previous.cpu_ticks.0)
        let system = Double(info.cpu_ticks.1 &- previous.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2 &- previous.cpu_ticks.2)
        let nice = Double(info.cpu_ticks.3 &- previous.cpu_ticks.3)
        let total = user + system + idle + nice
        return total > 0 ? max(0, min(1, (user + system + nice) / total)) : 0
    }

    static func memory() -> MemoryStats {
        let total = Int64(ProcessInfo.processInfo.physicalMemory)
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return MemoryStats(usedBytes: 0, totalBytes: total) }
        let page = Int64(vm_kernel_page_size)
        // "App memory" pressure the way Activity Monitor shows it: active + wired + compressed.
        let used = (Int64(stats.active_count) + Int64(stats.wire_count) + Int64(stats.compressor_page_count)) * page
        return MemoryStats(usedBytes: min(used, total), totalBytes: total)
    }

    enum Thermal: String {
        case normal = "Normal", fair = "Fair", serious = "Serious", critical = "Critical"
    }

    static func thermal() -> Thermal {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return .normal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .normal
        }
    }

    struct Temperature {
        let averageCelsius: Double
        let peakCelsius: Double
        var available: Bool { peakCelsius > 0 }
        /// A hotness bucket for coloring, based on the peak sensor.
        var level: Thermal {
            switch peakCelsius {
            case ..<60: return .normal
            case 60..<80: return .fair
            case 80..<95: return .serious
            default: return .critical
            }
        }
    }

    /// Real sensor temperature in °C (peak + average) via IOKit HID — falls back to the OS
    /// thermal-pressure `level` for coloring when no sensor is readable.
    static func temperature() -> Temperature {
        Temperature(averageCelsius: DPReadAverageTemperature(), peakCelsius: DPReadPeakTemperature())
    }
}
