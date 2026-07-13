import SwiftUI

/// Smart Scan — the dashboard landing. A big disk-usage ring hero + circular live stats, then a
/// one-tap scan that aggregates system junk + browser caches + Trash into routed findings.
struct SmartScanView: View {
    @ObservedObject var router: AppRouter
    @StateObject private var viewModel = SmartScanViewModel()

    private var accent: Color { Theme.moduleColor(.smartScan) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    hero
                    miniStatsRow
                    if viewModel.hasScanned {
                        findingsSection
                    } else {
                        scanCTA
                    }
                }
                .padding(Theme.Spacing.lg)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear { viewModel.loadStats() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Smart Scan").font(Theme.TypeScale.title)
                Text("Your Mac at a glance — one tap to reclaim space")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer()
            if viewModel.hasScanned {
                Button { viewModel.scan() } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                    .buttonStyle(.gradientPill).disabled(viewModel.scanning)
            }
        }
        .padding(Theme.Spacing.md)
    }

    // MARK: - Hero ring

    private var hero: some View {
        let showReclaimable = viewModel.hasScanned && viewModel.reclaimableBytes > 0
        return RingGauge(
            fraction: showReclaimable
                ? Double(viewModel.reclaimableBytes) / Double(max(viewModel.diskTotal, 1))
                : viewModel.diskUsedFraction,
            centerValue: showReclaimable ? viewModel.reclaimableBytes.formattedBytes : viewModel.diskFree.formattedBytes,
            centerLabel: showReclaimable ? "reclaimable" : "free of \(viewModel.diskTotal.formattedBytes)",
            color: showReclaimable ? accent : Color(red: 0.36, green: 0.62, blue: 1.0),
            size: 220, lineWidth: 20
        )
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    private var miniStatsRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            MiniRingStat(fraction: viewModel.diskUsedFraction, value: viewModel.diskUsed.formattedBytes,
                         label: "Used", color: Color(red: 0.36, green: 0.62, blue: 1.0), icon: "internaldrive.fill")
            MiniRingStat(fraction: viewModel.memUsedFraction, value: viewModel.memUsedBytes.formattedMemoryBytes,
                         label: "Memory", color: Color(red: 0.68, green: 0.48, blue: 1.0), icon: "memorychip.fill")
            MiniRingStat(fraction: viewModel.diskTotal > 0 ? Double(viewModel.trashBytes) / Double(viewModel.diskTotal) : 0,
                         value: viewModel.trashBytes.formattedBytes,
                         label: "Trash", color: Color(red: 0.30, green: 0.80, blue: 0.90), icon: "trash.fill")
        }
    }

    private var scanCTA: some View {
        VStack(spacing: 12) {
            Button { viewModel.scan() } label: {
                Label(viewModel.scanning ? "Scanning…" : "Smart Scan", systemImage: "bolt.fill")
            }
            .buttonStyle(.gradientPill).controlSize(.large).disabled(viewModel.scanning)
            Text("Checks system junk, browser caches, and the Trash in one pass.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private var findingsSection: some View {
        VStack(spacing: Theme.Spacing.sm) {
            if viewModel.findings.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill").foregroundColor(Theme.moduleColor(.processes))
                    Text("Nothing to reclaim — you're all clean.").font(.system(size: 13, weight: .medium))
                    Spacer()
                }
                .padding(16).glassCard()
            } else {
                ForEach(viewModel.findings) { findingCard($0) }
            }
        }
    }

    private func findingCard(_ finding: SmartFinding) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(Theme.moduleColor(finding.tab).opacity(0.16)).frame(width: 38, height: 38)
                Image(systemName: finding.icon).font(.system(size: 16)).foregroundColor(Theme.moduleColor(finding.tab))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(finding.title).font(.system(size: 13.5, weight: .semibold))
                Text(finding.detail).font(.system(size: 10.5)).foregroundColor(.secondary)
            }
            Spacer()
            Text(finding.bytes.formattedBytes).font(.system(size: 15, weight: .bold, design: .rounded))
            Button { router.selectedTab = finding.tab } label: {
                Text("Review").font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.pill(Theme.moduleColor(finding.tab)))
        }
        .padding(14)
        .glassCard()
    }
}
