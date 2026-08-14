import Foundation
import Combine
import AppKit

@MainActor
final class ProcessViewModel: ObservableObject {
    /// Default view is curated — top offenders only, like iStat Menus/Stats show, not a
    /// 1000-row table. `showAllProcesses` opts into the full sortable list for power users.
    /// Split into Apps vs System (by owning UID) — CleanMyMac's actual categorization,
    /// not just an arbitrary "top 6" list with no structure.
    @Published var topApps: [ProcessSnapshot] = []
    @Published var topBackground: [ProcessSnapshot] = []
    @Published var topSystem: [ProcessSnapshot] = []
    @Published var appCount: Int = 0
    @Published var backgroundCount: Int = 0
    @Published var systemCount: Int = 0
    @Published var appMemoryBytes: UInt64 = 0
    @Published var backgroundMemoryBytes: UInt64 = 0
    @Published var systemMemoryBytes: UInt64 = 0

    @Published var allProcesses: [ProcessSnapshot] = []
    @Published var totalCPUPercent: Double = 0
    /// Real system memory used (host_statistics64), NOT a sum of per-process resident
    /// sizes — that double-counts shared frameworks and reported 55GB "used" on a 42GB
    /// machine when confirmed live.
    @Published var totalMemoryBytes: UInt64 = 0
    @Published var totalMemoryCapacity: UInt64 = 0
    @Published var memoryActiveBytes: UInt64 = 0
    @Published var memoryWiredBytes: UInt64 = 0
    @Published var memoryCompressedBytes: UInt64 = 0
    @Published var memoryFreeBytes: UInt64 = 0
    /// Naive sum of every process's resident memory — shown *alongside* the accurate
    /// system value (not instead of it) so it's clear why they don't match: shared
    /// frameworks get counted once per process here, but only once system-wide above.
    @Published var processMemorySum: UInt64 = 0
    @Published var processCount: Int = 0

    @Published var showAllProcesses = false
    @Published var sortOrder: [KeyPathComparator<ProcessSnapshot>] = [.init(\.cpuPercent, order: .reverse)]
    @Published var filter: ProcessFilter = .all
    @Published var searchText = ""
    @Published var isRunning = false
    @Published var quitError: String?
    /// Set when a polite quit was ignored — drives the alert's "Force Quit" escalation.
    @Published var forceQuitTarget: (pid: Int32, name: String)?
    /// Live status while a quit is in flight ("Quitting Docker… 6s"). A quit can legitimately take
    /// 20s, and with no indication that reads as a dead button.
    @Published private(set) var busyMessage: String?
    /// PIDs currently being quit — the row shows a spinner instead of an inert Quit button.
    @Published private(set) var quittingPIDs: Set<Int32> = []

    /// When paused, the live sampler keeps running for the sparkline but the process LISTS
    /// stop updating — the user asked to freeze the "constantly changing" view so they can
    /// actually read it. Resume re-syncs to live.
    @Published var isPaused = false
    /// A frozen snapshot the user explicitly captured — its total CPU/memory is compared
    /// against the live values so you can see how things changed "over time".
    @Published var snapshot: CapturedSnapshot?
    /// Recent total-CPU samples for the header sparkline (newest last, capped).
    @Published var cpuHistory: [Double] = []
    @Published var lastSampledAt: Date?

    struct CapturedSnapshot {
        let takenAt: Date
        let totalCPUPercent: Double
        let usedMemoryBytes: UInt64
        let processCount: Int
        let topByCPU: [ProcessSnapshot]
    }

    private let monitor = ProcessMonitor()
    private var timer: Timer?
    private var isSampling = false
    private static let historyLimit = 40

    private static let topCount = 8

