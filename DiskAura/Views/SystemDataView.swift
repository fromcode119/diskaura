import SwiftUI

/// The "System Data" explainer — turns Finder's mysterious multi-GB "System Data" bar into a named
/// breakdown: what's safely reclaimable (with a jump straight to Cleanup) and what's real system
/// working storage you shouldn't touch. Answers the #1 unmet Mac-storage question: "what IS that?"
struct SystemDataView: View {
    @ObservedObject var router: AppRouter
    @State private var report: SystemDataService.Report?
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                header
                if isLoading {
                    loading
                } else if let report {
                    diskCard(report)
                    if !report.reclaimable.isEmpty { reclaimableCard(report) }
                    if !report.systemManaged.isEmpty { systemManagedCard(report) }
                } else {
                    Text("Analyzing your disk…").foregroundColor(.secondary).padding()
                }
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.appGradient)
        .onAppear { if report == nil { analyze() } }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("System Data").font(.system(size: 22, weight: .bold))
                Text("What that mysterious chunk of your disk actually is")
                    .font(.system(size: 12)).foregroundColor(.secondary)
            }
            Spacer()
            Button { analyze() } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                .buttonStyle(.bordered)
        }
    }

    private var loading: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Scanning caches, snapshots, system storage…").font(.system(size: 12)).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(24).glassCard()
    }

    // MARK: - Disk overview

    private func diskCard(_ r: SystemDataService.Report) -> some View {
        HStack(spacing: 24) {
            CategoryDonut(
                segments: [
                    DonutSegment(id: "used", label: "Used", sizeBytes: r.volumeUsedBytes, color: Theme.moduleColor(.scan)),
                    DonutSegment(id: "free", label: "Free", sizeBytes: r.volumeFreeBytes, color: Color.white.opacity(0.12)),
                ],
                centerValue: r.volumeFreeBytes.formattedBytes,
                centerLabel: "free"
            )
            VStack(alignment: .leading, spacing: 10) {
                statLine("Used", r.volumeUsedBytes, Theme.moduleColor(.scan))
                statLine("Free", r.volumeFreeBytes, .secondary)
                Divider().frame(width: 220)
                statLine("Reclaimable now", r.reclaimableTotal, Theme.moduleColor(.cleanup))
                if r.snapshotCount > 0 {
                    Text("\(r.snapshotCount) local Time Machine snapshot\(r.snapshotCount == 1 ? "" : "s") included")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
        .padding(Theme.Spacing.lg).glassCard()
    }

    private func statLine(_ label: String, _ bytes: Int64, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.system(size: 12)).foregroundColor(.secondary)
            Spacer(minLength: 24)
            Text(bytes.formattedBytes).font(.system(size: 13, weight: .semibold, design: .monospaced))
        }
    }

    // MARK: - Reclaimable

    private func reclaimableCard(_ r: SystemDataService.Report) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Safe to reclaim").font(.system(size: 14, weight: .semibold))
                    Text("\(r.reclaimableTotal.formattedBytes) of disposable caches, logs & junk")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
                Spacer()
                Button { router.selectedTab = .cleanup } label: {
                    Label("Reclaim in Cleanup", systemImage: "sparkles").font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.pill(Theme.moduleColor(.cleanup)))
            }
            ForEach(r.reclaimable) { bucket in bucketRow(bucket, tint: Theme.moduleColor(.cleanup)) }
        }
        .padding(Theme.Spacing.lg).glassCard()
    }

    private func systemManagedCard(_ r: SystemDataService.Report) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("System-managed — leave this alone").font(.system(size: 14, weight: .semibold))
                Text("\(r.systemManagedTotal.formattedBytes) of real working storage macOS owns. Shown for transparency; not removable.")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            ForEach(r.systemManaged) { bucket in bucketRow(bucket, tint: .secondary) }
        }
        .padding(Theme.Spacing.lg).glassCard()
    }

    private func bucketRow(_ bucket: SystemDataService.Bucket, tint: Color) -> some View {
        HStack(spacing: 11) {
            Image(systemName: bucket.icon).font(.system(size: 14)).foregroundColor(tint).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(bucket.title).font(.system(size: 12, weight: .medium))
                Text(bucket.explanation).font(.system(size: 10)).foregroundColor(.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            Text(bucket.bytes.formattedBytes).font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(bucket.reclaimable ? .primary : .secondary)
        }
        .padding(.vertical, 7).padding(.horizontal, 10)
        .background(Theme.panelBackground.opacity(0.4)).clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func analyze() {
        isLoading = true
        let matcher = ExclusionStore().matcher()
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                SystemDataService.analyze(exclusions: matcher)
            }.value
            await MainActor.run { self.report = result; self.isLoading = false }
        }
    }
}
