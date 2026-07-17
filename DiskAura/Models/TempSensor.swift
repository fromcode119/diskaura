import Foundation

/// A single named thermal reading in °C, for the sensor list.
struct TempSensor: Identifiable {
    let id: String
    let label: String
    let celsius: Double
}
