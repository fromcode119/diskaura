import SwiftUI

enum Theme {
    static func tagColor(_ tag: NodeTag) -> Color {
        switch tag {
        case .keep: return Color(red: 0.16, green: 0.82, blue: 0.45)
        case .clean: return Color(red: 1.00, green: 0.52, blue: 0.09)
        case .archive: return Color(red: 0.42, green: 0.40, blue: 1.00)
        case .system: return Color(red: 1.00, green: 0.27, blue: 0.35)
        }
    }

    // Blue→violet, matching the reference apps (iStat/CleanMyMac lead with blue/purple, never
    // orange). The old gold accent was a big reason the app read as "off" next to those refs.
    static let accent = Color(red: 0.42, green: 0.51, blue: 0.98)

    /// Primary CTA / hero gradient — the blue→violet sweep the references use on their
    /// prominent buttons and donuts.
    static let accentGradient = LinearGradient(
        colors: [Color(red: 0.40, green: 0.56, blue: 1.00), Color(red: 0.60, green: 0.42, blue: 0.98)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// Subtle purple-tinted backdrop gradient — the references' glassy cards float over a
    /// colored desktop; a full-window app fakes that with a gentle gradient canvas so the
    /// translucent cards have something to pick up, instead of flat near-black.
    static let appGradient = LinearGradient(
        colors: [Color(red: 0.12, green: 0.11, blue: 0.19), Color(red: 0.055, green: 0.055, blue: 0.085)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let sidebarGradient = LinearGradient(
        colors: [Color(red: 0.10, green: 0.09, blue: 0.16), Color(red: 0.06, green: 0.06, blue: 0.10)],
        startPoint: .top, endPoint: .bottom
    )

    static let appBackground = Color(red: 0.075, green: 0.072, blue: 0.11)
    static let sidebarBackground = Color(red: 0.078, green: 0.078, blue: 0.090)
    static let panelBackground = Color(red: 0.122, green: 0.122, blue: 0.145)
    static let rowHover = Color.white.opacity(0.05)
    static let border = Color.white.opacity(0.08)

    /// CleanMyMac's actual signature isn't a single accent — every module (System Junk,
    /// Space Lens, Uninstaller, Speed) has its own distinct color so the sidebar itself
    /// reads as colorful and modular rather than one monochrome icon rail.
    static func moduleColor(_ tab: SidebarTab) -> Color {
        switch tab {
        case .scan: return Color(red: 0.34, green: 0.62, blue: 1.00)
        case .largeOldFiles: return Color(red: 1.00, green: 0.62, blue: 0.20)
        case .systemData: return Color(red: 0.45, green: 0.72, blue: 0.95)
        case .cleanup: return Color(red: 0.30, green: 0.80, blue: 0.90)
        case .smartRules: return Color(red: 0.62, green: 0.55, blue: 0.98)
        case .assistant: return Color(red: 0.42, green: 0.78, blue: 0.92)
        case .duplicates: return Color(red: 0.68, green: 0.48, blue: 1.00)
        case .uninstaller: return Color(red: 1.00, green: 0.38, blue: 0.44)
        case .processes: return Color(red: 0.30, green: 0.82, blue: 0.58)
        case .loginItems: return Color(red: 0.98, green: 0.72, blue: 0.25)
        case .settings: return Color(red: 0.58, green: 0.60, blue: 0.66)
        }
    }

    static let cardRadius: CGFloat = 14

    // More generous spacing scale — the old values were too tight and read as a dense
    // developer tool. CleanMyMac's whole feel comes from whitespace.
    enum Spacing {
        static let xs: CGFloat = 6
        static let sm: CGFloat = 10
        static let md: CGFloat = 18
        static let lg: CGFloat = 26
        static let xl: CGFloat = 36
    }

    // Bigger, friendlier type — the app was full of 10-11px monospace that read as a
    // terminal. Titles are prominent, body is comfortably readable, mono is reserved for
    // actual sizes/paths only.
    enum TypeScale {
        static let eyebrow = Font.system(size: 11, weight: .semibold)
        static let body = Font.system(size: 13, weight: .regular)
        static let bodyEmphasis = Font.system(size: 13, weight: .semibold)
        static let title = Font.system(size: 22, weight: .bold)
        static let sectionTitle = Font.system(size: 15, weight: .semibold)
        static let mono = Font.system(size: 12, design: .monospaced)
    }
}

/// Big, fully-rounded CTA button — CleanMyMac's primary actions (Smart Scan, Clean Up)
/// are pill-shaped, not the standard macOS rounded-rect `.borderedProminent` look, which
/// read as a stock system button rather than a distinct product identity.
struct PillButtonStyle: ButtonStyle {
    var color: Color = Theme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(color.opacity(configuration.isPressed ? 0.75 : 1))
            .foregroundColor(.white)
            .clipShape(Capsule())
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { PillButtonStyle() }
    static func pill(_ color: Color) -> PillButtonStyle { PillButtonStyle(color: color) }
}

/// Gradient-filled pill for the ONE primary action per screen (Scan) — matches the
/// blue→violet CTA buttons in the reference apps.
struct GradientPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(Theme.accentGradient)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .foregroundColor(.white)
            .clipShape(Capsule())
    }
}

extension ButtonStyle where Self == GradientPillButtonStyle {
    static var gradientPill: GradientPillButtonStyle { GradientPillButtonStyle() }
}

extension View {
    /// Premium elevated card, tuned from actual dark-glassmorphism research (macOS 14 glass
    /// guide + NN/g): the glass illusion lives in the EDGES, not the fill, so the border is a
    /// soft gradient (bright-ish top → near-invisible bottom) — and NOT harsh pure white,
    /// which glows in dark mode. The shadow is deliberately SMALL and low-opacity (a 18px/0.45
    /// shadow across a grid "drowns the UI in grey" — the exact mistake I'd made). Multiple
    /// light cues compound: subtle fill gradient + top-edge highlight + gradient border +
    /// small shadow, all lit consistently from the top.
    func glassCard(cornerRadius: CGFloat = Theme.cardRadius, tint: Color? = nil) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.155, green: 0.155, blue: 0.20),
                                Color(red: 0.115, green: 0.115, blue: 0.155)
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
            )
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill((tint ?? .clear).opacity(tint == nil ? 0 : 0.13))
            )
            // Bright inner top-edge highlight (light from above) — the primary "glass" cue.
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.16), Color.white.opacity(0.02), Color.clear],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            // Small, soft shadow — light from top, shadow just below. NOT a big muddy blur.
            .shadow(color: Color.black.opacity(0.28), radius: 8, x: 0, y: 4)
    }
}

struct TagPill: View {
    let tag: NodeTag

    var body: some View {
        Text(tag.label)
            .font(.system(size: 9, weight: .bold))
            .textCase(.uppercase)
            .tracking(0.5)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.tagColor(tag).opacity(0.16))
            .foregroundColor(Theme.tagColor(tag))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

/// A de-boxed section header — small caps eyebrow label, no card chrome.
/// Use in place of the old bordered-card pattern so panels read as native
/// list groupings rather than nested forms.
struct SectionEyebrow: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(Theme.TypeScale.eyebrow)
            .foregroundColor(.secondary)
            .tracking(0.8)
    }
}
