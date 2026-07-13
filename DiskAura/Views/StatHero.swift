import SwiftUI

/// One glowing stat tile in a hero row. `sparkline`, when present, draws a mini trend at the
/// bottom of the tile (e.g. CPU load over time).
struct StatTileData: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let glow: Color
    var icon: String = "circle.fill"
    var valueColor: Color? = nil
    var sparkline: [Double]? = nil
}

/// The shared hero used at the top of every module: a donut + legend card on the left and a
/// 2×2 grid of stat tiles on the right — ALL at one fixed height so the cards line up exactly
/// across screens. Previously each screen hand-rolled this with slightly different paddings and
/// heights, so nothing matched; this is the single source of truth.
struct StatHero: View {
    let segments: [DonutSegment]
    let centerValue: String
    let centerLabel: String
    let tiles: [StatTileData]        // exactly 4

    static let height: CGFloat = 168
    static let donutCardWidth: CGFloat = 430
    private static let rowGap: CGFloat = 12
    private var tileRowHeight: CGFloat { (Self.height - Self.rowGap) / 2 }

    var body: some View {
        // Explicit heights (not maxHeight:.infinity) so the donut card and every tile are
        // pixel-identical in height — otherwise the intrinsic sizes drift a few points and the
        // cards visibly fail to line up.
        HStack(alignment: .top, spacing: 12) {
            HStack(spacing: 18) {
                CategoryDonut(segments: segments, centerValue: centerValue, centerLabel: centerLabel,
                              size: 116, lineWidth: 15)
                DonutLegend(segments: segments).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .frame(width: Self.donutCardWidth, height: Self.height, alignment: .center)
            .glassCard()

            VStack(spacing: Self.rowGap) {
                HStack(spacing: 12) { tile(at: 0); tile(at: 1) }
                HStack(spacing: 12) { tile(at: 2); tile(at: 3) }
            }
        }
        .frame(height: Self.height)
    }

    @ViewBuilder private func tile(at index: Int) -> some View {
        Group {
            if index < tiles.count { StatTileView(data: tiles[index]) } else { Color.clear }
        }
        .frame(maxWidth: .infinity)
        .frame(height: tileRowHeight)
    }
}

private struct StatTileView: View {
    let data: StatTileData

    var body: some View {
        HStack(spacing: 13) {
            // Colored glossy icon tile — the same tactile square as the sidebar, so a stat
            // tile reads as "designed" instead of a value floating in an empty rectangle.
            RoundedRectangle(cornerRadius: 10)
                .fill(LinearGradient(colors: [data.glow, data.glow.opacity(0.72)], startPoint: .top, endPoint: .bottom))
                .frame(width: 40, height: 40)
                .overlay(Image(systemName: data.icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.16), lineWidth: 0.5))
                .shadow(color: data.glow.opacity(0.4), radius: 6, y: 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(data.title).font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary).lineLimit(1)
                Text(data.value)
                    .font(.system(size: 23, weight: .semibold, design: .rounded))
                    .foregroundColor(data.valueColor ?? .primary)
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            }

            Spacer(minLength: 4)

            if let spark = data.sparkline {
                Sparkline(values: spark, color: data.glow, maxValue: 100).frame(width: 60, height: 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 15).padding(.vertical, 12)
        .background(
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: Theme.cardRadius).fill(Theme.panelBackground)
                Circle().fill(data.glow).frame(width: 70, height: 70).blur(radius: 26).opacity(0.28)
                    .offset(x: 20, y: -22)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        )
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.border, lineWidth: 1))
    }
}
