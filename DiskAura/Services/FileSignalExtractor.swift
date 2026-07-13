import Foundation
import PDFKit
import Vision
import CoreServices

/// Gathers the cheapest-useful evidence about what a file IS, escalating depth only when the
/// cheap signals are thin — the "some files are easy, some need OCR/metadata" pipeline. The
/// result is a compact one-line description fed to the on-device LLM to name a folder.
///
/// Escalation ladder (stops as soon as it has enough):
///   1. Filename + extension + Spotlight `kind` (always — near-free).
///   2. Images → Vision scene labels (already downsampled thumbnail).
///   3. PDFs / text / code → first page or first bytes of real text.
///   4. Scanned PDFs with no text layer → OCR the first page.
enum FileSignalExtractor {
    /// A compact, LLM-ready description of one file. `isThin` means the cheap signals gave us
    /// little — the caller may choose to spend an LLM call rather than guess.
    struct Signal {
        let filename: String
        let kind: String          // human "PDF document", "JSON text", …
        let content: String       // extracted snippet / Vision labels (may be empty)
        var isThin: Bool { content.isEmpty && kind.isEmpty }

        /// One line for the model prompt.
        var promptLine: String {
            var parts = ["Filename: \(filename)"]
            if !kind.isEmpty { parts.append("Kind: \(kind)") }
            if !content.isEmpty { parts.append("Content: \(content)") }
            return parts.joined(separator: " | ")
        }
    }

    static func signal(for url: URL) -> Signal {
        let kind = spotlightKind(for: url)
        let content: String
        if MediaTopicClassifier.isImage(url) {
            content = imageLabels(for: url)
        } else if isTextLike(url) {
            content = textSnippet(for: url)
        } else if url.pathExtension.lowercased() == "pdf" {
            content = pdfSnippet(for: url)
        } else {
            content = ""   // office docs, binaries, archives → rely on name + kind
        }
        return Signal(filename: url.lastPathComponent, kind: kind, content: content)
    }

    // MARK: - Spotlight kind (near-free, already indexed by macOS)

    private static func spotlightKind(for url: URL) -> String {
        guard let item = MDItemCreate(nil, url.path as CFString),
              let kind = MDItemCopyAttribute(item, kMDItemKind) as? String else { return "" }
        return kind
    }

    // MARK: - Images → Vision labels

    private static func imageLabels(for url: URL) -> String {
        let labels = MediaTopicClassifier.rawLabels(for: url)
        return labels.isEmpty ? "" : "photo of \(labels.joined(separator: ", "))"
    }

    // MARK: - Text-like files

    private static let textExtensions: Set<String> = [
        "txt", "md", "csv", "json", "xml", "yaml", "yml", "html", "css", "js", "ts",
        "py", "swift", "java", "c", "cpp", "h", "sh", "rb", "go", "rs", "log", "rtf", "srt",
    ]

    private static func isTextLike(_ url: URL) -> Bool {
        textExtensions.contains(url.pathExtension.lowercased())
    }

    private static func textSnippet(for url: URL, limit: Int = 500) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 4096)) ?? Data()
        let text = String(decoding: data, as: UTF8.self)
        return clean(text, limit: limit)
    }

    // MARK: - PDFs (text layer, then OCR)

    private static func pdfSnippet(for url: URL, limit: Int = 500) -> String {
        guard let doc = PDFDocument(url: url), let page = doc.page(at: 0) else { return "" }
        if let text = page.string, !clean(text, limit: limit).isEmpty {
            return clean(text, limit: limit)
        }
        return ocr(page: page, limit: limit)   // scanned PDF — no text layer
    }

    private static func ocr(page: PDFPage, limit: Int) -> String {
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        guard size.width > 1, size.height > 1 else { return "" }
        let image = NSImage(size: size)
        image.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: ctx)
        }
        image.unlockFocus()
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return clean(lines.joined(separator: " "), limit: limit)
    }

    // MARK: - Helpers

    private static func clean(_ text: String, limit: Int) -> String {
        let collapsed = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(collapsed.prefix(limit))
    }
}
