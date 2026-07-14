import SwiftUI

/// Protection — an on-device scan of launch agents & daemons for known macOS adware families and
/// suspicious (script-dropper / orphaned) launch items. Detections quarantine to the Trash. Not a
/// full antivirus; it's the "is anything obviously nasty auto-starting?" check the Mac cleaners have.
struct ProtectionView: View {
    @ObservedObject var viewModel: ProtectionViewModel

    private var accent: Color { Theme.moduleColor(.protection) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .safeAreaInset(edge: .bottom) {
            if viewModel.hasScanned && !viewModel.threats.isEmpty { actionBar }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Protection").font(Theme.TypeScale.title)
                Text(viewModel.hasScanned
                     ? "\(viewModel.threats.count) item\(viewModel.threats.count == 1 ? "" : "s") flagged"
                     : "Scan launch items for adware and suspicious auto-start entries")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer()
            Button { viewModel.scan() } label: {
                if viewModel.scanning { ProgressView().controlSize(.small) }
                else { Label(viewModel.hasScanned ? "Rescan" : "Scan", systemImage: "shield.lefthalf.filled") }
            }
            .buttonStyle(.gradientPill).disabled(viewModel.scanning)
        }
        .padding(Theme.Spacing.md)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.scanning {
            VStack(spacing: 12) { ProgressView(); Text("Scanning launch items…").font(.system(size: 12)).foregroundColor(.secondary) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !viewModel.hasScanned {
            idleState
        } else if viewModel.threats.isEmpty {
            cleanState
        } else {
            ScrollView {
                VStack(spacing: Theme.Spacing.sm) {
                    if let n = viewModel.lastRemoved, n > 0 { banner("Quarantined \(n) item\(n == 1 ? "" : "s") to the Trash") }
                    ForEach(viewModel.threats) { threatCard($0) }
                }
                .padding(Theme.Spacing.lg)
            }
        }
    }

    private var idleState: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(accent.opacity(0.16)).frame(width: 100, height: 100)
                Image(systemName: "shield.lefthalf.filled").font(.system(size: 42)).foregroundColor(accent)
            }
            VStack(spacing: 5) {
                Text("Check for adware").font(Theme.TypeScale.sectionTitle)
                Text("Scans the launch agents and daemons that start automatically for known adware\nand script-based droppers — all on your Mac, nothing sent anywhere.")
                    .font(.system(size: 12)).foregroundColor(.secondary).multilineTextAlignment(.center)
            }
            Button { viewModel.scan() } label: { Label("Scan now", systemImage: "shield.lefthalf.filled") }
                .buttonStyle(.pill(accent)).controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(40)
    }

    private var cleanState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.shield.fill").font(.system(size: 46)).foregroundColor(Theme.moduleColor(.processes))
            Text("No adware or suspicious launch items found.").font(.system(size: 14, weight: .medium))
            Text("Your auto-start items look clean.").font(.system(size: 12)).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func threatCard(_ threat: Threat) -> some View {
        let on = viewModel.selected.contains(threat.id)
        return HStack(spacing: 12) {
            Button { viewModel.toggle(threat.id) } label: {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17)).foregroundColor(on ? accent : .secondary)
            }.buttonStyle(.plain)
            severityBadge(threat.severity)
            VStack(alignment: .leading, spacing: 2) {
                Text(threat.name).font(.system(size: 13, weight: .semibold))
                Text(threat.detail).font(.system(size: 10.5)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(threat.path.path).font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Button { NSWorkspace.shared.activateFileViewerSelecting([threat.path]) } label: {
                Image(systemName: "folder").font(.system(size: 11))
            }.buttonStyle(.plain).foregroundColor(.secondary).help("Show in Finder")
        }
        .padding(14)
        .glassCard()
    }

    private func severityBadge(_ s: ThreatSeverity) -> some View {
        let color = s == .high ? Theme.moduleColor(.uninstaller)
            : s == .medium ? Theme.moduleColor(.largeOldFiles) : Color.secondary
        return Text(s.label.uppercased())
            .font(.system(size: 8, weight: .bold))
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(color.opacity(0.18)).foregroundColor(color)
            .clipShape(Capsule())
    }

    private func banner(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.moduleColor(.processes))
            Text(text).font(.system(size: 12, weight: .medium)); Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Theme.moduleColor(.processes).opacity(0.10)).clipShape(RoundedRectangle(cornerRadius: 9))
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(accent.opacity(0.18)).frame(width: 34, height: 34)
                Image(systemName: "shield.lefthalf.filled").font(.system(size: 14)).foregroundColor(accent)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("\(viewModel.selected.count) selected to quarantine").font(.system(size: 13, weight: .semibold))
                Text("Moved to Trash — recoverable until you empty it").font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer()
            Button { viewModel.quarantine() } label: {
                if viewModel.removing { ProgressView().controlSize(.small) }
                else { Label("Quarantine", systemImage: "shield.slash").font(.system(size: 12.5, weight: .semibold)) }
            }
            .buttonStyle(.pill(accent)).disabled(viewModel.selected.isEmpty || viewModel.removing)
        }
        .padding(.horizontal, Theme.Spacing.md).padding(.vertical, 11)
        .background(.ultraThinMaterial)
        .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.border), alignment: .top)
    }
}
