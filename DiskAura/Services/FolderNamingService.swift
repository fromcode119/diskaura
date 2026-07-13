import Foundation
import FoundationModels

/// Names a destination folder for a file using Apple's on-device LLM (Foundation Models,
/// macOS 26+). Free, offline, runs on the Neural Engine — the file's signals never leave the
/// Mac. Open-vocabulary: it invents a sensible folder for files it has never seen, so nothing
/// is dumped into a growing "Other". To keep names consistent it is told which folders already
/// exist and asked to reuse one when it fits.
@available(macOS 26.0, *)
actor FolderNamingService {
    private let session: LanguageModelSession

    init() {
        session = LanguageModelSession(instructions: """
        You sort a user's files into a tidy, nested folder tree. Given one file's broad type, \
        name, and a short description of its content, reply with the best folder PATH. Rules:
        - Return a path from GENERAL to SPECIFIC using '/' separators, 2 to 4 levels deep, e.g. \
          "Documents/Company/NeuroBodyGym", "Documents/Finance/Invoices", "Photos/Travel/2025".
        - The FIRST level is the broad type you are given (Documents, Photos, …). Go deeper only \
          when THIS file's content supports it (a company/vendor name, a project, a year, a topic).
        - Base the path ONLY on THIS file. Do NOT place it under a company/project/topic branch \
          unless this file itself clearly relates to that same company/project/topic. Example: a \
          Lufthansa boarding pass must NOT go under another company's folder; an Acme report must \
          NOT go under a different company. Different entity → different branch.
        - The existing-folders list is only a hint for consolidating genuinely-matching files; when \
          in doubt, create a new branch from this file's own content rather than forcing a reuse.
        - Each level is Title Case, 1-2 plain words. Never put a document under a photo branch or \
          a photo under a document branch. A scanned PDF is a document. Never use "Other" or "Misc".
        """)
        // Warm the model now so its first real call doesn't eat the ~10s cold-start latency.
        session.prewarm()
    }

    /// A folder path is a handful of tokens — cap the response and use greedy decoding so each
    /// call finishes fast and deterministically instead of generating a long reply.
    private static let fastOptions = GenerationOptions(sampling: .greedy, maximumResponseTokens: 40)

    /// True when the on-device model is ready to use (Apple Intelligence enabled, model present).
    static var isAvailable: Bool {
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        return false
    }

    @Generable
    struct FolderChoice {
        @Guide(description: "A nested folder PATH from general to specific with '/' separators, 2-4 levels, e.g. 'Documents/Company/NeuroBodyGym'. First level is the broad type. Never 'Other'/'Misc'.")
        let folderPath: String
    }


    /// Returns a nested folder path like "Documents/Company/NeuroBodyGym" (Title-Cased, '/'
    /// separated), or nil if the model errors. `existingFolders` are the paths chosen so far this
    /// run, offered to the model so it consolidates onto existing branches instead of inventing
    /// near-duplicates ("Documents/Travel" vs "Documents/Trips").
    func folderPath(for signal: FileSignalExtractor.Signal, category: String,
                    existingFolders: [String]) async -> String? {
        var prompt = "Choose the best folder path for this file.\nBroad type: \(category)\n\(signal.promptLine)"
        if !existingFolders.isEmpty {
            prompt += "\n\nExisting folders (reuse a branch ONLY if it clearly fits): \(existingFolders.joined(separator: ", "))"
        }
        do {
            let response = try await session.respond(to: prompt, generating: FolderChoice.self,
                                                     options: Self.fastOptions)
            return normalizePath(response.content.folderPath, category: category)
        } catch {
            return nil
        }
    }

    /// Broad file-type words the model might emit as a first level — we strip a leading one and
    /// substitute the file's real category so a video never nests under "Documents".
    private static let knownTypes: Set<String> = [
        "documents", "document", "photos", "photo", "images", "image", "videos", "video",
        "audio", "music", "archives", "archive", "code", "other", "misc", "files",
    ]

    /// Sanitise the model's path: split on '/', Title-Case each level, strip illegal characters,
    /// drop empties, cap depth at 5, and guarantee the broad type is the first level.
    private func normalizePath(_ raw: String, category: String) -> String? {
        let illegal = CharacterSet(charactersIn: ":\\")
        var parts = raw.split(separator: "/").map { component -> String in
            let cleaned = component
                .components(separatedBy: illegal).joined(separator: " ")
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return titleCase(cleaned)
        }.filter { !$0.isEmpty && $0 != "Other" && $0 != "Misc" }
        // Drop a leading broad-type word the model may have guessed (right or WRONG) — we always
        // re-prefix the real category next. This stops "Videos/Documents/Company/Hotels" when the
        // model wrongly labels a video as a document.
        if let first = parts.first, Self.knownTypes.contains(first.lowercased()) {
            parts.removeFirst()
        }
        parts.insert(category, at: 0)
        parts = parts.filter { !$0.isEmpty }
        if parts.count == 1 { return parts[0] }   // just the type, no usable sub-topic
        return parts.prefix(5).joined(separator: "/")
    }

    /// Title-cases a level, but PRESERVES intentional brand casing (camelCase / mixed case such as
    /// "NeuroBodyTech" or "iPhone") so folder names aren't flattened to "Neurobodytech".
    private func titleCase(_ s: String) -> String {
        guard !s.isEmpty else { return s }
        if s.dropFirst().contains(where: { $0.isUppercase }) { return s }   // camelCase / brand — keep
        return s.capitalized
    }
}
