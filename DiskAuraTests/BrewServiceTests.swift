import XCTest
@testable import DiskAura

/// Records what it was asked to run and returns canned output. Nothing here ever executes brew —
/// a suite that could install or uninstall packages on a real machine is not acceptable.
final class FakeBrewRunner: BrewCommandRunning {
    var receivedArgs: [[String]] = []
    var stdout = ""
    var stderr = ""
    var exitCode: Int32 = 0

    func run(_ arguments: [String]) throws -> BrewResult {
        receivedArgs.append(arguments)
        return BrewResult(stdout: stdout, stderr: stderr, exitCode: exitCode)
    }
    func stream(_ arguments: [String], onLine: @escaping (String) -> Void) throws -> BrewResult {
        receivedArgs.append(arguments)
        stdout.split(whereSeparator: \.isNewline).forEach { onLine(String($0)) }
        return BrewResult(stdout: stdout, stderr: stderr, exitCode: exitCode)
    }
}

final class BrewServiceTests: XCTestCase {
    private let env = BrewEnvironment(binaryPath: "/opt/homebrew/bin/brew", prefix: "/opt/homebrew")

    private func service(_ runner: FakeBrewRunner) -> BrewService {
        BrewService(runner: runner, environment: env)
    }

    // MARK: Environment

    func testLocateReturnsNilWhenNoBrewExists() {
        XCTAssertNil(BrewEnvironment.locate(candidates: ["/nonexistent/bin/brew"]))
    }

    func testPrefixIsDerivedFromBinaryPath() {
        let e = BrewEnvironment(binaryPath: "/opt/homebrew/bin/brew", prefix: "/opt/homebrew")
        XCTAssertEqual(e.cellarURL.path, "/opt/homebrew/Cellar")
        XCTAssertEqual(e.caskroomURL.path, "/opt/homebrew/Caskroom")
    }

    // MARK: Command injection

    /// A package name is DATA. If it ever reached a shell it could execute — so it must stay a
    /// single argument element, metacharacters and all.
    func testHostilePackageNameStaysOneArgument() {
        let evil = BrewPackage(name: "evil; rm -rf ~/Documents", kind: .formula)
        let args = BrewService.uninstallArguments(evil)
        XCTAssertEqual(args.last, "evil; rm -rf ~/Documents")
        XCTAssertEqual(args.filter { $0.contains("rm -rf") }.count, 1)
        XCTAssertFalse(args.contains { $0 == "&&" || $0 == ";" })
    }

    func testBacktickAndQuoteNamesAreNotSplit() {
        let evil = BrewPackage(name: "a`whoami`\"b\"", kind: .formula)
        XCTAssertEqual(BrewService.installArguments(evil).last, "a`whoami`\"b\"")
    }

    func testCaskCommandsCarryCaskFlag() {
        let cask = BrewPackage(name: "codex", kind: .cask)
        XCTAssertTrue(BrewService.installArguments(cask).contains("--cask"))
        XCTAssertTrue(BrewService.uninstallArguments(cask).contains("--cask"))
    }

    func testDryRunFlagPresentOnlyWhenRequested() {
        let pkg = BrewPackage(name: "wget", kind: .formula)
        XCTAssertTrue(BrewService.uninstallArguments(pkg, dryRun: true).contains("--dry-run"))
        XCTAssertFalse(BrewService.uninstallArguments(pkg, dryRun: false).contains("--dry-run"))
    }

    // MARK: Parsing installed state

    func testParsesFormulaeAndCasksWithOutdatedFlag() {
        let json = """
        {"formulae":[
          {"name":"aom","desc":"Codec library","homepage":"https://aomedia.org",
           "installed":[{"version":"3.14.1"}],"versions":{"stable":"3.14.1"},"outdated":false},
          {"name":"bash","desc":"Bourne-Again SHell",
           "installed":[{"version":"5.2.21"}],"versions":{"stable":"5.3.0"},"outdated":true}],
         "casks":[
          {"token":"codex","name":["Codex"],"desc":"Agent","version":"0.126.0","installed":"0.125.0","outdated":true}]}
        """
        let pkgs = BrewService.parseInstalled(json: json)
        XCTAssertEqual(pkgs.count, 3)
        let bash = pkgs.first { $0.name == "bash" }
        XCTAssertEqual(bash?.installedVersion, "5.2.21")
        XCTAssertEqual(bash?.latestVersion, "5.3.0")
        XCTAssertTrue(bash?.isOutdated ?? false)
        let codex = pkgs.first { $0.name == "codex" }
        XCTAssertEqual(codex?.kind, .cask)
        XCTAssertEqual(codex?.installedVersion, "0.125.0")   // casks report a plain string
        XCTAssertTrue(codex?.isInstalled ?? false)
    }

    func testParsingMalformedJsonReturnsEmptyRatherThanCrashing() {
        XCTAssertTrue(BrewService.parseInstalled(json: "not json").isEmpty)
        XCTAssertTrue(BrewService.parseInstalled(json: "").isEmpty)
    }

    // MARK: Dependency guard

    func testUninstallBlockedWhenSomethingDependsOnIt() throws {
        let runner = FakeBrewRunner()
        runner.stdout = "ffmpeg\nimagemagick\n"
        let svc = service(runner)
        XCTAssertEqual(try svc.dependents(of: "libpng"), ["ffmpeg", "imagemagick"])
        XCTAssertFalse(try svc.canUninstall("libpng"))
    }

