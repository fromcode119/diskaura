# Homebrew Module Implementation Plan

> **For agentic workers:** Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Manage Homebrew from inside DiskAura — list installed packages with sizes, upgrade
outdated ones, search and install new ones, and reclaim space — with mandatory dry-run previews.

**Architecture:** Hybrid (approach C from the spec). `brew --json=v2` is the offline source of
truth for installed/outdated state; a disk-cached web catalog powers search; all mutations run
through the real `brew` CLI via `Process` with argument arrays.

**Tech Stack:** Swift 5, SwiftUI, XCTest, XcodeGen. No third-party dependencies.

## Global Constraints

- Commands are built as **argument arrays, never interpolated shell strings**. A package name must
  never be able to inject a command.
- **No test may run a real mutating brew command.** `BrewService` takes an injected runner; tests
  use a fake. Nothing may be installed, uninstalled, or cleaned by the suite.
- Destructive actions **preview first** (`--dry-run` / `-n`) and require confirmation.
- Results are **measured, not assumed** — report what brew actually did.
- Long operations **stream visible progress**; no silent multi-minute waits.
- Admin escalation is **scoped to cask installs only**; anything else shows a copyable command.
- "Homebrew not installed" is a first-class UI state, never an error or empty list.
- Swift files stay focused; prefer splitting over a file that does too much.

---

## File Structure

| File | Responsibility |
|---|---|
| `DiskAura/Models/BrewPackage.swift` | One installed/available package: name, version, kind, size, outdated |
| `DiskAura/Models/BrewOperation.swift` | A queued operation + its state and streamed log |
| `DiskAura/Services/BrewEnvironment.swift` | Locate brew, report prefix/version, detect absence |
| `DiskAura/Services/BrewCommandRunner.swift` | Process execution protocol + real implementation (injectable) |
| `DiskAura/Services/BrewService.swift` | Build argument arrays, run commands, parse JSON |
| `DiskAura/Services/BrewCatalog.swift` | Cached searchable catalog + offline fallback |
| `DiskAura/ViewModels/BrewViewModel.swift` | UI state: lists, filters, operation queue |
| `DiskAura/Views/BrewView.swift` | Tab composition root |
| `DiskAura/Views/Brew/BrewPackageRow.swift` | One package row + its actions |
| `DiskAura/Views/Brew/BrewOperationBar.swift` | Streaming progress + log |
| `DiskAura/Views/Brew/BrewNotInstalledCard.swift` | The not-installed state |
| `DiskAuraTests/BrewServiceTests.swift` | Command construction, parsing, dependency guard |
| `DiskAuraTests/BrewCatalogTests.swift` | Search ranking + cache staleness |

---

### Task 1: Environment detection

**Files:** Create `Services/BrewEnvironment.swift`, `DiskAuraTests/BrewServiceTests.swift`

**Produces:** `BrewEnvironment.locate() -> BrewEnvironment?` with `.binaryPath: String`,
`.prefix: String`; `BrewEnvironment.isInstalled: Bool`.

- [ ] Write failing test: `testLocateReturnsNilWhenNoBrewBinaryExists` using injected candidate paths
- [ ] Run it, confirm it fails to compile/pass
- [ ] Implement `locate(candidates:)` checking `/opt/homebrew/bin/brew` then `/usr/local/bin/brew`
- [ ] Run tests, confirm pass
- [ ] Commit

### Task 2: Injectable command runner

**Files:** Create `Services/BrewCommandRunner.swift`

**Consumes:** `BrewEnvironment.binaryPath`
**Produces:** `protocol BrewCommandRunning { func run(_ args: [String]) throws -> BrewResult }`
where `BrewResult` has `.stdout: String`, `.stderr: String`, `.exitCode: Int32`; plus
`FakeBrewRunner` (test target) recording `receivedArgs: [[String]]`.

- [ ] Write failing test: `testRunnerReceivesArgumentsAsArrayNotShellString`
- [ ] Run it, confirm failure
- [ ] Implement protocol + `ProcessBrewRunner` using `Process.arguments = args` (no shell)
- [ ] Run tests, confirm pass
- [ ] Commit

