import SwiftUI

/// One package row — name, description, size, and the action that applies to its state.
struct BrewPackageRow: View {
    let package: BrewPackage
    let accent: Color
    let isBusy: Bool
    var onInstall: (() -> Void)?
    var onUpgrade: (() -> Void)?
    var onUninstall: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(accent.opacity(package.kind == .cask ? 0.10 : 0.18))
                    .frame(width: 30, height: 30)
                Image(systemName: package.kind == .cask ? "macwindow" : "shippingbox.fill")
                    .font(.system(size: 13)).foregroundColor(accent)
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(package.name).font(.system(size: 13, weight: .semibold))
                    if package.isOutdated {
                        Text("\(package.installedVersion) → \(package.latestVersion)")
                            .font(.system(size: 9.5, weight: .semibold))
                            .padding(.horizontal, 5).padding(.vertical, 1.5)
                            .background(Theme.moduleColor(.largeOldFiles).opacity(0.18))
                            .foregroundColor(Theme.moduleColor(.largeOldFiles))
                            .clipShape(Capsule())
                    } else if package.isInstalled {
                        Text(package.installedVersion).font(.system(size: 10)).foregroundColor(.secondary)
                    }
                }
                if !package.desc.isEmpty {
                    Text(package.desc).font(.system(size: 10.5)).foregroundColor(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if package.sizeBytes > 0 {
                Text(package.sizeBytes.formattedBytes)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
            }
            actions
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(hovering ? Color.white.opacity(0.04) : .clear)
        .onHover { hovering = $0 }
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: 6) {
            if package.isOutdated, let onUpgrade {
                // Row actions are compact, but all three share one sizing system so they line up.
                Button("Upgrade") { onUpgrade() }
                    .buttonStyle(.compactPill(Theme.moduleColor(.largeOldFiles))).disabled(isBusy)
            }
            if package.isInstalled, let onUninstall {
                Button("Remove") { onUninstall() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.moduleColor(.uninstaller))
                    .opacity(hovering ? 1 : 0.5)
                    .disabled(isBusy)
            }
            if !package.isInstalled, let onInstall {
                Button("Install") { onInstall() }
                    .buttonStyle(.compactPill(accent, filled: true)).disabled(isBusy)
            }
        }
        .frame(minWidth: 90, alignment: .trailing)
    }
}