    var filteredAllProcesses: [ProcessSnapshot] {
        var list = allProcesses
        switch filter {
        case .all: break
        case .apps: list = list.filter(\.isApp)
        case .system: list = list.filter(\.isSystemProcess)
        }
        if !searchText.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        return list.sorted(using: sortOrder)
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    /// Enabling "show all" should populate immediately rather than waiting up to 2s for
    /// the next tick — the table would otherwise appear empty for a beat after toggling.
    func setShowAllProcesses(_ show: Bool) {
        showAllProcesses = show
        if show { tick() }
    }

    func togglePause() {
        isPaused.toggle()
        if !isPaused { tick() }
    }

    /// Freeze the current live figures as a reference point to compare against later.
    func captureSnapshot() {
        snapshot = CapturedSnapshot(
            takenAt: Date(),
            totalCPUPercent: totalCPUPercent,
            usedMemoryBytes: totalMemoryBytes,
            processCount: processCount,
            topByCPU: Array((topApps + topBackground).sorted { $0.cpuPercent > $1.cpuPercent }.prefix(5))
        )
    }

    func clearSnapshot() { snapshot = nil }

    /// Quits an app cleanly via NSRunningApplication when possible (same as clicking
    /// Quit in the Dock); falls back to SIGTERM for non-app processes. System processes
    /// (root-owned) are never quittable from here — matches CleanMyMac, which doesn't
    /// let you kill core system daemons either, only hung user apps.
    func quit(_ process: ProcessSnapshot) {
        guard !process.isSystemProcess else { return }
        // Ask politely first: the owning .app bundle if there is one (Docker.app owns
        // com.docker.backend), otherwise the process itself, otherwise SIGTERM.
        let target = owningApp(of: process) ?? NSRunningApplication(processIdentifier: process.id)
        let targetPID = target?.processIdentifier ?? process.id
        let label = target?.localizedName ?? process.name

        // Feedback FIRST — before any waiting — so the click always visibly does something.
        busyMessage = "Quitting \(label)…"
        quittingPIDs.insert(process.id)

        if let target, target.terminate() {
            // A polite quit is a REQUEST — an app can defer or ignore it (Docker Desktop takes
            // 10-20s to stop its VM, and may not respond at all). So watch the outcome instead
            // of assuming, and offer to force it if the app never goes away.
            watchQuit(pid: targetPID, name: label, startedAt: startTime(of: targetPID), politeQuit: true)
        } else if kill(targetPID, SIGTERM) == 0 {
            watchQuit(pid: targetPID, name: label, startedAt: startTime(of: targetPID), politeQuit: false)
        } else {
            finishQuit(pid: process.id)
            busyMessage = nil
            quitError = quitFailureReason(for: process, errno: errno)
        }
        tick()
    }

    /// Force-quit (SIGKILL) — what the alert's "Force Quit" button runs after a polite quit was
    /// ignored. Same escalation Activity Monitor offers; unsaved work in that app is lost.
    /// Takes the target as a PARAMETER, not from `forceQuitTarget`: dismissing the alert clears
    /// that property before the button's action runs, so reading it here made Force Quit a silent
    /// no-op — the "I clicked force and nothing happened" bug.
    func forceQuit(pid: Int32, name: String) {
        forceQuitTarget = nil
        busyMessage = "Force quitting \(name)…"
        // forceTerminate() is still a cooperative AppKit path; SIGKILL is the kernel-level stop
        // that an app cannot ignore. Try the former, then escalate for real.
        NSRunningApplication(processIdentifier: pid)?.forceTerminate()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self else { return }
            if kill(pid, 0) == 0 { kill(pid, SIGKILL) }              // still alive → kernel kill
            try? await Task.sleep(for: .seconds(1))
            self.busyMessage = nil
            if kill(pid, 0) == 0 {
                self.quitError = "\(name) could not be stopped even with Force Quit. "
                    + "It's likely restarted by a background service — stop it from the app's own "
                    + "menu-bar icon or Settings."
            }
            self.tick()
        }
    }

    /// Polls a quit target instead of guessing. Distinguishes the three real outcomes: it quit,
    /// it ignored us (same pid, same start time — offer Force Quit), or it genuinely respawned
    /// (a NEW pid for the same name). The old code claimed "restarted automatically" for all of
    /// them, which was wrong: Docker's pid had been alive for 1d21h and never died at all.
    private func watchQuit(pid: Int32, name: String, startedAt: UInt64, politeQuit: Bool) {
        Task { [weak self] in
            // Apps that stop VMs/containers legitimately need time; poll rather than one snap check,
            // counting up so the user can see it working instead of staring at a frozen button.
            for elapsed in 1...20 {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                if kill(pid, 0) != 0 || startTime(of: pid) != startedAt {
                    self.finishQuit(pid: pid)
                    self.busyMessage = "\(name) quit."
                    Task { try? await Task.sleep(for: .seconds(2)); self.busyMessage = nil }
                    self.tick()
                    return
                }
                self.busyMessage = "Quitting \(name)… \(elapsed)s"
            }
            guard let self else { return }
            self.finishQuit(pid: pid)
            self.busyMessage = nil
            self.forceQuitTarget = (pid: pid, name: name)
            self.quitError = politeQuit
                ? "\(name) didn't respond to the quit request after 20 seconds. "
                + "You can force it to stop, but any unsaved work in it will be lost."
                : "\(name) ignored the stop signal after 20 seconds. It can be forced to stop."
        }
    }

