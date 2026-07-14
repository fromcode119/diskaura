import Foundation

/// Swift-facing wrapper over the `DAPrivileged` Objective-C shim. Runs privileged shell commands
/// behind a SESSION-cached authorization, so the user types their password ONCE per app session
/// and every subsequent admin task runs without re-prompting — replacing the old per-task
/// `osascript … with administrator privileges` that prompted for every single action.
enum PrivilegedRunner {
    static func run(_ command: String) -> (ok: Bool, output: String, cancelled: Bool) {
        var status: Int32 = 0
        let output = DAPrivileged.run(command, status: &status) ?? ""
        return (status == 0, output, status == -2)
    }
}
