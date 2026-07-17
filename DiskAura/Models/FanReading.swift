import Foundation

/// One fan's live reading (RPM), with the SMC-reported min/max envelope when available.
struct FanReading: Identifiable {
    let id: Int
    let rpm: Int
    let minRpm: Int
    let maxRpm: Int

    /// 0…1 position of the current RPM within the fan's envelope, for a ring gauge. Apple Silicon
    /// doesn't expose the F%dMn/F%dMx keys (they read 0), so fall back to a nominal 6000-RPM ceiling
    /// so the gauge still conveys "how hard is this fan working".
    var loadFraction: Double {
        let ceiling = maxRpm > minRpm ? Double(maxRpm) : 6000
        let floor = maxRpm > minRpm ? Double(minRpm) : 0
        guard ceiling > floor else { return 0 }
        return min(1, max(0, (Double(rpm) - floor) / (ceiling - floor)))
    }
}
