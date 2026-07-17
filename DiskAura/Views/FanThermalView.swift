import SwiftUI

/// Read-only fan + thermal monitor. Shows live fan RPM, temperature sensors, the OS thermal-
/// pressure state, and a "why are my fans loud" section tying heat to the top CPU processes.
/// There is no fan-speed control: Apple Silicon blocks it, so this is honestly a monitor.
struct FanThermalView: View {
    @ObservedObject var viewModel: FanThermalService
    @ObservedObject var processVM: ProcessViewModel

    private var accent: Color { Theme.moduleColor(.fanThermal) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                fansSection
                sensorsSection
                loudSection
            }
            .padding(Theme.Spacing.lg)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Fan & Thermal").font(.system(size: 22, weight: .bold))
            Text("Live monitor — Apple Silicon manages fan speed itself, so DiskAura reads but never overrides it.")
                .font(.system(size: 12)).foregroundColor(.secondary)
        }
    }

    // MARK: Fans

    @ViewBuilder private var fansSection: some View {
        if viewModel.fans.isEmpty {
            infoCard(icon: "wind", text: viewModel.hasSampled
                     ? "No fans detected — this Mac is fanless, or the SMC isn't reporting fan speed."
                     : "Reading fans…")
        } else {
            HStack(spacing: Theme.Spacing.md) {
                ForEach(viewModel.fans) { fan in
                    VStack(spacing: 10) {
                        RingGauge(fraction: fan.loadFraction,
                                  centerValue: "\(fan.rpm)",
                                  centerLabel: "RPM",
                                  color: accent, size: 128, lineWidth: 14)
                        Text("Fan \(fan.id + 1)").font(.system(size: 12, weight: .medium)).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(Theme.Spacing.md)
                    .glassCard()
                }
            }
        }
    }

    // MARK: Sensors + thermal pressure

    private var sensorsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Temperature").font(.system(size: 13, weight: .semibold))
                Spacer()
                thermalBadge
            }
            Divider()
            if viewModel.sensors.isEmpty {
                Text("No readable temperature sensors.").font(.system(size: 11)).foregroundColor(.secondary)
            } else {
                ForEach(viewModel.sensors) { s in
                    HStack {
                        Image(systemName: "thermometer.medium").foregroundColor(accent).frame(width: 20)
                        Text(s.label).font(.system(size: 12))
                        Spacer()
                        Text("\(Int(s.celsius.rounded()))°C")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .padding(Theme.Spacing.lg).glassCard()
    }

    private var thermalBadge: some View {
        let (label, color) = thermalDescriptor
        return Text(label)
            .font(.system(size: 10, weight: .bold)).tracking(0.5)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(color.opacity(0.18)).foregroundColor(color)
            .clipShape(Capsule())
    }

    private var thermalDescriptor: (String, Color) {
        switch viewModel.thermalState {
        case .nominal:  return ("NOMINAL", Theme.moduleColor(.processes))
        case .fair:     return ("FAIR", Theme.moduleColor(.privacy))
        case .serious:  return ("SERIOUS", Theme.moduleColor(.shredder))
        case .critical: return ("CRITICAL", Color(red: 0.95, green: 0.3, blue: 0.3))
        @unknown default: return ("NOMINAL", Theme.moduleColor(.processes))
        }
    }

    // MARK: Why are my fans loud

    private var loudSection: some View {
        let top = Array((processVM.topApps + processVM.topBackground)
            .sorted { $0.cpuPercent > $1.cpuPercent }.prefix(5))
        return VStack(alignment: .leading, spacing: 12) {
            Text("Why are my fans loud").font(.system(size: 13, weight: .semibold))
            Text("The processes working your CPU hardest right now — quitting a runaway one lets the machine cool and the fans wind down.")
                .font(.system(size: 11)).foregroundColor(.secondary)
            Divider()
            if top.isEmpty {
                Text("Sampling processes…").font(.system(size: 11)).foregroundColor(.secondary)
            } else {
                ForEach(top) { p in
                    HStack(spacing: 10) {
                        if let icon = p.icon { Image(nsImage: icon).resizable().frame(width: 22, height: 22) }
                        else { Image(systemName: "gearshape").foregroundColor(.secondary).frame(width: 22) }
                        Text(p.name).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(String(format: "%.0f%%", p.cpuPercent))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(p.cpuPercent > 50 ? Theme.moduleColor(.shredder) : .secondary)
                        Button("Quit") { processVM.quit(p) }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(Theme.Spacing.lg).glassCard()
    }

    private func infoCard(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundColor(accent)
            Text(text).font(.system(size: 12)).foregroundColor(.secondary)
            Spacer()
        }
        .padding(Theme.Spacing.lg).glassCard()
    }
}
