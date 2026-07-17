import Foundation

/// Read-only fan + thermal monitor. Polls fan RPM (Apple SMC) and temperature (IOKit HID sensors)
/// while its tab is visible, and surfaces the OS thermal-pressure state. Never writes the SMC —
/// fan-speed control is unsupported and unsafe on Apple Silicon, so this is a monitor, not a
/// controller.
@MainActor
final class FanThermalService: ObservableObject {
    @Published private(set) var fans: [FanReading] = []
    @Published private(set) var sensors: [TempSensor] = []
    @Published private(set) var peakCelsius: Double = 0
    @Published private(set) var thermalState: ProcessInfo.ThermalState = .nominal
    @Published private(set) var hasSampled = false

    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func sample() {
        fans = (DPReadFans() as [DPFanReading]).map {
            FanReading(id: $0.index, rpm: $0.rpm, minRpm: $0.minRpm, maxRpm: $0.maxRpm)
        }
        let t = SystemStatsService.temperature()
        peakCelsius = t.peakCelsius
        // The HID sensor array is summarized (peak + average) by the existing shim; present those
        // two as the sensor list — a full per-sensor breakdown isn't exposed by the summary API.
        var list: [TempSensor] = []
        if t.peakCelsius > 0 { list.append(TempSensor(id: "peak", label: "Hottest sensor", celsius: t.peakCelsius)) }
        if t.averageCelsius > 0 { list.append(TempSensor(id: "avg", label: "Average", celsius: t.averageCelsius)) }
        sensors = list
        thermalState = ProcessInfo.processInfo.thermalState
        hasSampled = true
    }
}
