import PounceKit
import SwiftUI

// The TV's shared pieces, laid out in 1920 x 1080 points inside the TV-safe area and read from
// the couch: nothing that matters is under 28 pt. A remote's focus is a yellow glow and a lift.

/// The room behind a TV screen: the iPhone's art filling the frame, softened and darkened at the
/// edges so the screen's own things stand out (the web TV's `.tv-bg`).
struct TVBackdrop: View {
    let art: String

    /// Width over height of the room art (`home-bg`, `room-bg`: 390 x 844 points).
    private static let artAspect: CGFloat = 390.0 / 844.0

    var body: some View {
        GeometryReader { g in
            // The iPhone's art is tall: fill the width and show the band 34% of the way down.
            let tall = g.size.width / Self.artAspect
            Image(art)
                .resizable()
                .frame(width: g.size.width, height: tall)
                .offset(y: (g.size.height - tall) * 0.34)
                .frame(width: g.size.width, height: g.size.height, alignment: .top)
                .clipped()
                .blur(radius: 6, opaque: true)
                .overlay {
                    RadialGradient(
                        colors: [Palette.ink.opacity(0.15), Palette.ink.opacity(0.7)], center: .center,
                        startRadius: g.size.width * 0.2, endRadius: g.size.width * 0.7)
                }
                .overlay {
                    LinearGradient(colors: [Palette.night.opacity(0.35), Palette.ink.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                }
        }
        .background(Palette.night)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// A chunky button for the remote: a candy gradient in an ink outline with an ink drop under it.
/// Focused, it lifts and glows yellow; pressed, it sinks.
struct TVButtonStyle: ButtonStyle {
    var tint: Color = Palette.violet
    var corner: CGFloat = 40

    func makeBody(configuration: Configuration) -> some View {
        Face(configuration: configuration, tint: tint, corner: corner)
    }

    private struct Face: View {
        let configuration: Configuration
        let tint: Color
        let corner: CGFloat
        @Environment(\.isFocused) private var focused

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
            configuration.label
                .background(
                    shape.fill(LinearGradient(colors: [tint.mix(with: .white, by: 0.25), tint, tint.mix(with: Palette.ink, by: 0.25)], startPoint: .top, endPoint: .bottom)))
                .overlay(shape.inset(by: 3).strokeBorder(.white.opacity(0.35), lineWidth: 4).padding(3).mask(alignment: .top) { Rectangle().frame(height: 30) })
                .overlay(shape.strokeBorder(Palette.ink, lineWidth: 6))
                .background(shape.fill(Palette.ink).offset(y: configuration.isPressed ? 4 : 12))
                .overlay(shape.inset(by: -10).strokeBorder(Palette.yellow, lineWidth: 8).opacity(focused ? 1 : 0))
                .compositingGroup()
                .shadow(color: Palette.yellow.opacity(focused ? 0.55 : 0), radius: 36)
                .scaleEffect(configuration.isPressed ? 0.97 : focused ? 1.05 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: focused)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}

/// A row button's label: an icon and one to three words.
struct TVButtonLabel: View {
    let icon: String
    let words: String
    var size: CGFloat = 46

    var body: some View {
        HStack(spacing: 24) {
            Image(icon)
                .resizable()
                .scaledToFit()
                .frame(width: size * 1.45, height: size * 1.45)
            OutlinedText(words, size: size, width: 3.5)
                .fixedSize()
        }
        .padding(.horizontal, 44)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
    }
}

/// A QR code for a phone to scan, in a cat-eared frame.
struct TVQRCode: View {
    let text: String?
    var side: CGFloat = 400

    var body: some View {
        ZStack(alignment: .top) {
            HStack(spacing: side * 0.62) {
                Ear()
                Ear().scaleEffect(x: -1)
            }
            .offset(y: -side * 0.1)
            Group {
                if let text {
                    QRTile(text: text, side: side, padding: 26, corner: 40, outline: 7)
                } else {
                    RoundedRectangle(cornerRadius: 40, style: .continuous)
                        .fill(.white)
                        .overlay(RoundedRectangle(cornerRadius: 40, style: .continuous).strokeBorder(Palette.ink, lineWidth: 7))
                        .frame(width: side + 52, height: side + 52)
                        .shadow(color: Palette.ink.opacity(0.55), radius: 0, x: 0, y: 10)
                }
            }
        }
        .padding(.top, side * 0.08)
        .compositingGroup()
    }

    /// A cat's ear on the frame's corner.
    private struct Ear: View {
        var body: some View {
            Triangle()
                .fill(Palette.violet)
                .overlay(Triangle().inset(0.3).fill(Palette.magenta))
                .overlay(Triangle().stroke(Palette.ink, style: StrokeStyle(lineWidth: 7, lineJoin: .round)))
                .frame(width: 96, height: 96)
                .rotationEffect(.degrees(-14))
        }
    }

    private struct Triangle: Shape {
        var insetShare: CGFloat = 0

        func inset(_ share: CGFloat) -> Triangle { Triangle(insetShare: share) }

        func path(in rect: CGRect) -> Path {
            let r = rect.insetBy(dx: rect.width * insetShare / 2, dy: rect.height * insetShare / 2)
            var p = Path()
            p.move(to: CGPoint(x: r.minX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX + r.width * 0.32, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.closeSubpath()
            return p
        }
    }
}

/// A link's backup code, typed on a phone: big, spaced, white on ink.
struct TVCode: View {
    let code: String?
    var size: CGFloat = 92
    var label: String

    var body: some View {
        Text(verbatim: code ?? "      ")
            .font(.system(size: size, weight: .black, design: .rounded).monospaced())
            .tracking(size * 0.18)
            .foregroundStyle(.white)
            .padding(.leading, size * 0.18)
            .padding(.horizontal, 36)
            .padding(.vertical, 6)
            .background(Capsule().fill(Palette.ink.opacity(0.85)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.9), lineWidth: 4))
            .opacity(code == nil ? 0.4 : 1)
            .accessibilityLabel(code.map { "\(label) \($0.map(String.init).joined(separator: " "))" } ?? "")
    }
}

/// "Reconnecting": an ink pill with a beating red dot.
struct TVReconnecting: View {
    @State private var beat = false

    var body: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(Palette.refuse)
                .frame(width: 22, height: 22)
                .opacity(beat ? 1 : 0.35)
            Text("Reconnecting", comment: "TV: the table or link lost its connection and is getting it back")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 12)
        .background(Capsule().fill(Palette.ink))
        .overlay(Capsule().strokeBorder(.white.opacity(0.85), lineWidth: 3))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { beat = true }
        }
        .accessibilityElement(children: .combine)
    }
}

/// An outlined line with an icon in front, for what to do on a phone.
struct TVHint: View {
    let icon: String
    let words: String
    var size: CGFloat = 44

    var body: some View {
        HStack(spacing: 18) {
            Image(icon)
                .resizable()
                .scaledToFit()
                .frame(width: size * 1.3, height: size * 1.3)
            OutlinedText(words, size: size, width: 3.5)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(words)
    }
}

/// The menu's paw in the corner every TV screen at a table keeps free: the bottom-right of the
/// TV-safe area, where the table's scene draws its own paw. Select (or Menu) opens the menu.
struct TVMenuPaw: View {
    /// The scene draws the paw at the table; elsewhere this does.
    var drawsIcon = true
    let open: () -> Void

    static let side: CGFloat = 88

    var body: some View {
        Button(action: open) {
            Color.clear
                .frame(width: Self.side, height: Self.side)
                .overlay {
                    if drawsIcon {
                        Image(ArtName.iconPawMenu).resizable().scaledToFit()
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(PawStyle())
        .accessibilityLabel(Text("Table menu", comment: "TV: the paw that opens the menu at a table"))
        .accessibilityIdentifier("tv.paw")
    }

    private struct PawStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View { Face(configuration: configuration) }

        private struct Face: View {
            let configuration: Configuration
            @Environment(\.isFocused) private var focused

            var body: some View {
                configuration.label
                    .background {
                        Circle()
                            .strokeBorder(Palette.yellow, lineWidth: 7)
                            .padding(-14)
                            .shadow(color: Palette.yellow.opacity(0.6), radius: 24)
                            .opacity(focused ? 1 : 0)
                    }
                    .scaleEffect(configuration.isPressed ? 0.94 : focused ? 1.08 : 1)
                    .animation(.spring(response: 0.25, dampingFraction: 0.6), value: focused)
            }
        }
    }
}

/// The colour of seat `seat`'s ring.
func tvRing(_ seat: Seat) -> Color {
    Palette.playerRings[seat % Palette.playerRings.count]
}
