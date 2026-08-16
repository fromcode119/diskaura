import Foundation

/// Result of one brew invocation.
struct BrewResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32
    var succeeded: Bool { exitCode == 0 }
}

/// Runs brew commands. Injectable so tests never touch a real Homebrew installation — a suite that
/// could install or uninstall packages on the developer's machine is not an acceptable test suite.
protocol BrewCommandRunning {
    func run(_ arguments: [String]) throws -> BrewResult
    /// Streaming variant for long operations (installs take minutes). `onLine` fires per output
    /// line so the UI can show real progress instead of freezing.
    func stream(_ arguments: [String], onLine: @escaping (String) -> Void) throws -> BrewResult
}

/// Real runner. Arguments are passed to `Process` as an ARRAY — never joined into a shell string —
/// so a package name containing `;`, backticks or quotes is data, not code.
struct ProcessBrewRunner: BrewCommandRunning {
    let binaryPath: String

    func run(_ arguments: [String]) throws -> BrewResult {
        try execute(arguments, onLine: nil)
    }

    func stream(_ arguments: [String], onLine: @escaping (String) -> Void) throws -> BrewResult {
        try execute(arguments, onLine: onLine)
    }

    private func execute(_ arguments: [String], onLine: ((String) -> Void)?) throws -> BrewResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = arguments          // ARRAY — no shell, no interpolation
        // Non-interactive: brew must never sit waiting on a TTY prompt we can't answer.
        var env = ProcessInfo.processInfo.environment
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        env["HOMEBREW_NO_COLOR"] = "1"
        process.environment = env

        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()

        var stdout = "", stderr = ""
        if let onLine {
            // Read incrementally so output appears while the command is still running.
            let handle = outPipe.fileHandleForReading
            var buffer = ""
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                let text = String(data: chunk, encoding: .utf8) ?? ""
                stdout += text
                buffer += text
                while let nl = buffer.firstIndex(of: "\n") {
                    onLine(String(buffer[..<nl]))
                    buffer = String(buffer[buffer.index(after: nl)...])
                }
            }
            if !buffer.isEmpty { onLine(buffer) }
            stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        } else {
            stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        }
        process.waitUntilExit()
        return BrewResult(stdout: stdout, stderr: stderr, exitCode: process.terminationStatus)
    }
}
