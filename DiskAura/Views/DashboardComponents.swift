import SwiftUI

/// Donut / ring gauge — the signature stat visual in CleanMyMac / iStat-style dashboards.
/// A track ring plus a colored progress arc with a big value in the middle.
struct RingGauge: View {
    let fraction: Double
    let centerValue: String
    let centerLabel: String
    var color: Color = Theme.accent
    var size: CGFloat = 128
    var lineWidth: CGFloat = 14

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(fraction, 1)))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [color.opacity(0.65), color]),
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text(centerValue)
                    .font(.system(size: size * 0.2, weight: .bold, design: .rounded))
                Text(centerLabel)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}

/// A metric tile — big number + label on a subtly accent-tinted gradient card, like the
/// dashboard tiles in the reference apps. Optional trailing spark content.
struct MetricTile: View {
    let icon: String
    let label: String
    let value: String
    var accent: Color = Theme.accent
    var caption: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(accent.opacity(0.22))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(accent)
            }
            Spacer(minLength: 10)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption ?? " ")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
        .padding(14)
        .glassCard(tint: accent)
    }
}

/// Reusable premium card container — subtle border + dark surface, used to wrap dashboard
/// sections so the whole app shares one card language.
struct DashboardCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .padding(18)
            .glassCard()
    }
}
