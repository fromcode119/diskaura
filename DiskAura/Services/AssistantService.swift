import Foundation
import FoundationModels

/// DiskAura's on-device storage assistant — answers "why is my disk full?", "what can I safely
/// delete?", "what's taking all my space?" in plain language, grounded ONLY in the real facts we
/// gathered about this Mac (so it can't hallucinate files or numbers). Fully local via Apple's
/// Foundation Models; the facts never leave the device. macOS 26+.
@available(macOS 26.0, *)
actor AssistantService {
    private let session: LanguageModelSession

    init(facts: String) {
        session = LanguageModelSession(instructions: """
        You are DiskAura's friendly storage assistant, running entirely on the user's Mac. Answer
        their questions about disk space using ONLY the facts below — never invent files, sizes, or
        numbers you weren't given.

        Style: reply in 2-3 short sentences of natural PROSE — no bullet lists or headers. Cite the
        one or two most relevant real numbers. ALWAYS end by naming the single DiskAura section to
        open next: Cleanup (junk/caches), Large & Old (big stale files), Duplicates (identical &
        look-alike files), System Data (the "System Data" breakdown), Smart Rules (plain-English
        tidy-up), or Uninstaller (apps + leftovers). If the facts don't cover the question, say so
        briefly and suggest which scan to run.

        FACTS ABOUT THIS MAC:
        \(facts)
        """)
        session.prewarm()
    }

    static var isAvailable: Bool { OnDeviceAI.isReady }

    func answer(_ question: String) async -> String {
        let options = GenerationOptions(sampling: .greedy, maximumResponseTokens: 260)
        do {
            let response = try await session.respond(to: question, options: options)
            return response.content
        } catch {
            return "I couldn't answer that just now — try rephrasing, or open the relevant section directly."
        }
    }
}
