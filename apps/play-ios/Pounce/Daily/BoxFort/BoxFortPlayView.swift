import PounceKit
import SwiftUI

/// Box Fort's board and controls (the host draws the top bar, the clock and the end): the score
/// row, the rug, and the tray of three pieces to drag onto it.
///
/// Holding 120 Hz while dragging: the finger moves one small layer (`BoxFortLifted`); the aim
/// layer redraws only when the snapped spot changes; the rug redraws only when boxes do.
struct BoxFortPlayView: View {
    let model: BoxFortPlayModel
    @State private var drag = BoxFortDrag()
    @State private var refused = 0

    static let space = "boxfort.play"

    var body: some View {
        GeometryReader { geo in
            let layout = BoxFortLayout(size: geo.size)
            let state = model.state
            ZStack(alignment: .topLeading) {
                BoxFortHeader(points: state.points, combo: state.combo, set: state.set, sets: state.sets, height: layout.header.height)
                    .frame(width: layout.header.width)
                    .offset(x: layout.header.minX, y: layout.header.minY)
                BoxFortRugView(rug: state.rug, cell: layout.cell)
                    .equatable()
                    .offset(x: layout.rug.minX, y: layout.rug.minY)
                    .accessibilityElement()
                    .accessibilityLabel("Rug")
                    .accessibilityValue("\(state.rug.filter { $0 != 0 }.count) boxes")
                    .accessibilityIdentifier("boxfort.rug")
                BoxFortAim(drag: drag, model: model, layout: layout)
                BoxFortBurstLayer(burst: model.burst, layout: layout)
                ForEach(0..<3, id: \.self) { slot in
                    tray(slot: slot, layout: layout)
                }
                BoxFortGainLayer(gain: model.gain, layout: layout)
                if let over = state.over {
                    BoxFortOverStamp(over: over, layout: layout)
                }
                BoxFortLifted(drag: drag, pieces: state.pieces, layout: layout)
                #if DEBUG
                    // For the UI tests: the board as data, at the view's top-left (its frame is the origin).
                    Color.clear
                        .frame(width: 1, height: 1)
                        .accessibilityElement()
                        .accessibilityIdentifier("boxfort.state")
                        .accessibilityValue(BoxFortPlayView.debugValue(model, layout))
                #endif
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .coordinateSpace(.named(Self.space))
            .animation(.spring(duration: Pace.seconds(0.35), bounce: 0.4), value: state.over)
        }
        .onChange(of: model.burst) { _, burst in
            guard let burst else { return }
            Sound.shared.play(ArtName.Sound.sfxSparkle, kind: .game)
            if burst.lines >= 2 || model.state.combo >= 3 { Haptics.shared.celebrate() } else { Haptics.shared.success() }
        }
        .onChange(of: model.state.over) { _, over in
            if over == .full {
                Sound.shared.play(ArtName.Sound.sfxFanfare, kind: .game)
                Haptics.shared.celebrate()
            } else if over == .stuck {
                Sound.shared.play(ArtName.Sound.sfxThud, kind: .game)
                Haptics.shared.thump()
            }
        }
        .onChange(of: model.dealt) { Sound.shared.play(ArtName.Sound.sfxWhoosh, volume: 0.6, kind: .game) }
    }

    #if DEBUG
        /// `rug=<64 tints>|x=<rug left>|y=<rug top>|cell=<spot side>|pieces=<cells>/<cells>/<cells>|placed=010|ready=1`,
        /// a piece's cells as `rc` pairs ("00 01 10"). `ready` is 0 while a set is on its way or the run is over.
        static func debugValue(_ model: BoxFortPlayModel, _ layout: BoxFortLayout) -> String {
            let s = model.state
            let pieces = s.pieces.map { $0.cells.map { "\($0.row)\($0.col)" }.joined(separator: " ") }.joined(separator: "/")
            return [
                "rug=" + s.rug.map(String.init).joined(),
                String(format: "x=%.2f", layout.rug.minX), String(format: "y=%.2f", layout.rug.minY), String(format: "cell=%.3f", layout.cell),
                "pieces=" + pieces,
                "placed=" + s.placed.map { $0 ? "1" : "0" }.joined(),
                "ready=" + (model.canPlace ? "1" : "0"),
            ].joined(separator: "|")
        }
    #endif

    @ViewBuilder
    private func tray(slot: Int, layout: BoxFortLayout) -> some View {
        let state = model.state
        let rect = layout.slots[slot]
        let showing = state.pieces.indices.contains(slot) && !state.placed[slot]
            && drag.slot != slot && model.landing?.slot != slot && !model.waiting
        ZStack(alignment: .topLeading) {
            if showing {
                BoxFortTrayPiece(piece: state.pieces[slot], layout: layout, slot: slot, fits: model.fits[slot])
                    .pop(trigger: model.dealt)
                    .shake(trigger: refused)
            }
            // The whole slot takes the finger, so a one-box piece is as easy to pick up as any.
            Color.clear
                .contentShape(Rectangle())
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .gesture(dragGesture(slot: slot, layout: layout))
                .accessibilityElement()
                .accessibilityLabel("Piece \(slot + 1)")
                .accessibilityValue(showing ? "\(state.pieces[slot].cells.count) boxes" : "Empty")
                .accessibilityIdentifier("boxfort.slot.\(slot)")
        }
    }

    private func dragGesture(slot: Int, layout: BoxFortLayout) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { value in
                let state = model.state
                if drag.slot == nil {
                    guard model.canPlace, state.pieces.indices.contains(slot), !state.placed[slot] else { return }
                    drag.begin(slot: slot, at: value.location)
                    Haptics.shared.prepare()
                    Haptics.shared.tick()
                }
                guard drag.slot == slot else { return }
                drag.move(to: value.location)
                aim(piece: state.pieces[slot], finger: value.location, layout: layout)
            }
            .onEnded { _ in
                guard drag.slot == slot else { return }
                let spot = drag.spot
                drag.end()
                guard let spot else {
                    refused += 1
                    Sound.shared.play(ArtName.Sound.sfxNope, volume: 0.5)
                    return
                }
                Task {
                    if await model.place(slot: slot, at: spot) {
                        Haptics.shared.drop()
                        Sound.shared.play(ArtName.Sound.sfxPop, kind: .game)
                    } else {
                        refused += 1
                    }
                }
            }
    }

