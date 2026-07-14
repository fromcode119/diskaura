import SwiftUI

/// A conversational, on-device storage assistant. Ask "why is my disk full?" or "what can I safely
/// delete?" and it answers from the real facts about this Mac — no cloud, nothing leaves the device.
struct AssistantView: View {
    @ObservedObject var scanVM: ScanViewModel
    @ObservedObject var router: AppRouter

    @State private var messages: [Message] = []
    @State private var input: String = ""
    @State private var isPreparing = false
    @State private var isThinking = false
    @State private var facts: String?
    @State private var serviceBox: ServiceBox?

    private struct Message: Identifiable {
        let id = UUID()
        let fromUser: Bool
        let text: String
    }

    /// Boxes the availability-gated actor so `@State` doesn't need the macOS-26 attribute.
    private final class ServiceBox {
        let make: (String) -> Any
        var instance: Any?
        init() {
            if #available(macOS 26.0, *) { make = { AssistantService(facts: $0) } }
            else { make = { _ in NSObject() } }
        }
    }

    private let suggestions = [
        "Why is my disk full?",
        "What can I safely delete?",
        "What's taking the most space?",
        "How do I free up 20 GB?",
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if !OnDeviceAI.isReady {
                unavailable
            } else {
                conversation
                inputBar
            }
        }
        .onAppear { if facts == nil { prepare() } }
    }

    private var header: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(Theme.moduleColor(.smartRules).opacity(0.18)).frame(width: 34, height: 34)
                Image(systemName: "sparkle").foregroundColor(Theme.moduleColor(.smartRules))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Assistant").font(.system(size: 16, weight: .semibold))
                Text(isPreparing ? "Reading your disk…" : "On-device — nothing leaves your Mac")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer()
            if isPreparing { ProgressView().controlSize(.small) }
        }
        .padding(Theme.Spacing.md)
    }

    private var unavailable: some View {
        Text("The assistant needs Apple Intelligence (macOS 26 on Apple Silicon).")
            .font(.system(size: 12)).foregroundColor(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity).padding(30)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if messages.isEmpty {
                        emptyState
                    }
                    ForEach(messages) { message in
                        VStack(alignment: message.fromUser ? .trailing : .leading, spacing: 6) {
                            bubble(message)
                            if !message.fromUser, let tab = suggestedTab(message.text) {
                                Button { router.selectedTab = tab } label: {
                                    Label("Open \(tab.rawValue)", systemImage: "arrow.right.circle.fill")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(Theme.moduleColor(.smartRules))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: message.fromUser ? .trailing : .leading)
                        .id(message.id)
                    }
                    if isThinking {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Thinking…").font(.system(size: 12)).foregroundColor(.secondary)
                        }
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .onChange(of: messages.count) {
                if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ask me anything about your storage.").font(.system(size: 13)).foregroundColor(.secondary)
            FlowChips(items: suggestions) { send($0) }
        }
        .padding(.vertical, 8)
    }

    private func bubble(_ message: Message) -> some View {
        HStack {
            if message.fromUser { Spacer(minLength: 40) }
            Text(.init(message.text))   // render **bold** section names as markdown
                .font(.system(size: 12.5))
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(message.fromUser ? Theme.moduleColor(.smartRules).opacity(0.9) : Theme.panelBackground)
                .foregroundColor(message.fromUser ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: 460, alignment: message.fromUser ? .trailing : .leading)
                .textSelection(.enabled)
            if !message.fromUser { Spacer(minLength: 40) }
        }
        .frame(maxWidth: .infinity, alignment: message.fromUser ? .trailing : .leading)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask about your disk…", text: $input)
                .textFieldStyle(.plain).font(.system(size: 13))
                .padding(10).background(Theme.panelBackground).clipShape(RoundedRectangle(cornerRadius: 9))
                .onSubmit { send(input) }
            Button { send(input) } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 22))
                    .foregroundColor(canSend ? Theme.moduleColor(.smartRules) : .secondary.opacity(0.5))
            }
            .buttonStyle(.plain).disabled(!canSend)
        }
        .padding(Theme.Spacing.md)
    }

    private var canSend: Bool { !input.trimmingCharacters(in: .whitespaces).isEmpty && !isThinking && !isPreparing }

    /// Detects which DiskAura section the reply pointed the user to, so we can offer a jump button.
    private func suggestedTab(_ text: String) -> SidebarTab? {
        let t = text.lowercased()
        if t.contains("cleanup") || t.contains("system junk") { return .cleanup }
        if t.contains("large") && t.contains("old") { return .largeOldFiles }
        if t.contains("duplicat") { return .duplicates }
        if t.contains("uninstall") { return .uninstaller }
        if t.contains("system data") { return .systemData }
        if t.contains("smart rules") { return .smartRules }
        if t.contains("privacy") { return .privacy }
        if t.contains("disk scan") || t.contains("sunburst") { return .scan }
        return nil
    }

    // MARK: - Logic

    private func prepare() {
        isPreparing = true
        let largest = scanVM.result?.root.flattenFiles()
            .sorted { $0.sizeBytes > $1.sizeBytes }.prefix(8)
            .map { (name: $0.name, bytes: $0.sizeBytes, path: $0.url.path) } ?? []
        Task {
            let built = await Task.detached(priority: .userInitiated) {
                buildFacts(largest: largest)
            }.value
            await MainActor.run {
                facts = built
                let box = ServiceBox()
                box.instance = box.make(built)
                serviceBox = box
                isPreparing = false
            }
        }
    }

    private func send(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespaces)
        guard !question.isEmpty, !isThinking else { return }
        input = ""
        messages.append(Message(fromUser: true, text: question))
        isThinking = true
        Task {
            // The service is built after the disk facts finish loading; if the user asks before
            // that (e.g. taps a suggestion while it still says "Reading your disk…"), wait for it
            // instead of silently dropping the question.
            while serviceBox?.instance == nil && isPreparing {
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
            let reply: String
            if #available(macOS 26.0, *), let service = serviceBox?.instance as? AssistantService {
                reply = await service.answer(question)
            } else {
                reply = "The assistant isn't available on this Mac."
            }
            await MainActor.run {
                isThinking = false
                messages.append(Message(fromUser: false, text: reply))
            }
        }
    }
}

