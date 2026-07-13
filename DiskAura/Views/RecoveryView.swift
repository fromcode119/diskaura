import SwiftUI

/// The Undo Center — a visible history of every move, organize, and cleanup this session, each
/// with a one-click Revert. Makes the trust story concrete: nothing DiskAura does is a one-way door.
struct RecoveryView: View {
    @ObservedObject var store = UndoHistoryStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9).fill(Theme.moduleColor(.processes).opacity(0.18)).frame(width: 34, height: 34)
                    Image(systemName: "arrow.uturn.backward").foregroundColor(Theme.moduleColor(.processes))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Recovery").font(.system(size: 15, weight: .semibold))
                    Text("Undo anything DiskAura moved or cleaned this session")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
                Spacer()
                Button("Close") { dismiss() }.buttonStyle(.bordered)
            }
            .padding(Theme.Spacing.md)
            Divider()

            if let message {
                Text(message).font(.system(size: 11)).foregroundColor(Theme.moduleColor(.processes))
                    .padding(.horizontal, Theme.Spacing.md).padding(.top, 8)
            }

            if store.entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 34)).foregroundStyle(.tertiary)
                    Text("Nothing to recover yet").font(.system(size: 12)).foregroundColor(.secondary)
                    Text("Moves, organizes and cleanups show up here — each reversible in one click.")
                        .font(.system(size: 11)).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).padding(30)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(store.entries) { entry in row(entry) }
                    }
                    .padding(Theme.Spacing.md)
                }
            }
        }
        .frame(width: 560, height: 460)
        .background(Theme.appBackground)
    }

    @ViewBuilder private func row(_ entry: UndoEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill").font(.system(size: 13)).foregroundColor(Theme.moduleColor(.scan))
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(.system(size: 12, weight: .medium))
                Text("\(entry.count) item\(entry.count == 1 ? "" : "s") · \(entry.date.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 10)).foregroundColor(.secondary)
            }
            Spacer()
            Button {
                let result = store.revert(entry)
                message = "Restored \(result.restored) item\(result.restored == 1 ? "" : "s")"
                    + (result.failed > 0 ? " · \(result.failed) couldn't be restored" : "")
            } label: {
                Label("Revert", systemImage: "arrow.uturn.backward").font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.pill(Theme.moduleColor(.processes)))
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Theme.panelBackground.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
