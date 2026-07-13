import SwiftUI

/// Privacy — clears browser caches, cookies, and history for Safari / Chrome / Firefox.
/// Everything goes to the Trash (recoverable). Sensitive items (cookies/history) are guarded
/// when the browser is open, since clearing a live profile database can corrupt it.
struct PrivacyView: View {
    @StateObject private var viewModel = PrivacyViewModel()

    private var accent: Color { Theme.moduleColor(.privacy) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .safeAreaInset(edge: .bottom) {
            if viewModel.hasScanned && !viewModel.items.isEmpty { cleanBar }
        }
        .onAppear { if !viewModel.hasScanned { viewModel.scan() } }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Privacy").font(Theme.TypeScale.title)
                Text(viewModel.hasScanned
                     ? "\(viewModel.totalBytes.formattedBytes) of browser traces found"
                     : "Clear browsing traces from Safari, Chrome and Firefox")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer()
            Button { viewModel.scan() } label: {
                Label(viewModel.hasScanned ? "Rescan" : "Scan", systemImage: "hand.raised.fill")
            }
            .buttonStyle(.gradientPill)
        }
        .padding(Theme.Spacing.md)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.scanning {
            VStack(spacing: 12) { ProgressView(); Text("Scanning browsers…").font(.system(size: 12)).foregroundColor(.secondary) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.items.isEmpty && viewModel.hasScanned {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.shield.fill").font(.system(size: 40)).foregroundColor(Theme.moduleColor(.processes))
                Text("No browser traces to clear.").foregroundColor(.secondary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    if let done = viewModel.lastCleaned, done.count > 0 {
                        banner("Cleared \(done.bytes.formattedBytes) to the Trash")
                    }
                    ForEach(PrivacyBrowser.allCases, id: \.self) { browser in
                        let group = viewModel.items.filter { $0.browser == browser }
                        if !group.isEmpty { browserCard(browser, group) }
                    }
                }
                .padding(Theme.Spacing.lg)
            }
        }
    }

    private func browserCard(_ browser: PrivacyBrowser, _ group: [PrivacyItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: browser.icon).font(.system(size: 16)).foregroundColor(accent).frame(width: 24)
                Text(browser.rawValue).font(.system(size: 14, weight: .semibold))
                if group.first?.browserRunning == true {
                    Label("Running — quit to clear cookies & history", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Theme.moduleColor(.largeOldFiles))
                }
                Spacer()
            }
            .padding(.bottom, 6)
            ForEach(group) { item in itemRow(item) }
        }
        .padding(14)
        .glassCard()
    }

    private func itemRow(_ item: PrivacyItem) -> some View {
        let blocked = item.category.sensitive && item.browserRunning
        let on = viewModel.selected.contains(item.id)
        return HStack(spacing: 11) {
            Button { viewModel.toggle(item.id) } label: {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16)).foregroundColor(on ? Theme.moduleColor(.processes) : .secondary)
            }
            .buttonStyle(.plain).disabled(blocked)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.category.rawValue).font(.system(size: 12.5, weight: .medium))
                Text(item.category.detail).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer()
            Text(item.sizeBytes.formattedBytes).font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(blocked ? .secondary : .primary)
        }
        .padding(.vertical, 6)
        .opacity(blocked ? 0.5 : 1)
    }

    private func banner(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.moduleColor(.processes))
            Text(text).font(.system(size: 12, weight: .medium))
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Theme.moduleColor(.processes).opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    private var cleanBar: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(accent.opacity(0.18)).frame(width: 34, height: 34)
                Image(systemName: "hand.raised.fill").font(.system(size: 14)).foregroundColor(accent)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("\(viewModel.selectedBytes.formattedBytes) selected").font(.system(size: 13, weight: .semibold))
                Text("Moved to Trash — recoverable until you empty it").font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer()
            Button { viewModel.clean() } label: {
                if viewModel.cleaning { ProgressView().controlSize(.small) }
                else { Label("Clear traces", systemImage: "hand.raised.fill").font(.system(size: 12.5, weight: .semibold)) }
            }
            .buttonStyle(.pill(accent))
            .disabled(viewModel.selectedBytes == 0 || viewModel.cleaning)
        }
        .padding(.horizontal, Theme.Spacing.md).padding(.vertical, 11)
        .background(.ultraThinMaterial)
        .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.border), alignment: .top)
    }
}