/// Builds the grounding facts string from real disk data (runs the junk scan + volume stats).
private func buildFacts(largest: [(name: String, bytes: Int64, path: String)]) -> String {
    let report = SystemDataService.analyze()
    var lines: [String] = []
    lines.append("Disk: \(report.volumeFreeBytes.formattedBytes) free of \(report.volumeTotalBytes.formattedBytes) total (\(report.volumeUsedBytes.formattedBytes) used).")
    lines.append("Safely reclaimable right now: \(report.reclaimableTotal.formattedBytes).")
    if !report.reclaimable.isEmpty {
        let top = report.reclaimable.prefix(6).map { "\($0.title) \($0.bytes.formattedBytes)" }.joined(separator: ", ")
        lines.append("Reclaimable junk by category: \(top).")
    }
    if !report.systemManaged.isEmpty {
        let sys = report.systemManaged.map { "\($0.title) \($0.bytes.formattedBytes)" }.joined(separator: ", ")
        lines.append("System-managed (not removable): \(sys).")
    }
    if report.snapshotCount > 0 {
        lines.append("Local Time Machine snapshots: \(report.snapshotCount).")
    }
    if !largest.isEmpty {
        let files = largest.prefix(8).map { "\($0.name) (\($0.bytes.formattedBytes))" }.joined(separator: ", ")
        lines.append("Largest files in the last scanned folder: \(files).")
    } else {
        lines.append("No folder has been scanned yet in Disk Scan, so specific large-file details aren't available.")
    }
    return lines.joined(separator: "\n")
}

/// Simple wrapping chip row for the suggestion prompts.
private struct FlowChips: View {
    let items: [String]
    let onTap: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                Button { onTap(item) } label: {
                    Text(item).font(.system(size: 11)).foregroundColor(Theme.moduleColor(.smartRules))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Theme.moduleColor(.smartRules).opacity(0.12)).clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