    func testLeafPackageCanBeUninstalled() throws {
        let runner = FakeBrewRunner()
        runner.stdout = "\n"
        XCTAssertTrue(try service(runner).canUninstall("wget"))
    }

    // MARK: Previews

    func testCleanupPreviewParsesReclaimableBytes() {
        let text = """
        Would remove: /opt/homebrew/Cellar/foo/1.0 (10 files, 2.1MB)
        ==> This operation would free approximately 462.9MB of disk space.
        """
        let preview = BrewService.parsePreview(text)
        XCTAssertEqual(preview.reclaimableBytes, Int64(462.9 * 1024 * 1024))
        XCTAssertEqual(preview.lines.count, 2)
    }

    func testPreviewSizeUnits() {
        XCTAssertEqual(BrewService.parseSize(in: "would free approximately 1.5GB of disk"),
                       Int64(1.5 * 1024 * 1024 * 1024))
        XCTAssertEqual(BrewService.parseSize(in: "would free approximately 800KB"), 800 * 1024)
        XCTAssertEqual(BrewService.parseSize(in: "nothing to say here"), 0)
    }

    func testPreviewUsesDryRunSoNothingIsRemoved() throws {
        let runner = FakeBrewRunner()
        _ = try service(runner).previewCleanup()
        XCTAssertEqual(runner.receivedArgs.first, ["cleanup", "-n"])
        // The real (destructive) form must NOT have been issued.
        XCTAssertFalse(runner.receivedArgs.contains(["cleanup"]))
    }
}

/// Search must cover BOTH installed and not-installed packages. The first implementation filtered
/// installed ones OUT, so searching for something you already had returned nothing.
@MainActor
final class BrewSearchTests: XCTestCase {
    private func viewModelWithInstalled(_ names: [String]) -> BrewViewModel {
        let vm = BrewViewModel()
        vm.setPackagesForTesting(names.map { n in
            var p = BrewPackage(name: n, kind: .formula)
            p.installedVersion = "1.0"
            return p
        })
        return vm
    }

    func testSearchFindsInstalledPackage() {
        let vm = viewModelWithInstalled(["wget", "ffmpeg", "libpng"])
        vm.searchText = "wget"
        vm.runSearch()
        XCTAssertEqual(vm.installedMatches.map(\.name), ["wget"])
    }

    func testSearchMatchesDescriptionAndRanksExactNameFirst() {
        let vm = BrewViewModel()
        var a = BrewPackage(name: "wgetpaste", kind: .formula); a.installedVersion = "1.0"
        var b = BrewPackage(name: "wget", kind: .formula); b.installedVersion = "1.0"
        vm.setPackagesForTesting([a, b])
        vm.searchText = "wget"
        vm.runSearch()
        XCTAssertEqual(vm.installedMatches.first?.name, "wget", "exact name must rank first")
        XCTAssertEqual(vm.installedMatches.count, 2)
    }

    func testShortQueryClearsResultsInsteadOfMatchingEverything() {
        let vm = viewModelWithInstalled(["wget"])
        vm.searchText = "w"
        vm.runSearch()
        XCTAssertTrue(vm.installedMatches.isEmpty)
        XCTAssertFalse(vm.hasSearchQuery)
    }
}

/// Trace removal: zap for casks, autoremove for orphaned formula dependencies.
final class BrewTraceRemovalTests: XCTestCase {
    private let env = BrewEnvironment(binaryPath: "/opt/homebrew/bin/brew", prefix: "/opt/homebrew")

    func testZapFlagOnlyForCasksAndOnlyWhenRequested() {
        let cask = BrewPackage(name: "codex", kind: .cask)
        XCTAssertTrue(BrewService.uninstallArguments(cask, zap: true).contains("--zap"))
        XCTAssertFalse(BrewService.uninstallArguments(cask, zap: false).contains("--zap"))
        // Formulae have no zap concept — the flag must never be sent for them.
        let formula = BrewPackage(name: "wget", kind: .formula)
        XCTAssertFalse(BrewService.uninstallArguments(formula, zap: true).contains("--zap"))
    }

    func testAutoremovePreviewNeverRemoves() throws {
        let runner = FakeBrewRunner()
        runner.stdout = "==> Would autoremove 2 unneeded formulae:\nlibidn2\nlibunistring\n"
        let svc = BrewService(runner: runner, environment: env)
        XCTAssertEqual(try svc.orphanedDependencies(), ["libidn2", "libunistring"])
        XCTAssertEqual(runner.receivedArgs.first, ["autoremove", "-n"])
        XCTAssertFalse(runner.receivedArgs.contains(["autoremove"]))
    }

    func testAutoremoveParsesSpaceSeparatedList() {
        let out = "==> Would autoremove 3 unneeded formulae:\nlibidn2 libunistring gettext\n"
        XCTAssertEqual(BrewService.parseAutoremove(out), ["libidn2", "libunistring", "gettext"])
    }

    func testNoOrphansParsesEmpty() {
        XCTAssertTrue(BrewService.parseAutoremove("").isEmpty)
    }
}
