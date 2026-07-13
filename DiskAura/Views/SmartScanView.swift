import SwiftUI

/// Smart Scan — the one-tap overview. Runs the safe analyzers across the app and shows a single
/// combined "reclaimable" total plus routed findings that jump to the module handling each one.
struct SmartScanView: View {
    @ObservedObject var router: AppRouter
    @StateObject private var viewModel = SmartScanViewModel()

    private var accent: Color { Theme.moduleColor(.smartScan) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Smart Scan").font(Theme.TypeScale.title)
                Text("One tap to see everything you can reclaim")
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

    @ViewBuilder
    private var content: some View {
        if !viewModel.hasScanned {
            idleState
        } else {
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    heroTotal
                    if viewModel.findings.isEmpty {
                        allClear
                    } else {
                        ForEach(viewModel.findings) { finding in findingCard(finding) }
                    }
                }
                .padding(Theme.Spacing.lg)
            }
        }
    }

    private var idleState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle().fill(Theme.accentGradient).frame(width: 110, height: 110).opacity(0.9)
                if viewModel.scanning {
                    ProgressView().controlSize(.large).tint(.white)
                } else {
                    Image(systemName: "bolt.fill").font(.system(size: 44, weight: .medium)).foregroundColor(.white)
                }
            }
            VStack(spacing: 5) {
                Text(viewModel.scanning ? "Scanning…" : "Ready when you are")
                    .font(Theme.TypeScale.sectionTitle)
                Text("Smart Scan checks system junk, browser caches, and the Trash in one pass.")
                    .font(.system(size: 12)).foregroundColor(.secondary).multilineTextAlignment(.center)
            }
            Button { viewModel.scan() } label: {
                Label("Smart Scan", systemImage: "bolt.fill")
            }
            .buttonStyle(.gradientPill).controlSize(.large).disabled(viewModel.scanning)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var heroTotal: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(accent.opacity(0.16)).frame(width: 72, height: 72)
                Image(systemName: "bolt.fill").font(.system(size: 30)).foregroundColor(accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.totalBytes.formattedBytes)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("reclaimable across \(viewModel.findings.count) area\(viewModel.findings.count == 1 ? "" : "s")")
                    .font(.system(size: 12)).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(Theme.Spacing.md)
        .glassCard()
    }

    private var allClear: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 40)).foregroundColor(Theme.moduleColor(.processes))
            Text("Nothing to reclaim — you're all clean.").foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 30)
    }

    private func findingCard(_ finding: SmartFinding) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Theme.moduleColor(finding.tab).opacity(0.16)).frame(width: 36, height: 36)
                Image(systemName: finding.icon).font(.system(size: 15)).foregroundColor(Theme.moduleColor(finding.tab))
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
