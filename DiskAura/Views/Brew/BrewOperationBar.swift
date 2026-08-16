import SwiftUI

/// Live operation status pinned to the bottom. A brew install can run for minutes — showing its
/// streamed output is the difference between "working" and "the button did nothing".
struct BrewOperationBar: View {
    let operation: BrewOperation
    let accent: Color
    let onDismiss: () -> Void
    @State private var showLog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showLog && !operation.log.isEmpty { logPane }
            HStack(spacing: 10) {
                icon
                VStack(alignment: .leading, spacing: 1) {
                    Text(headline).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                    Text(detail).font(.system(size: 10.5)).foregroundColor(.secondary).lineLimit(1)
                }
                Spacer()
                if !operation.log.isEmpty {
                    Button(showLog ? "Hide log" : "Show log") { showLog.toggle() }
                        .buttonStyle(.bordered).controlSize(.small)
                }
                if !operation.isRunning {
                    Button("Done") { onDismiss() }.buttonStyle(.pill(accent)).controlSize(.small)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
        .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.border), alignment: .top)
    }

    @ViewBuilder private var icon: some View {
        switch operation.state {
        case .running: ProgressView().controlSize(.small)
        case .succeeded: Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.moduleColor(.processes))
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundColor(Theme.moduleColor(.uninstaller))
        }
    }

    private var headline: String {
        switch operation.state {
        case .running: return operation.title + "…"
        case .succeeded(let m): return m
        case .failed(let m): return m
        }
    }

    /// While running, brew's own latest output line is the most useful status available.
    private var detail: String {
        switch operation.state {
        case .running:
            let secs = Int(Date().timeIntervalSince(operation.startedAt))
            let line = operation.currentLine
            return line.isEmpty ? "\(secs)s elapsed" : line
        case .succeeded: return "Finished"
        case .failed: return "See the log for the full output"
        }
    }

    private var logPane: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(operation.log.enumerated()), id: \.offset) { i, line in
                        Text(line).font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).id(i)
                    }
                }
                .padding(10)
            }
            .frame(height: 150)
            .onChange(of: operation.log.count) { _, n in proxy.scrollTo(n - 1, anchor: .bottom) }
        }
    }
}
