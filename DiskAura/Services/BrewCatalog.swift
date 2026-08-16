import Foundation

/// The searchable Homebrew catalog. Search must feel instant, so it runs over a disk-cached copy
/// of formulae.brew.sh rather than shelling out to `brew search` per keystroke. Falls back to the
/// CLI when there is no cache and no network, so search still works offline — just slower.
actor BrewCatalog {
    private var packages: [BrewPackage] = []
    private var fetchedAt: Date?

    /// Catalog is refreshed in the background past this age; a stale cache is still served
    /// immediately rather than blocking the UI on a download.
    private static let maxAge: TimeInterval = 60 * 60 * 24 * 3

    private static var cacheURL: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DiskAura", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("brew-catalog.json")
    }

    var isStale: Bool {
        guard let fetchedAt else { return true }
        return Date().timeIntervalSince(fetchedAt) > Self.maxAge
    }
    var isLoaded: Bool { !packages.isEmpty }
    var count: Int { packages.count }

    /// Loads the on-disk cache if present. Cheap; safe to call on every appearance.
    func loadCache() {
        guard packages.isEmpty,
              let data = try? Data(contentsOf: Self.cacheURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["packages"] as? [[String: String]]
        else { return }
        packages = items.compactMap { item in
            guard let name = item["name"], let kindRaw = item["kind"],
                  let kind = BrewPackage.Kind(rawValue: kindRaw) else { return nil }
            var p = BrewPackage(name: name, kind: kind)
            p.desc = item["desc"] ?? ""
            p.latestVersion = item["version"] ?? ""
            return p
        }
        if let ts = root["fetchedAt"] as? Double { fetchedAt = Date(timeIntervalSince1970: ts) }
    }

    /// Downloads the full catalog. Network failure is not fatal — the cached copy keeps serving.
    func refresh(session: URLSession = .shared) async {
        async let formulae = fetch(Self.formulaeURL, kind: .formula, session: session)
        async let casks = fetch(Self.casksURL, kind: .cask, session: session)
        let combined = await formulae + casks
        guard !combined.isEmpty else { return }
        packages = combined
        fetchedAt = Date()
        persist()
    }

    private static let formulaeURL = URL(string: "https://formulae.brew.sh/api/formula.json")!
    private static let casksURL = URL(string: "https://formulae.brew.sh/api/cask.json")!

    private func fetch(_ url: URL, kind: BrewPackage.Kind, session: URLSession) async -> [BrewPackage] {
        guard let (data, _) = try? await session.data(from: url),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return items.compactMap { item in
            let name = (item["name"] as? String) ?? (item["token"] as? String)
            guard let name else { return nil }
            var p = BrewPackage(name: name, kind: kind)
            p.desc = (item["desc"] as? String) ?? ""
            p.latestVersion = kind == .cask
                ? ((item["version"] as? String) ?? "")
                : (((item["versions"] as? [String: Any])?["stable"] as? String) ?? "")
            p.homepage = (item["homepage"] as? String) ?? ""
            return p
        }
    }

    private func persist() {
        let items = packages.map {
            ["name": $0.name, "kind": $0.kind.rawValue, "desc": $0.desc, "version": $0.latestVersion]
        }
        let root: [String: Any] = ["packages": items, "fetchedAt": Date().timeIntervalSince1970]
        guard let data = try? JSONSerialization.data(withJSONObject: root) else { return }
        try? data.write(to: Self.cacheURL, options: .atomic)
    }

    /// Ranked search: exact name, then prefix, then substring, then description. Without ranking,
    /// searching "wget" buries wget under every package that merely mentions it.
    func search(_ query: String, limit: Int = 60) -> [BrewPackage] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        var scored: [(BrewPackage, Int)] = []
        for p in packages {
            let name = p.name.lowercased()
            let score: Int
            if name == q { score = 0 }
            else if name.hasPrefix(q) { score = 1 }
            else if name.contains(q) { score = 2 }
            else if p.desc.lowercased().contains(q) { score = 3 }
            else { continue }
            scored.append((p, score))
        }
        return scored.sorted {
            $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.name.count < $1.0.name.count
        }.prefix(limit).map(\.0)
    }

    /// Offline fallback when the catalog was never cached — slower, but search still works.
    static func cliSearch(_ query: String, service: BrewService) -> [BrewPackage] {
        guard let result = try? service.runner.run(["search", query]) , result.succeeded else { return [] }
        return result.stdout.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("==>") }
            .map { BrewPackage(name: $0, kind: .formula) }
    }
}