    /// Where the lifted piece would land, and which lines it would clear. A single placement is
    /// a few dozen checks, done only when the snapped spot changes.
    private func aim(piece: BoxFortPiece, finger: CGPoint, layout: BoxFortLayout) {
        let size = piece.size
        let spot = layout.snap(origin: layout.lifted(finger: finger, size: size), size: size)
        guard spot != drag.spot else { return }
        guard let spot, let landed = BoxFortRules.place(model.state.rug, piece, row: spot.row, col: spot.col) else {
            drag.aim(nil, clears: .none)
            return
        }
        drag.aim(spot, clears: landed.cleared)
        Haptics.shared.tick()
    }
}

/// The piece under the finger: one layer, moved, never redrawn while it moves.
private struct BoxFortLifted: View {
    let drag: BoxFortDrag
    let pieces: [BoxFortPiece]
    let layout: BoxFortLayout

    var body: some View {
        if let slot = drag.slot, pieces.indices.contains(slot) {
            let piece = pieces[slot]
            let origin = layout.lifted(finger: drag.finger, size: piece.size)
            BoxFortLiftedPiece(piece: piece, cell: layout.cell)
                .offset(x: origin.x, y: origin.y)
                .allowsHitTesting(false)
                .transaction { $0.animation = nil }
        }
    }
}

/// Grows from tray size to rug size as it's picked up.
private struct BoxFortLiftedPiece: View {
    let piece: BoxFortPiece
    let cell: CGFloat
    @State private var up = false

    var body: some View {
        BoxFortPieceView(piece: piece, cell: cell)
            .equatable()
            .scaleEffect(up ? 1.04 : BoxFortLayout.trayScale, anchor: .bottom)
            .onAppear {
                withAnimation(.spring(duration: Pace.seconds(0.18), bounce: 0.35)) { up = true }
            }
    }
}

/// Where the lifted piece would land: a see-through copy on the rug, and a glow on each line
/// it would clear. Also the piece just let go, solid, until the rules take it.
private struct BoxFortAim: View {
    let drag: BoxFortDrag
    let model: BoxFortPlayModel
    let layout: BoxFortLayout

    var body: some View {
        let state = model.state
        ZStack(alignment: .topLeading) {
            if let slot = drag.slot, let spot = drag.spot, state.pieces.indices.contains(slot) {
                Canvas { ctx, _ in
                    var glow = Path()
                    for row in drag.clears.rows { glow.addRect(layout.lineRect(row: row)) }
                    for col in drag.clears.cols { glow.addRect(layout.lineRect(col: col)) }
                    ctx.fill(glow, with: .color(.white.opacity(0.3)))
                    ctx.stroke(glow, with: .color(Palette.yellow), lineWidth: 3)
                }
                Canvas { ctx, _ in
                    let origin = layout.cellRect(row: spot.row, col: spot.col).origin
                    BoxFortArt.drawPiece(&ctx, piece: state.pieces[slot], origin: origin, cell: layout.cell)
                }
                .compositingGroup()
                .opacity(0.45)
            }
            if let landing = model.landing {
                Canvas { ctx, _ in
                    let origin = layout.cellRect(row: landing.at.row, col: landing.at.col).origin
                    BoxFortArt.drawPiece(&ctx, piece: landing.piece, origin: origin, cell: layout.cell)
                }
            }
        }
        .frame(width: layout.size.width, height: layout.size.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension BoxFortLayout {
    func lineRect(row: Int) -> CGRect { CGRect(x: rug.minX, y: rug.minY + CGFloat(row) * cell, width: rug.width, height: cell) }
    func lineRect(col: Int) -> CGRect { CGRect(x: rug.minX + CGFloat(col) * cell, y: rug.minY, width: cell, height: rug.height) }
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
