import Foundation
import IOKit.ps

struct BatteryInfo {
    let hasBattery: Bool
    let percent: Int
    let charging: Bool
    var fraction: Double { Double(percent) / 100.0 }
}

struct NetThroughput {
    let downBytesPerSec: Double
    let upBytesPerSec: Double
}

/// Extra menu-bar glance metrics: battery, live network throughput, and system uptime.
/// Kept separate from `SystemStatsService` (CPU/memory/thermal) since these use different
/// system APIs (IOKit power sources, `getifaddrs` counters, `ProcessInfo.systemUptime`).
enum SystemGlanceService {
    /// e.g. "3d 4h", "5h 12m", "8m". Uptime since last boot.
    static func uptimeString() -> String {
        let s = Int(ProcessInfo.processInfo.systemUptime)
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    static func battery() -> BatteryInfo {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let source = list.first,
              let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any]
        else { return BatteryInfo(hasBattery: false, percent: 0, charging: false) }

        let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
        let maximum = desc[kIOPSMaxCapacityKey] as? Int ?? 100
        let state = desc[kIOPSPowerSourceStateKey] as? String
        let charging = (desc[kIOPSIsChargingKey] as? Bool) ?? (state == kIOPSACPowerValue)
        let percent = maximum > 0 ? Int((Double(current) / Double(maximum) * 100).rounded()) : 0
        return BatteryInfo(hasBattery: true, percent: percent, charging: charging)
    }

    /// Previous interface byte counters + timestamp — throughput is the delta over elapsed time.
    private static var previousSample: (down: UInt64, up: UInt64, time: TimeInterval)?

    /// Live network throughput (bytes/sec) summed across all up, non-loopback interfaces.
    /// First call returns 0 (no baseline). Counter wrap returns 0 for that tick.
    static func networkThroughput() -> NetThroughput {
        var down: UInt64 = 0
        var up: UInt64 = 0
        var addrs: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&addrs) == 0 {
            var ptr = addrs
            while let node = ptr {
                let flags = Int32(node.pointee.ifa_flags)
                let name = String(cString: node.pointee.ifa_name)
                if let data = node.pointee.ifa_data,
                   node.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
                   (flags & IFF_UP) != 0, !name.hasPrefix("lo") {
                    let d = data.assumingMemoryBound(to: if_data.self)
                    down += UInt64(d.pointee.ifi_ibytes)
                    up += UInt64(d.pointee.ifi_obytes)
                }
                ptr = node.pointee.ifa_next
            }
            freeifaddrs(addrs)
        }
        let now = ProcessInfo.processInfo.systemUptime
        defer { previousSample = (down, up, now) }
        guard let prev = previousSample, now > prev.time else {
            return NetThroughput(downBytesPerSec: 0, upBytesPerSec: 0)
        }
        let dt = now - prev.time
        let dd = down >= prev.down ? Double(down - prev.down) : 0
        let du = up >= prev.up ? Double(up - prev.up) : 0
        return NetThroughput(downBytesPerSec: dd / dt, upBytesPerSec: du / dt)
    }
}
