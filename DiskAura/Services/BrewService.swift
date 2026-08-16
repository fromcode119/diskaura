import Foundation

/// Preview of what a destructive brew command WOULD do. Every destructive action shows one of
/// these first — brew deletes immediately with no Trash step, so the preview is the safety net.
struct BrewPreview {
    let lines: [String]
    let reclaimableBytes: Int64
}

/// Talks to Homebrew. Builds argument ARRAYS (never shell strings), parses `--json=v2` for
/// installed state, and gates destructive actions behind dry-run previews and a dependency check.
struct BrewService {
    let runner: BrewCommandRunning
    let environment: BrewEnvironment

    // MARK: - Argument construction
    //
    // Kept as pure functions so tests can assert that a hostile package name stays a single
    // argument element instead of becoming executable text.

    static func installArguments(_ pkg: BrewPackage) -> [String] {
        pkg.kind == .cask ? ["install", "--cask", pkg.name] : ["install", pkg.name]
    }
    static func uninstallArguments(_ pkg: BrewPackage, dryRun: Bool = false) -> [String] {
        var args = ["uninstall"]
        if pkg.kind == .cask { args.append("--cask") }
        if dryRun { args.append("--dry-run") }
        args.append(pkg.name)
        return args
    }
    static func upgradeArguments(_ pkg: BrewPackage?) -> [String] {
        guard let pkg else { return ["upgrade"] }
        return pkg.kind == .cask ? ["upgrade", "--cask", pkg.name] : ["upgrade", pkg.name]
    }
    static func cleanupArguments(dryRun: Bool) -> [String] {
        dryRun ? ["cleanup", "-n"] : ["cleanup"]
    }
    static func usesArguments(_ name: String) -> [String] { ["uses", "--installed", name] }

    // MARK: - Installed state

    /// Installed formulae and casks with versions and outdated flags, from brew's own JSON.
    func installedPackages() throws -> [BrewPackage] {
        let result = try runner.run(["info", "--json=v2", "--installed"])
        guard result.succeeded else { return [] }
        return Self.parseInstalled(json: result.stdout)
    }

    static func parseInstalled(json: String) -> [BrewPackage] {
        guard let data = json.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return [] }

        var out: [BrewPackage] = []
        for f in (root["formulae"] as? [[String: Any]]) ?? [] {
            guard let name = f["name"] as? String else { continue }
            let installed = (f["installed"] as? [[String: Any]])?.first
            var pkg = BrewPackage(name: name, kind: .formula)
            pkg.installedVersion = (installed?["version"] as? String) ?? ""
            pkg.latestVersion = ((f["versions"] as? [String: Any])?["stable"] as? String) ?? ""
            pkg.desc = (f["desc"] as? String) ?? ""
            pkg.homepage = (f["homepage"] as? String) ?? ""
            pkg.isOutdated = (f["outdated"] as? Bool) ?? false
            out.append(pkg)
        }
        for c in (root["casks"] as? [[String: Any]]) ?? [] {
            guard let token = c["token"] as? String else { continue }
            var pkg = BrewPackage(name: token, kind: .cask)
            // Casks report `installed` as a plain version string, unlike formulae.
            pkg.installedVersion = (c["installed"] as? String) ?? ""
            pkg.latestVersion = (c["version"] as? String) ?? ""
            pkg.desc = (c["desc"] as? String) ?? ""
            pkg.homepage = (c["homepage"] as? String) ?? ""
            pkg.isOutdated = (c["outdated"] as? Bool) ?? false
            out.append(pkg)
        }
        return out.sorted { $0.name < $1.name }
    }

    // MARK: - Dependency guard

    /// Installed packages that depend on `name`. Non-empty means removing it would break them.
    func dependents(of name: String) throws -> [String] {
        let result = try runner.run(Self.usesArguments(name))
        guard result.succeeded else { return [] }
        return result.stdout.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Removal is refused while anything still depends on the package — brew would either fail or
    /// leave the dependents broken.
    func canUninstall(_ name: String) throws -> Bool { try dependents(of: name).isEmpty }

    // MARK: - Previews

    func previewUninstall(_ pkg: BrewPackage) throws -> BrewPreview {
        let result = try runner.run(Self.uninstallArguments(pkg, dryRun: true))
        return Self.parsePreview(result.stdout + "\n" + result.stderr)
    }

    func previewCleanup() throws -> BrewPreview {
        let result = try runner.run(Self.cleanupArguments(dryRun: true))
        return Self.parsePreview(result.stdout + "\n" + result.stderr)
    }

    /// Pulls the freeable byte count out of brew's own summary line, e.g.
    /// "This operation would free approximately 462.9MB of disk space."
    static func parsePreview(_ text: String) -> BrewPreview {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        var bytes: Int64 = 0
        if let line = lines.last(where: { $0.contains("would free") || $0.contains("freed") }) {
            bytes = parseSize(in: line)
        }
        return BrewPreview(lines: lines, reclaimableBytes: bytes)
    }

    /// Parses "462.9MB" / "1.2GB" / "800KB" out of a sentence. Uses brew's binary-ish convention.
    static func parseSize(in line: String) -> Int64 {
        let pattern = #"([0-9]+(?:\.[0-9]+)?)\s*(KB|MB|GB|TB|B)\b"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let m = re.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let numRange = Range(m.range(at: 1), in: line),
              let unitRange = Range(m.range(at: 2), in: line),
              let value = Double(line[numRange])
        else { return 0 }
        let multiplier: Double
        switch line[unitRange].uppercased() {
        case "KB": multiplier = 1024
        case "MB": multiplier = 1024 * 1024
        case "GB": multiplier = 1024 * 1024 * 1024
        case "TB": multiplier = 1024 * 1024 * 1024 * 1024
        default: multiplier = 1
        }
        return Int64(value * multiplier)
    }

    // MARK: - Sizes

    /// On-disk size of a package, read from the Cellar/Caskroom rather than asked of brew (brew has
    /// no fast size query). Physical blocks, matching how the rest of the app measures.
    func sizeOnDisk(_ pkg: BrewPackage) -> Int64 {
        let base = pkg.kind == .cask ? environment.caskroomURL : environment.cellarURL
        return Self.directorySize(at: base.appendingPathComponent(pkg.name))
    }

    static func directorySize(at url: URL) -> Int64 {
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in e {
            var s = stat()
            if lstat(f.path, &s) == 0, (s.st_mode & S_IFMT) != S_IFLNK { total += Int64(s.st_blocks) * 512 }
        }
        return total
    }
}
