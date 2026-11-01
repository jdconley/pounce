import SwiftUI

enum PillSize {
    case small, medium, large

    var height: CGFloat {
        switch self {
        case .small: 44
        case .medium: 58
        case .large: 76
        }
    }

    var width: CGFloat { height * 1.6 }
}

/// A glossy candy pill with an icon, a 6 pt bottom "lip", and a 4 pt press-down.
struct PillButton: View {
    let icon: String
    let color: Color
    let size: PillSize
    /// Overrides the size's default width (e.g. full-width CTAs).
    let width: CGFloat?
    let accessibilityLabel: LocalizedStringKey
    let action: () -> Void

    init(
        icon: String, color: Color, size: PillSize = .large, width: CGFloat? = nil,
        accessibilityLabel: LocalizedStringKey, action: @escaping () -> Void
    ) {
        self.icon = icon
        self.color = color
        self.size = size
        self.width = width
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    var body: some View {
        Button {
            Haptics.shared.tick()
            Sound.shared.play(ArtName.Sound.sfxTick)
            action()
        } label: {
            EmptyView()
        }
        .buttonStyle(PillButtonStyle(icon: icon, color: color, size: size, width: width))
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct PillButtonStyle: ButtonStyle {
    let icon: String
    let color: Color
    let size: PillSize
    let width: CGFloat?

    static let lip: CGFloat = 6
    static let press: CGFloat = 4
    static let outline: CGFloat = 4

    func makeBody(configuration: Configuration) -> some View {
        let w = width ?? size.width
        let h = size.height
        let travel = configuration.isPressed ? Self.press : 0
        ZStack(alignment: .top) {
            // The lip: a darker pill peeking out below the face.
            Capsule()
                .fill(color.mix(with: Palette.ink, by: 0.5))
                .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: Self.outline))
                .frame(width: w, height: h)
                .offset(y: Self.lip)
            // The face.
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [color.mix(with: .white, by: 0.35), color, color.mix(with: Palette.ink, by: 0.15)],
                        startPoint: .top, endPoint: .bottom)
                )
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(.white.opacity(0.5))
                        .frame(width: w * 0.62, height: h * 0.2)
                        .padding(.top, h * 0.08)
                }
                .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: Self.outline))
                .overlay {
                    Image(icon)
                        .resizable()
                        .scaledToFit()
                        .frame(height: h * 0.58)
                        .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 2)
                }
                .frame(width: w, height: h)
                .offset(y: travel)
        }
        .frame(width: w, height: h + Self.lip)
        .contentShape(Rectangle())
        .animation(.spring(duration: 0.12, bounce: 0.2), value: configuration.isPressed)
    }
}

#Preview("Design gallery") {
    ScrollView {
        VStack(spacing: 28) {
            OutlinedText("POUNCE", size: 56, fill: Palette.orange)
            OutlinedText("Mochi", size: 32)
            OutlinedText("BCD23", size: 40, fill: Palette.lime, width: 4)
            HStack(spacing: 12) {
                ForEach(Array(Palette.playerRings.enumerated()), id: \.offset) { _, c in
                    Circle().fill(c).frame(width: 34, height: 34)
                        .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 4))
                }
            }
            HStack(spacing: 16) {
                PillButton(icon: ArtName.iconPlus, color: Palette.magenta, size: .small, accessibilityLabel: "New game") {}
                PillButton(icon: ArtName.iconKeypad, color: Palette.teal, size: .medium, accessibilityLabel: "Join") {}
            }
            PillButton(icon: ArtName.iconPlay, color: Palette.orange, size: .large, accessibilityLabel: "Play") {}
            PillButton(icon: ArtName.iconShare, color: Palette.sky, accessibilityLabel: "Share") {}
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }
    .background(Palette.night)
}
