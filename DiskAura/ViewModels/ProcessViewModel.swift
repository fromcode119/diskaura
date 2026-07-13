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
        if let app = NSRunningApplication(processIdentifier: process.id) {
            app.terminate()
        } else {
            if kill(process.id, SIGTERM) != 0 {
                quitError = "Couldn't quit \(process.name)"
            }
        }
        tick()
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