    private func finishQuit(pid: Int32) { quittingPIDs.remove(pid) }

    /// Process start time, used to tell "never died" apart from "died and respawned" — a reused
    /// pid would otherwise look like the original process still running.
    private func startTime(of pid: Int32) -> UInt64 {
        var info = proc_bsdinfo()
        let size = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
        guard size == Int32(MemoryLayout<proc_bsdinfo>.size) else { return 0 }
        return UInt64(info.pbi_start_tvsec)
    }

    /// The running `.app` that owns this process, found by walking the executable path up to the
    /// enclosing `.app` bundle. Returns nil for a standalone binary with no owning bundle.
    private func owningApp(of process: ProcessSnapshot) -> NSRunningApplication? {
        guard !process.executablePath.isEmpty else { return nil }
        var url = URL(fileURLWithPath: process.executablePath)
        while url.pathComponents.count > 1 {
            if url.pathExtension == "app" {
                return NSWorkspace.shared.runningApplications.first { $0.bundleURL == url }
            }
            url = url.deletingLastPathComponent()
        }
        return nil
    }

    /// Explains WHY a quit failed instead of the useless "Couldn't quit X" — the reason decides
    /// what the user can do about it (relaunch-on-exit vs needs-admin vs already-gone).
    private func quitFailureReason(for process: ProcessSnapshot, errno code: Int32) -> String {
        switch code {
        case EPERM:
            return "\(process.name) is protected by macOS and can't be quit from here. "
                 + "Quit it from its own app or menu-bar icon instead."
        case ESRCH:
            return "\(process.name) already exited."
        default:
            return "Couldn't quit \(process.name) (error \(code))."
        }
    }

    /// Sampling runs off the main actor — this is what fixed the slow tab-switch: the
    /// previous version called 1000+ synchronous syscalls directly on the main thread.
    private func tick() {
        guard !isSampling else { return }
        isSampling = true
        Task {
            let sampled = await monitor.sample()
            let cpuSorted = sampled.sorted { $0.cpuPercent > $1.cpuPercent }
            let apps = cpuSorted.filter(\.isApp)
            let system = cpuSorted.filter(\.isSystemProcess)
            // Everything owned by you that isn't a GUI app — helper/XPC processes,
            // background CLI tools, etc. Without this bucket these just vanished from
            // both categories (confirmed live: ~957 of 1081 processes were uncategorized).
            let background = cpuSorted.filter { !$0.isApp && !$0.isSystemProcess }
            let total = sampled.reduce(0) { $0 + $1.cpuPercent }
            let processSum = sampled.reduce(UInt64(0)) { $0 + $1.memoryBytes }
            let count = sampled.count
            let systemMemory = SystemMemoryService.current()

            // History + the always-live memory donut keep updating even when paused, so the
            // sparkline and RAM stay real; only the process LISTS freeze on pause.
            self.cpuHistory.append(total)
            if self.cpuHistory.count > Self.historyLimit {
                self.cpuHistory.removeFirst(self.cpuHistory.count - Self.historyLimit)
            }
            self.lastSampledAt = Date()
            self.totalMemoryBytes = systemMemory?.usedBytes ?? 0
            self.totalMemoryCapacity = systemMemory?.totalBytes ?? 0
            self.memoryActiveBytes = systemMemory?.activeBytes ?? 0
            self.memoryWiredBytes = systemMemory?.wiredBytes ?? 0
            self.memoryCompressedBytes = systemMemory?.compressedBytes ?? 0
            self.memoryFreeBytes = systemMemory?.freeBytes ?? 0

            if !self.isPaused {
                self.topApps = Array(apps.prefix(Self.topCount))
                self.topBackground = Array(background.prefix(Self.topCount))
                self.topSystem = Array(system.prefix(Self.topCount))
                self.appCount = apps.count
                self.backgroundCount = background.count
                self.systemCount = system.count
                self.appMemoryBytes = apps.reduce(UInt64(0)) { $0 + $1.memoryBytes }
                self.backgroundMemoryBytes = background.reduce(UInt64(0)) { $0 + $1.memoryBytes }
                self.systemMemoryBytes = system.reduce(UInt64(0)) { $0 + $1.memoryBytes }
                self.totalCPUPercent = total
                self.processMemorySum = processSum
                self.processCount = count
                if self.showAllProcesses {
                    self.allProcesses = sampled
                }
            }
            self.isSampling = false
        }
    }
}
