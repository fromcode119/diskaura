import Foundation
import FoundationModels

/// Non-gated check for whether the on-device model is usable — callable from any OS target so
/// views don't have to wrap availability around every reference to the macOS-26 service.
enum OnDeviceAI {
    static var isReady: Bool {
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        return false
    }
}

/// Turns a plain-English tidy-up instruction ("move PDFs older than 30 days to Archive") into a
/// structured, executable rule — entirely on the device's LLM. This is "Hazel without the learning
/// curve": no rule-builder UI to learn, just say what you want. macOS 26+ / Apple Silicon.
@available(macOS 26.0, *)
actor RuleParsingService {
    private let session: LanguageModelSession

    init() {
        session = LanguageModelSession(instructions: """
        You convert a user's plain-English file-tidying request into a structured rule. Extract:
        - extensions: the file types mentioned (lowercase, no dot); empty list if none/any.
        - olderThanDays: age threshold in days if the user says "older than…"; 0 if not mentioned.
        - largerThanMB: size threshold in megabytes if mentioned; 0 if not.
        - nameContains: a word the filename must contain if mentioned; empty if not.
        - action: choose exactly one —
            • "organize" when they want a folder SORTED/TIDIED into MULTIPLE folders (e.g. "organize my
              Downloads", "sort my files by type", "tidy up this folder", "clean up by date"). This is
              the common case for vague tidy-up requests with no single destination.
            • "move" ONLY when they name ONE specific destination folder to move matching files into
              (e.g. "move PDFs to Archive").
            • "trash" when they want files deleted/removed.
        - destination: for "move", the single target folder (e.g. "Archive"). For "organize", the scheme
          word the user used — "type", "topic", or "date" (default "type"). Empty for "trash".
        Interpret faithfully; do not invent filters the user didn't ask for.
        """)
        session.prewarm()
    }

    /// A rule uses sentinels (empty list / 0 / empty string) for "not specified" so the on-device
    /// model never has to emit nulls.
    @Generable
    struct ParsedRule {
        @Guide(description: "File extensions to match, lowercase without the dot, e.g. ['pdf','docx']. Empty for any type.")
        let extensions: [String]
        @Guide(description: "Match files older than this many days. 0 means no age filter.")
        let olderThanDays: Int
        @Guide(description: "Match files larger than this many megabytes. 0 means no size filter.")
        let largerThanMB: Int
        @Guide(description: "Match files whose name contains this text. Empty for no name filter.")
        let nameContains: String
        @Guide(description: "Either 'move' or 'trash'.")
        let action: String
        @Guide(description: "Destination subfolder name when moving (e.g. 'Archive'). Empty when trashing.")
        let destination: String
    }

    static var isAvailable: Bool {
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        return false
    }

    /// Parses to the plain, OS-agnostic `FileRule` the matching engine consumes.
    func parse(_ english: String) async -> FileRule? {
        let options = GenerationOptions(sampling: .greedy, maximumResponseTokens: 120)
        do {
            let response = try await session.respond(
                to: "Convert this request into a rule:\n\"\(english)\"",
                generating: ParsedRule.self, options: options)
            let p = response.content
            let a = p.action.lowercased()
            let action: String
            if a.contains("trash") || a.contains("delete") { action = "trash" }
            else if a.contains("organi") || a.contains("sort") || a.contains("tidy") { action = "organize" }
            else { action = "move" }
            return FileRule(
                extensions: p.extensions.map { $0.lowercased().replacingOccurrences(of: ".", with: "") }.filter { !$0.isEmpty },
                olderThanDays: max(0, p.olderThanDays),
                largerThanMB: max(0, p.largerThanMB),
                nameContains: p.nameContains.trimmingCharacters(in: .whitespaces),
                action: action,
                destination: p.destination.trimmingCharacters(in: .whitespaces))
        } catch {
            return nil
        }
    }
}
