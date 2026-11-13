import SwiftUI

// The rows Settings is built from (`GearSheet`): groups with a short label over one rounded card,
// rows with a round icon, words, and a switch, a chevron or an arrow at the end. At the
// accessibility text sizes the words drop under the icon and the control, so they get the row's
// whole width.

/// A short label over one rounded card of rows, a hairline between them.
struct SettingsGroup<Content: View>: View {
    var title: Text?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                title
                    .font(.system(.subheadline, design: .rounded, weight: .black))
                    .textCase(.uppercase)
                    .tracking(1)
                    .foregroundStyle(Palette.lime)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) {
                Group(subviews: content) { rows in
                    ForEach(rows) { row in
                        if row.id != rows.first?.id {
                            Rectangle()
                                .fill(.white.opacity(0.1))
                                .frame(height: 1.5)
                                .padding(.leading, 14)
                                .accessibilityHidden(true)
                        }
                        row
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Palette.ink.opacity(0.4))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.ink, lineWidth: 3)))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }
}

/// A row's round picture: art, or an SF Symbol in white, on a glossy disc.
struct SettingsIcon: View {
    enum Glyph {
        case art(String)
        case symbol(String)
    }

    let glyph: Glyph
    let color: Color
    var side: CGFloat = 42

    var body: some View {
        Circle()
            .fill(LinearGradient(colors: [color.mix(with: .white, by: 0.3), color], startPoint: .top, endPoint: .bottom))
            .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 3))
            .overlay {
                switch glyph {
                case .art(let name):
                    Image(name).resizable().scaledToFit().padding(side * 0.17)
                case .symbol(let name):
                    Image(systemName: name)
                        .font(.system(size: side * 0.42, weight: .black))
                        .foregroundStyle(.white)
                        .shadow(color: Palette.ink.opacity(0.6), radius: 0, x: 0, y: 1.5)
                }
            }
            .frame(width: side, height: side)
            .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 3)
            .accessibilityHidden(true)
    }
}

/// A chunky on/off switch: the knob slides right and the track lights up lime.
struct ToySwitch: View {
    let on: Bool
    var color: Color = Palette.lime

    var body: some View {
        ZStack(alignment: on ? .trailing : .leading) {
            Capsule()
                .fill(on
                    ? AnyShapeStyle(LinearGradient(colors: [color.mix(with: .white, by: 0.25), color], startPoint: .top, endPoint: .bottom))
                    : AnyShapeStyle(Palette.night.mix(with: Palette.ink, by: 0.4)))
                .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 3))
            Circle()
                .fill(on ? .white : .white.opacity(0.7))
                .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 3))
                .padding(4)
                .shadow(color: Palette.ink.opacity(0.4), radius: 0, x: 0, y: 2)
        }
        .frame(width: 60, height: 36)
        .compositingGroup()
        .animation(.spring(duration: 0.25, bounce: 0.4).paced, value: on)
        .accessibilityHidden(true)
    }
}

/// What a row does when tapped, drawn at its end.
enum SettingsRowEnd {
    /// Turns something on or off; the color is the icon's while on.
    case toggle(Bool, Color)
    /// Opens a page inside Settings (or another sheet): a chevron.
    case page
    /// Leaves the app (a web page, the App Store): an arrow out.
    case external
    /// Does it right here: nothing at the end, or `value` when there is one.
    case action
}

/// One tappable row: icon, title, an optional detail line, an optional value, and its end.
struct SettingsRow<Icon: View>: View {
    let title: Text
    var detail: Text?
    var value: Text?
    var end: SettingsRowEnd = .page
    var destructive = false
    @ViewBuilder let icon: Icon
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button {
            Haptics.shared.tick()
            Sound.shared.play(ArtName.Sound.sfxTick)
            action()
        } label: {
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            icon
                            Spacer(minLength: 8)
                            trailing
                        }
                        words
                        valueText
                    }
                } else {
                    HStack(spacing: 12) {
                        icon
                        // The words get their room before the spacer and the value split the rest.
                        words.layoutPriority(1)
                        Spacer(minLength: 8)
                        valueText
                        trailing
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(SettingsRowStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityValue: Text {
        if case .toggle(let on, _) = end { return on ? Text(verbatim: "on") : Text(verbatim: "off") }
        return value ?? detail ?? Text(verbatim: "")
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 2) {
            title
                .font(.system(.headline, design: .rounded, weight: .black))
                .foregroundStyle(destructive ? Palette.refuse.mix(with: .white, by: 0.35) : .white)
                // Beside the icon and the control: one line, a little smaller before it would wrap.
                // Under them (the accessibility sizes) it wraps.
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(typeSize.isAccessibilitySize ? 1 : 0.75)
            if let detail {
                detail
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var valueText: some View {
        if let value {
            value
                .font(.system(.subheadline, design: .rounded, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.85))
                // One line beside the words; under them, at the accessibility sizes, it may wrap.
                .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: true)
        }
    }

    @ViewBuilder private var trailing: some View {
        switch end {
        case .toggle(let on, _):
            ToySwitch(on: on)
        case .page:
            Image(systemName: "chevron.right")
                .font(.system(size: 17, weight: .black))
                .foregroundStyle(.white.opacity(0.6))
                .accessibilityHidden(true)
        case .external:
            Image(systemName: "arrow.up.right")
                .font(.system(size: 17, weight: .black))
                .foregroundStyle(.white.opacity(0.6))
                .accessibilityHidden(true)
        case .action:
            EmptyView()
        }
    }
}

extension SettingsRow where Icon == SettingsIcon {
    init(
        _ glyph: SettingsIcon.Glyph, color: Color, title: Text, detail: Text? = nil, value: Text? = nil,
        end: SettingsRowEnd = .page, destructive: Bool = false, action: @escaping () -> Void
    ) {
        self.title = title
        self.detail = detail
        self.value = value
        self.end = end
        self.destructive = destructive
        self.action = action
        let dim: Bool = if case .toggle(false, _) = end { true } else { false }
        self.icon = SettingsIcon(glyph: glyph, color: dim ? Palette.violet.mix(with: Palette.night, by: 0.3) : color)
    }
}

/// A row lights up a little while pressed.
private struct SettingsRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(.white.opacity(configuration.isPressed ? 0.1 : 0))
    }
}
