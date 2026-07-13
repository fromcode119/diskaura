import SwiftUI

/// Shows what changed since the last scan of the current root — "grew by 4GB, here's what".
/// Stays silent until there's actually a prior scan to compare against, rather than
/// permanently reserving space with a "no history yet" placeholder.
struct ScanHistoryView: View {
    @ObservedObject var scanVM: ScanViewModel

    private var rootPath: String? { scanVM.result?.root.path }

    private var deltas: [SnapshotDelta] {
        guard let rootPath else { return [] }
        return scanVM.history.deltas(for: rootPath)
    }

    private var pair: (previous: ScanSnapshot, current: ScanSnapshot)? {
        guard let rootPath else { return nil }
        return scanVM.history.lastTwo(for: rootPath)
    }

    var body: some View {
        if let pair {
            let totalDelta = pair.current.totalBytes - pair.previous.totalBytes
            let grew = totalDelta >= 0
            let accent = grew ? Theme.moduleColor(.largeOldFiles) : Theme.moduleColor(.processes)
            let changed = Array(deltas.prefix(6))

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10).fill(accent.opacity(0.18))
                            .frame(width: 38, height: 38)
                        Image(systemName: grew ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 16, weight: .bold)).foregroundColor(accent)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("What changed").font(.system(size: 15, weight: .semibold))
                        Text("Since \(pair.previous.scannedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(grew ? "+" : "−")\(abs(totalDelta).formattedBytes)")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(accent)
                        Text(grew ? "grew" : "freed").font(.system(size: 10)).foregroundColor(.secondary)
                    }
                }

                if !changed.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(changed) { delta in
                            let up = delta.deltaBytes >= 0
                            HStack(spacing: 10) {
                                Image(systemName: up ? "plus" : "minus")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(up ? Theme.moduleColor(.largeOldFiles) : Theme.moduleColor(.processes))
                                    .frame(width: 16, height: 16)
                                    .background(Circle().fill((up ? Theme.moduleColor(.largeOldFiles) : Theme.moduleColor(.processes)).opacity(0.15)))
                                Text(delta.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                Spacer()
                                Text("\(up ? "+" : "−")\(abs(delta.deltaBytes).formattedBytes)")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(up ? Theme.moduleColor(.largeOldFiles) : Theme.moduleColor(.processes))
                            }
                            .padding(.vertical, 7)
                            if delta.id != changed.last?.id { Divider().padding(.leading, 26) }
                        }
                    }
                }
            }
            .padding(18)
            .glassCard()
        }
    }
}
