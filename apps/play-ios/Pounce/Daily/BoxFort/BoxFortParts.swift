import PounceKit
import SwiftUI

/// Pieces of the Box Fort screen that the play view and the TV's watch view both draw.

/// The row over the rug: points on the left, the combo when there is one, and the set count.
struct BoxFortHeader: View {
    let points: Int
    let combo: Int
    let set: Int
    let sets: Int
    let height: CGFloat

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            OutlinedText("\(points)", size: height * 0.62)
                .fixedSize()
                .pop(trigger: points)
                .accessibilityLabel("Points")
                .accessibilityValue("\(points)")
                .accessibilityIdentifier("boxfort.points")
            Spacer(minLength: 4)
            if combo >= 2 {
                Text("Combo \(combo)")
                    .font(.system(size: height * 0.34, weight: .black, design: .rounded))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Palette.yellow))
                    .overlay(Capsule().stroke(Palette.ink, lineWidth: 2.5))
                    .pop(trigger: combo)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityIdentifier("boxfort.combo")
                Spacer(minLength: 4)
            }
            Text("Set \(min(set + 1, sets)) of \(sets)")
                .font(.system(size: height * 0.34, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .monospacedDigit()
                .accessibilityIdentifier("boxfort.set")
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .frame(height: height)
        .animation(.spring(duration: Pace.seconds(0.25)), value: combo >= 2)
    }
}

/// A tray slot's piece at tray scale, centered in its slot. A piece with no room anywhere dims
/// (one layer, so its boxes don't show through each other).
struct BoxFortTrayPiece: View {
    let piece: BoxFortPiece
    let layout: BoxFortLayout
    let slot: Int
    let fits: Bool

    var body: some View {
        let origin = layout.trayOrigin(slot: slot, size: piece.size)
        BoxFortPieceView(piece: piece, cell: layout.trayCell)
            .equatable()
            .compositingGroup()
            .opacity(fits ? 1 : 0.35)
            .offset(x: origin.x, y: origin.y)
    }
}

/// The stamp across the rug when the run is over.
struct BoxFortOverStamp: View {
    let over: BoxFortState.Over
    let layout: BoxFortLayout

    var body: some View {
        let text = over == .full ? "Full fort" : "Out of room"
        OutlinedText(text, size: layout.cell * 0.85, fill: over == .full ? Palette.yellow : .white, width: 4)
            .padding(.horizontal, layout.cell * 0.4)
            .padding(.vertical, layout.cell * 0.15)
            .background(RoundedRectangle(cornerRadius: layout.cell * 0.25).fill(over == .full ? Palette.magenta : Palette.violet))
            .overlay(RoundedRectangle(cornerRadius: layout.cell * 0.25).stroke(Palette.ink, lineWidth: 4))
            .rotationEffect(.degrees(-8))
            .frame(maxWidth: layout.rug.width)
            .position(x: layout.rug.midX, y: layout.rug.midY)
            .transition(.scale(scale: 2).combined(with: .opacity))
            .accessibilityIdentifier("boxfort.over")
    }
}

/// Cleared boxes jump, flash white and burst into scraps of cardboard tape.
struct BoxFortBurstLayer: View {
    let burst: BoxFortBurst?
    let layout: BoxFortLayout

    var body: some View {
        Group {
            if let burst {
                KeyframeAnimator(initialValue: 0.0, trigger: burst.id) { t in
                    Canvas { ctx, _ in draw(&ctx, burst: burst, t: t) }
                        .allowsHitTesting(false)
                } keyframes: { _ in
                    LinearKeyframe(0.0, duration: 0.001)
                    LinearKeyframe(1.0, duration: Pace.seconds(0.55))
                }
            }
        }
        .frame(width: layout.size.width, height: layout.size.height)
    }

    private func draw(_ ctx: inout GraphicsContext, burst: BoxFortBurst, t: Double) {
        guard t > 0, t < 1 else { return }
        let cell = layout.cell
        // Boxes swell, then shrink away; a white flash fades over them.
        let scale = t < 0.25 ? 1 + 0.5 * t : max(0, 1.125 * (1 - (t - 0.25) / 0.75))
        for (index, tint) in burst.boxes {
            let spot = layout.cellRect(row: index / 8, col: index % 8)
            let r = CGRect(
                x: spot.midX - spot.width * scale / 2, y: spot.midY - spot.height * scale / 2,
                width: spot.width * scale, height: spot.height * scale)
            if r.width > 1 { BoxFortArt.drawBox(&ctx, rect: r, tint: tint) }
            ctx.fill(Path(roundedRect: r, cornerRadius: r.width * 0.14), with: .color(.white.opacity(max(0, 0.85 - t * 1.6))))
            // Four scraps fly out of each box.
            for k in 0..<4 {
                let angle = Double(index * 37 + k * 90) * .pi / 180
                let d = cell * (0.3 + 1.4 * t) * (1 + Double(burst.lines) * 0.15)
                let p = CGPoint(x: spot.midX + cos(angle) * d, y: spot.midY + sin(angle) * d + cell * 1.2 * t * t)
                let scrap = CGRect(x: p.x - cell * 0.09, y: p.y - cell * 0.05, width: cell * 0.18, height: cell * 0.1)
                ctx.fill(Path(roundedRect: scrap, cornerRadius: 2), with: .color(BoxFortArt.paint(tint).opacity(1 - t)))
            }
        }
    }
}

/// "+64" floating up from where a piece landed, bigger with a combo.
struct BoxFortGainLayer: View {
    let gain: BoxFortGain?
    let layout: BoxFortLayout

    var body: some View {
        Group {
            if let gain {
                let x = layout.rug.minX + gain.at.x * layout.cell
                let y = layout.rug.minY + gain.at.y * layout.cell
                KeyframeAnimator(initialValue: GainMotion(), trigger: gain.id) { m in
                    OutlinedText("+\(gain.points)", size: layout.cell * (gain.combo >= 2 ? 0.8 : 0.6), fill: gain.combo >= 2 ? Palette.yellow : .white)
                        .fixedSize()
                        .scaleEffect(m.scale)
                        .opacity(m.opacity)
                        .position(x: x, y: y + m.rise * layout.cell)
                } keyframes: { _ in
                    KeyframeTrack(\.scale) {
                        CubicKeyframe(1.3, duration: Pace.seconds(0.12))
                        SpringKeyframe(1, duration: Pace.seconds(0.25))
                    }
                    KeyframeTrack(\.rise) { CubicKeyframe(-1.4, duration: Pace.seconds(0.8)) }
                    KeyframeTrack(\.opacity) {
                        LinearKeyframe(1, duration: Pace.seconds(0.05))
                        LinearKeyframe(1, duration: Pace.seconds(0.45))
                        LinearKeyframe(0, duration: Pace.seconds(0.3))
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
    }

    struct GainMotion {
        var scale = 0.4
        var rise = 0.0
        var opacity = 0.0
    }
}