### Task 3: Command construction is injection-proof

**Files:** Modify `Services/BrewService.swift`

**Produces:** `BrewService(runner:environment:)`, `func uninstallArguments(for:) -> [String]`

- [ ] Write failing test: `testPackageNameWithShellMetacharactersIsNotInterpreted` using name
      `evil; rm -rf /` and asserting it appears as ONE argument element
- [ ] Run it, confirm failure
- [ ] Implement argument builders returning `[String]`
- [ ] Run tests, confirm pass
- [ ] Commit

### Task 4: Parse installed + outdated state

**Files:** Modify `Services/BrewService.swift`, create `Models/BrewPackage.swift`

**Consumes:** runner from Task 2
**Produces:** `func installedPackages() throws -> [BrewPackage]`; `BrewPackage` with
`name`, `version`, `kind: .formula/.cask`, `isOutdated: Bool`, `sizeBytes: Int64`

- [ ] Write failing test: `testParsesInstalledFormulaeAndOutdatedFlag` from a fixture JSON string
- [ ] Run it, confirm failure
- [ ] Implement `brew info --json=v2 --installed` parsing via `JSONSerialization`
- [ ] Run tests, confirm pass
- [ ] Commit

### Task 5: Dependency guard

**Files:** Modify `Services/BrewService.swift`

**Produces:** `func dependents(of name: String) throws -> [String]`,
`func canUninstall(_ name: String) throws -> Bool`

- [ ] Write failing test: `testUninstallBlockedWhenAnotherPackageDependsOnIt` (fake returns `["ffmpeg"]`)
- [ ] Write failing test: `testLeafPackageCanBeUninstalled` (fake returns empty)
- [ ] Run them, confirm failure
- [ ] Implement using `brew uses --installed <name>`
- [ ] Run tests, confirm pass
- [ ] Commit

### Task 6: Dry-run previews

**Files:** Modify `Services/BrewService.swift`

**Produces:** `func previewUninstall(_:) throws -> BrewPreview`, `func previewCleanup() throws -> BrewPreview`
with `BrewPreview.reclaimableBytes: Int64`, `.lines: [String]`

- [ ] Write failing test: `testCleanupPreviewParsesReclaimableBytes` from fixture
      `"This operation would free approximately 462.9MB of disk space."`
- [ ] Run it, confirm failure
- [ ] Implement `cleanup -n` / `uninstall --dry-run` + byte parsing (MB/GB/KB)
- [ ] Run tests, confirm pass
- [ ] Commit

### Task 7: Catalog search

**Files:** Create `Services/BrewCatalog.swift`, `DiskAuraTests/BrewCatalogTests.swift`

**Produces:** `func search(_ query: String) -> [BrewPackage]`, `var isStale: Bool`

- [ ] Write failing test: `testSearchRanksExactNameMatchFirst`
- [ ] Run it, confirm failure
- [ ] Implement in-memory search over cached catalog with exact > prefix > description ranking
- [ ] Run tests, confirm pass
- [ ] Commit

### Task 8: View model + operation queue

**Files:** Create `ViewModels/BrewViewModel.swift`, `Models/BrewOperation.swift`

**Produces:** `@Published packages`, `outdated`, `operation: BrewOperation?`, plus
`install/uninstall/upgrade/cleanup` methods that stream output

- [ ] Implement view model driving the service off the main actor
- [ ] Run full suite, confirm pass
- [ ] Commit

### Task 9: UI + sidebar wiring

**Files:** Create `Views/BrewView.swift` and `Views/Brew/*`; modify `Views/ContentView.swift`,
`Views/Theme.swift`

- [ ] Add `SidebarTab.homebrew` + module colour + view wiring
- [ ] Build, run full suite
- [ ] Commit

### Task 10: Verify live

- [ ] Deploy via `./dev-run.sh`
- [ ] Confirm installed list, outdated count, cleanup preview, and search against the real machine
- [ ] Confirm no test mutated the real Homebrew installation
- [ ] Commit any fixes
