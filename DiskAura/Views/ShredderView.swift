import SwiftUI

/// Secure Shredder — permanently erases files by overwriting their bytes before deleting,
/// so undelete tools can't recover them. A one-way door, so it's clearly separated from the
/// recoverable Trash-based cleanup elsewhere in the app.
struct ShredderView: View {
    @StateObject private var viewModel = ShredderViewModel()
    @State private var confirming = false

    private var accent: Color { Theme.moduleColor(.shredder) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .alert("Shred \(viewModel.selected.count) item\(viewModel.selected.count == 1 ? "" : "s") permanently?",
               isPresented: $confirming) {
            Button("Cancel", role: .cancel) {}
            Button("Shred", role: .destructive) { viewModel.shred() }
        } message: {
            Text("This overwrites the data and deletes it. It cannot be undone or recovered — this is not the Trash.")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Secure Shredder").font(Theme.TypeScale.title)
                Text("Permanently erase files so they can't be recovered")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer()
            Button { viewModel.chooseFiles() } label: {
                Label("Add files…", systemImage: "plus")
            }
            .buttonStyle(.gradientPill)
        }
        .padding(Theme.Spacing.md)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.selected.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(viewModel.selected, id: \.self) { url in
                        fileRow(url)
                    }
                }
                .padding(Theme.Spacing.lg)
            }
            .safeAreaInset(edge: .bottom) { actionBar }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(accent.opacity(0.16)).frame(width: 92, height: 92)
                Image(systemName: "flame.fill").font(.system(size: 34)).foregroundColor(accent)
            }
            VStack(spacing: 5) {
                Text("Nothing selected").font(Theme.TypeScale.sectionTitle)
                Text("Add files or folders to erase them beyond recovery.\nEverything else in DiskAura goes to the Trash — this does not.")
                    .font(.system(size: 12)).foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button { viewModel.chooseFiles() } label: {
                Label("Add files…", systemImage: "plus")
            }
            .buttonStyle(.pill(accent))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func fileRow(_ url: URL) -> some View {
        HStack(spacing: 12) {
            FileIconView(url: url, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                Text(url.deletingLastPathComponent().path).font(.system(size: 10))
                    .foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(viewModel.fileSize(url).formattedBytes)
                .font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
            Button { viewModel.remove(url) } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain).help("Remove from list")
        }
        .padding(12)
        .glassCard()
    }

    private var actionBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Security").font(.system(size: 10)).foregroundStyle(.secondary)
                Picker("", selection: $viewModel.passes) {
                    Text("Standard (1 pass)").tag(1)
                    Text("Thorough (3 passes)").tag(3)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 260)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(viewModel.selected.count) item\(viewModel.selected.count == 1 ? "" : "s") · \(viewModel.totalBytes.formattedBytes)")
                    .font(.system(size: 12, weight: .semibold))
                if let outcome = viewModel.outcome { resultText(outcome) }
            }
            Button { confirming = true } label: {
                if viewModel.running {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Shred permanently", systemImage: "flame.fill").font(.system(size: 12.5, weight: .semibold))
                }
            }
            .buttonStyle(.pill(accent))
            .disabled(viewModel.running || viewModel.selected.isEmpty)
        }
        .padding(.horizontal, Theme.Spacing.md).padding(.vertical, 11)
        .background(.ultraThinMaterial)
        .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.border), alignment: .top)
    }

    @ViewBuilder
    private func resultText(_ outcome: ShredOutcome) -> some View {
        switch outcome {
        case .done(let files, let bytes):
            Text("Erased \(files) file\(files == 1 ? "" : "s") · \(bytes.formattedBytes)")
                .font(.system(size: 10)).foregroundColor(Theme.moduleColor(.processes))
        case .failed(let msg):
            Text(msg).font(.system(size: 10)).foregroundColor(Theme.moduleColor(.uninstaller)).lineLimit(1)
        }
    }
}
