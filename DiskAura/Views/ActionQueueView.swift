import SwiftUI

struct ActionQueueView: View {
    @ObservedObject var viewModel: ActionQueueViewModel
    /// Called after a delete actually runs, so the caller can re-scan and drop the deleted
    /// files from every list — otherwise the breakdown / large-old lists keep showing files
    /// that are already gone, which reads as unreliable.
    var onExecuted: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var confirmPermanentDelete = false

    private var hasPermanent: Bool {
        viewModel.pendingActions.contains { $0.kind == .permanentDelete }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Theme.moduleColor(.uninstaller).opacity(0.18))
                        .frame(width: 34, height: 34)
                    Image(systemName: "trash.fill")
                        .foregroundColor(Theme.moduleColor(.uninstaller))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Review before deleting").font(.system(size: 15, weight: .semibold))
                    Text("These stay untouched until you press the button below.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding(Theme.Spacing.md)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(viewModel.pendingActions) { action in
                        HStack(spacing: 11) {
                            FileIconView(url: action.node.url, size: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(action.node.name).font(.system(size: 13, weight: .medium))
                                Text(action.node.path)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Text(label(for: action.kind))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(color(for: action.kind))
                            Text(action.node.sizeBytes.formattedBytes)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .frame(width: 74, alignment: .trailing)
                            Button {
                                viewModel.remove(action)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Keep this one — remove from the queue")
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, 9)
                        if action.id != viewModel.pendingActions.last?.id {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
            }

            Divider()

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Frees \(viewModel.totalBytes.formattedBytes)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Theme.moduleColor(.processes))
                    Text("\(viewModel.pendingActions.count) item\(viewModel.pendingActions.count == 1 ? "" : "s") · \(hasPermanent ? "permanent delete" : "moves to Trash (recoverable)")")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                if let error = viewModel.executionError {
                    Text(error).font(.caption).foregroundColor(.red).lineLimit(2)
                }
                Spacer()
                Button {
                    if hasPermanent {
                        confirmPermanentDelete = true
                    } else {
                        Task { await viewModel.executeAll(); onExecuted(); dismiss() }
                    }
                } label: {
                    if viewModel.isExecuting {
                        ProgressView().controlSize(.small)
                    } else {
                        Label(hasPermanent ? "Delete \(viewModel.pendingActions.count) permanently"
                                           : "Delete \(viewModel.pendingActions.count) now",
                              systemImage: "trash")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .buttonStyle(.pill(Theme.moduleColor(.uninstaller)))
                .disabled(viewModel.pendingActions.isEmpty || viewModel.isExecuting)
            }
            .padding(Theme.Spacing.md)
        }
        .frame(width: 660, height: 500)
        .background(Theme.appBackground)
        .alert("Permanently delete?", isPresented: $confirmPermanentDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Permanently Delete", role: .destructive) {
                Task { await viewModel.executeAll(); onExecuted(); dismiss() }
            }
        } message: {
            Text("Some queued items will be permanently deleted and cannot be recovered from Trash. This cannot be undone.")
        }
    }

    private func color(for kind: ActionKind) -> Color {
        switch kind {
        case .trash: return Theme.moduleColor(.uninstaller)
        case .permanentDelete: return .red
        case .archiveMove: return Theme.moduleColor(.duplicates)
        }
    }

    private func label(for kind: ActionKind) -> String {
        switch kind {
        case .trash: return "→ Trash"
        case .permanentDelete: return "Delete forever"
        case .archiveMove: return "Archive"
        }
    }
}
