import SwiftUI

/// System maintenance — one-tap upkeep tasks (free RAM, flush DNS, rebuild indexes, clear caches).
/// Admin tasks show a lock badge and trigger a single macOS auth prompt when run.
struct MaintenanceView: View {
    @StateObject private var viewModel = MaintenanceViewModel()

    private var accent: Color { Theme.moduleColor(.maintenance) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(viewModel.tasks) { task in
                        taskCard(task)
                    }
                    footnote
                }
                .padding(Theme.Spacing.lg)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Maintenance").font(Theme.TypeScale.title)
                Text("One-tap upkeep that keeps macOS fast and glitch-free")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer()
            Button { viewModel.runAll() } label: {
                if viewModel.runningAll {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Run all", systemImage: "bolt.fill")
                }
            }
            .buttonStyle(.gradientPill)
            .disabled(viewModel.runningAll)
        }
        .padding(Theme.Spacing.md)
    }

    private func taskCard(_ task: MaintenanceTask) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(accent.opacity(0.16)).frame(width: 34, height: 34)
                Image(systemName: task.icon).font(.system(size: 15)).foregroundColor(accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(task.title).font(.system(size: 13, weight: .semibold))
                    if task.needsAdmin {
                        Label("Admin", systemImage: "lock.fill")
                            .font(.system(size: 8, weight: .bold))
                            .labelStyle(.titleAndIcon)
                            .padding(.horizontal, 5).padding(.vertical, 1.5)
                            .background(Color.white.opacity(0.08))
                            .foregroundColor(.secondary)
                            .clipShape(Capsule())
                    }
                }
                Text(task.detail).font(.system(size: 10.5)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let outcome = viewModel.results[task.id] {
                    outcomeLabel(outcome)
                }
            }
            Spacer(minLength: 8)
            runButton(task)
        }
        .padding(14)
        .glassCard()
    }

    @ViewBuilder
    private func outcomeLabel(_ outcome: MaintenanceOutcome) -> some View {
        switch outcome {
        case .success(let msg):
            Label(msg, systemImage: "checkmark.circle.fill")
                .font(.system(size: 10)).foregroundColor(Theme.moduleColor(.processes))
                .lineLimit(2).padding(.top, 2)
        case .failure(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 10)).foregroundColor(Theme.moduleColor(.uninstaller))
                .lineLimit(2).padding(.top, 2)
        case .cancelled:
            Label("Cancelled", systemImage: "xmark.circle")
                .font(.system(size: 10)).foregroundColor(.secondary).padding(.top, 2)
        }
    }

    private func runButton(_ task: MaintenanceTask) -> some View {
        Button { viewModel.run(task) } label: {
            if viewModel.isRunning(task.id) {
                ProgressView().controlSize(.small)
            } else {
                Text("Run").font(.system(size: 12, weight: .semibold))
            }
        }
        .buttonStyle(.pill(accent))
        .disabled(viewModel.isRunning(task.id))
    }

    private var footnote: some View {
        Text("All actions are standard, reversible macOS maintenance — nothing is deleted. Admin tasks ask for your password once.")
            .font(.system(size: 10)).foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }
}
