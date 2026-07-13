import Foundation
import AppKit

/// Drives the Shredder tab: the file selection, pass count, and last outcome.
@MainActor
final class ShredderViewModel: ObservableObject {
    @Published var selected: [URL] = []
    @Published var passes: Int = 1
    @Published private(set) var running = false
    @Published private(set) var outcome: ShredOutcome?

    var totalBytes: Int64 {
        selected.reduce(0) { $0 + (fileSize($1)) }
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose files or folders to securely erase"
        if panel.runModal() == .OK {
            let existing = Set(selected.map { $0.standardizedFileURL })
            for url in panel.urls where !existing.contains(url.standardizedFileURL) {
                selected.append(url)
            }
            outcome = nil
        }
    }

    func remove(_ url: URL) {
        selected.removeAll { $0 == url }
    }

    func clear() {
        selected.removeAll()
        outcome = nil
    }

    func shred() {
        guard !running, !selected.isEmpty else { return }
        running = true
        outcome = nil
        let urls = selected
        let passes = self.passes
        Task {
            let result = await SecureShredService.shred(urls, passes: passes)
            running = false
            outcome = result
            if case .done = result { selected.removeAll() }
        }
    }

    func fileSize(_ url: URL) -> Int64 {
        (try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]))
            .flatMap { $0.totalFileAllocatedSize ?? $0.fileSize }
            .map(Int64.init) ?? 0
    }
}
