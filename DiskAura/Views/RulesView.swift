import SwiftUI
import AppKit

/// Natural-language file rules — "Hazel without the learning curve". Type what you want in plain
/// English; the on-device LLM turns it into a rule, previews exactly which files match, and applies
/// it reversibly. No rule-builder to learn, and nothing leaves the Mac.
struct RulesView: View {
    @State private var folder: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    @State private var text: String = ""
    @State private var isParsing = false
    @State private var isApplying = false
    @State private var rule: FileRule?
    @State private var matches: [FileRuleEngine.Match] = []
    @State private var summary: String = ""
    @State private var message: String?

    private let examples = [
        "Move PDFs older than 30 days to Archive",
        "Trash zip files larger than 100 MB",
        "Move screenshots to a Screenshots folder",
        "Delete installers older than 2 months",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                header
                if !OnDeviceAI.isReady {
                    unavailable
                } else {
                    folderPicker
                    input
                    if let message { Text(message).font(.system(size: 11)).foregroundColor(Theme.moduleColor(.processes)) }
                    if rule != nil { previewCard }
                }
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.appGradient)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Smart Rules").font(.system(size: 22, weight: .bold))
            Text("Tidy up in plain English — parsed and run entirely on your Mac")
                .font(.system(size: 12)).foregroundColor(.secondary)
        }
    }

    private var unavailable: some View {
        Text("Natural-language rules need Apple Intelligence (macOS 26 on Apple Silicon).")
            .font(.system(size: 12)).foregroundColor(.secondary)
            .padding(20).glassCard()
    }

    private var folderPicker: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill").foregroundColor(Theme.moduleColor(.scan))
            Text(folder.path).font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.middle)
            Spacer()
            Button("Choose…") { chooseFolder() }
        }
        .padding(12).glassCard()
    }

    private var input: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("e.g. Move PDFs older than 30 days to Archive", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(10)
                    .background(Theme.panelBackground).clipShape(RoundedRectangle(cornerRadius: 8))
                    .onSubmit { parse() }
                Button { parse() } label: {
                    if isParsing { ProgressView().controlSize(.small) }
                    else { Label("Parse", systemImage: "wand.and.stars").font(.system(size: 13, weight: .semibold)) }
                }
                .buttonStyle(.pill(Theme.moduleColor(.processes)))
                .disabled(text.isEmpty || isParsing)
            }
            HStack(spacing: 6) {
                ForEach(examples, id: \.self) { example in
                    Button { text = example; parse() } label: {
                        Text(example).font(.system(size: 10)).foregroundColor(.secondary)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Theme.panelBackground.opacity(0.6)).clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder private var previewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rule").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary).tracking(0.7)
                    Text(summary).font(.system(size: 13, weight: .medium))
                }
                Spacer()
                Button { apply() } label: {
                    if isApplying { ProgressView().controlSize(.small) }
                    else { Label("Apply to \(matches.count)", systemImage: "checkmark.circle").font(.system(size: 13, weight: .semibold)) }
                }
                .buttonStyle(.pill(matches.isEmpty ? .secondary : Theme.moduleColor(.cleanup)))
                .disabled(matches.isEmpty || isApplying)
            }
            Divider()
            if matches.isEmpty {
                Text("No files in \(folder.lastPathComponent) match this rule.")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            } else {
                Text("\(matches.count) matching file\(matches.count == 1 ? "" : "s")")
                    .font(.system(size: 11)).foregroundColor(.secondary)
                ForEach(matches.prefix(30)) { match in
                    HStack(spacing: 10) {
                        ThumbnailView(url: match.url, size: 26)
                        Text(match.name).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(match.sizeBytes.formattedBytes).font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                if matches.count > 30 {
                    Text("+\(matches.count - 30) more").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(Theme.Spacing.lg).glassCard()
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Use Folder"
        if panel.runModal() == .OK, let url = panel.url { folder = url; if rule != nil { recomputeMatches() } }
    }

    private func parse() {
        guard OnDeviceAI.isReady, !text.isEmpty else { return }
        isParsing = true
        message = nil
        let request = text
        Task {
            guard #available(macOS 26.0, *) else { return }
            let service = RuleParsingService()
            let parsed = await service.parse(request)
            await MainActor.run {
                isParsing = false
                if let parsed {
                    rule = parsed
                    summary = FileRuleEngine.describe(parsed)
                    recomputeMatches()
                } else {
                    message = "Couldn't understand that — try rephrasing."
                }
            }
        }
    }

    private func recomputeMatches() {
        guard let rule else { return }
        // Always honour the rule's filter — "organize PDFs older than 30 days" must sort ONLY those
        // PDFs, not the whole folder. With no filter ("organize my files") this matches everything.
        matches = FileRuleEngine.matches(for: rule, in: folder)
    }

    private func apply() {
        guard let rule else { return }
        if rule.action == "organize" { applyOrganize(rule); return }
        isApplying = true
        let current = matches
        let target = folder
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                FileRuleEngine.apply(rule, matches: current, in: target)
            }.value
            await MainActor.run {
                isApplying = false
                if result.trashed {
                    UndoHistoryStore.shared.recordTrash(title: "Rule: trashed \(result.affected) file\(result.affected == 1 ? "" : "s")",
                                                        restorePairs: result.trashRestorePairs)
                } else {
                    UndoHistoryStore.shared.recordMoves(title: "Rule: moved \(result.affected) file\(result.affected == 1 ? "" : "s")",
                                                        movedPairs: result.movedPairs)
                }
                message = "Done — \(result.affected) file\(result.affected == 1 ? "" : "s") \(result.trashed ? "moved to Trash" : "moved"). Undo in Recovery."
                finishApply()
            }
        }
    }

    /// An "organize" rule hands off to the real organizer — sorting the folder's files into nested
    /// type/topic/date folders (the on-device AI when the scheme is Topic), not a flat move.
    private func applyOrganize(_ rule: FileRule) {
        isApplying = true
        let target = folder
        let scheme = FileRuleEngine.organizeScheme(rule)
        let urls = matches.map { $0.url }   // only the files the rule matched, not the whole folder
        Task {
            let plan = await OrganizeService.planForFiles(urls, scheme: scheme, in: target)
            let outcome = await Task.detached(priority: .userInitiated) { () -> OrganizeService.OrganizeResult? in
                try? OrganizeService.organize(plan, in: target)
            }.value
            await MainActor.run {
                isApplying = false
                if let outcome {
                    UndoHistoryStore.shared.recordMoves(
                        title: "Rule: organized \(outcome.movedCount) file\(outcome.movedCount == 1 ? "" : "s") (\(scheme.rawValue.lowercased()))",
                        movedPairs: outcome.movedPairs)
                    message = "Organized \(outcome.movedCount) file\(outcome.movedCount == 1 ? "" : "s") into \(outcome.foldersCreated) folder\(outcome.foldersCreated == 1 ? "" : "s"). Undo in Recovery."
                } else {
                    message = "Couldn't organize this folder."
                }
                finishApply()
            }
        }
    }

    private func finishApply() {
        rule = nil
        matches = []
        text = ""
    }
}
