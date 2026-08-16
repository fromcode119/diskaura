# Homebrew Module — Design

**Date:** 2026-08-16
**Status:** Approved (design), pending implementation plan
**Branch:** `feature/homebrew`

## Purpose

Manage Homebrew packages from inside DiskAura: see what's installed and what it costs in disk
space, upgrade what's outdated, search and install new packages, and reclaim space from brew's
caches and old versions.

This is a **full package-manager GUI**, not only a cleanup surface. That was an explicit choice:
cleanup alone was offered and rejected in favour of browse/search/install/upgrade.

Measured baseline on the development machine (2026-08-16, Homebrew 6.0.17, `/opt/homebrew`):

| Metric | Value |
|---|---|
| Installed formulae | 118 |
| Installed casks | 5 |
| Leaves (nothing depends on them) | 19 |
| Outdated formulae | 44 |
| Cellar + Caskroom on disk | ~2.6 GB |
| Reclaimable by `brew cleanup` | 462.9 MB |

## Approach: hybrid CLI + cached catalog

Three approaches were considered:

- **A — shell out to `brew` for everything.** Always correct and version-matched, but `brew search`
  is too slow to drive a search field, and human-readable output is fragile to parse.
- **B — use the formulae.brew.sh JSON API for everything.** Instant catalog search with
  descriptions, but network-dependent and free to drift from what is actually installed locally.
- **C — hybrid (chosen).** `brew --json=v2` is the source of truth for installed/outdated state:
  offline, exact, version-matched. A disk-cached copy of the web catalog powers search and browse.
  All mutations go through the real `brew` CLI.

C is the only option where search feels instant *and* installed state is never a guess.

## Architecture

### Data layer

**`BrewEnvironment`** — locates the `brew` binary (`/opt/homebrew/bin/brew` on Apple Silicon,
`/usr/local/bin/brew` on Intel), reports prefix and version. Treats **"Homebrew not installed"** as
a first-class state with its own UI, never an error or an empty list.

**`BrewService`** — runs brew through `Process`.

- Commands are built as **argument arrays, never an interpolated shell string.** A package name
  therefore cannot inject a command. This is a hard requirement, not a preference.
- Streams stdout/stderr line by line so long operations show live progress.
- Reads structured state via `brew info --json=v2 --installed`.

**`BrewCatalog`** — the searchable catalog (~7k formulae, ~5k casks with descriptions), fetched
from formulae.brew.sh, cached to disk with a timestamp, refreshed in the background. Falls back to
`brew search` when offline or when the cache is missing. Search never blocks on the network.

### Operations

`install`, `uninstall`, `upgrade`, and `cleanup` are each a queued **`BrewOperation`** carrying a
live log and a terminal state.

Installs take minutes. Applying the lesson from the Quit-button bug: an operation with no visible
progress reads as a broken button. Every operation therefore shows streaming output and a running
elapsed time, and its result is **measured, not assumed** — the same rule that applies to Empty
Trash (report the real disk delta, never the intended one).

### Safety model

Destructive actions always **preview before they run**:

- `brew uninstall --dry-run` and `brew cleanup -n` produce the exact file list and byte count.
- The confirmation shows what will be removed and how much it frees.
- **Dependency guard:** `brew uses --installed <pkg>` runs first. If any installed package depends
  on the target, removal is blocked and names the dependents. An explicit override is available,
  but it is never the default.
- Removed package names are recorded so "reinstall these" can be offered. This is labelled
  honestly as a **re-download, not an undo** — it needs the network and may fetch a newer version.

There is no Trash step: brew deletes immediately. The preview *is* the safety mechanism, which is
why it is mandatory rather than a setting.

### Admin rights

Formulae install inside the brew prefix and **never run as root.** Some casks ship `.pkg`
installers that require admin rights.

For those, macOS presents **its own secure authorization dialog**. The password goes to Apple, not
to DiskAura — the app never sees, stores, or transmits it. Escalation is **scoped to cask installs
only**, because Homebrew explicitly discourages running `brew` as root. Any other operation that
turns out to need admin rights is **not** escalated: DiskAura shows the exact command with a Copy
button so the user can run it themselves.

## v1 scope

In scope:

1. Installed list — formulae and casks, with per-package size, sortable, searchable.
2. Outdated + upgrade — individually or all.
3. Catalog search + install.
4. Cleanup — stale downloads and superseded versions, with a dry-run preview.
5. Not-installed state — detect and explain, with a link to brew.sh. DiskAura does not install
   Homebrew itself in v1.

Explicitly deferred: taps, `brew services`, pinning, install-time options, and version pinning.

## Placement

A new **Homebrew** entry in the sidebar's system section, following the existing tab pattern
(`SidebarTab` case, module colour in `Theme`, view wired in `ContentView`). It reuses the app's
existing visual language — stat hero, glass cards, pill buttons — rather than inventing new chrome.

## Error handling

Every failure names a cause and an action:

- brew missing → explain and link, do not show an empty list.
- network unavailable during search → serve the cached catalog and say it may be stale.
- operation fails → surface brew's own stderr verbatim; it is usually the clearest explanation.
- dependency conflict → name the dependents.
- admin required and declined → show the copyable command.

## Testing

- **Parsing** — `brew info --json=v2` fixtures drive installed/outdated parsing, with no live brew.
- **Dependency guard** — fixture graphs assert that a depended-on package is refused and a leaf is
  allowed.
- **Process layer** — a fake runner injected into `BrewService` so tests never mutate a real
  Homebrew installation. No test may install or uninstall anything.
- **Command construction** — assert argument arrays are passed as arrays, including package names
  containing spaces, quotes, and shell metacharacters.

## Known constraints

- Homebrew must already be installed; v1 does not bootstrap it.
- Reinstall-after-uninstall is a re-download, not a restore.
- Catalog search quality depends on cache freshness.
- Package sizes come from the Cellar/Caskroom on disk and, like every other size in the app, are
  currently summed per path without inode dedup — hard links and APFS clones count once per link.
  Tracked separately from this work.
