import PounceKit
import SwiftUI

/// Box Fort's drawing, shared by the play view and the TV's watch view: a woven rug on the floor,
/// toy boxes in loud paint with packing tape, and cats napping in the boxes that were there first.
/// Everything is drawn into a `GraphicsContext`, so a whole rug is one layer.
enum BoxFortArt {
    /// A box's paint by tint (1 to 6). `BoxFortRules.clutter` (7) is the cats' own boxes.
    static func paint(_ tint: Int) -> Color {
        switch tint {
        case 1: Palette.magenta
        case 2: Palette.teal
        case 3: Palette.orange
        case 4: Palette.sky
        case 5: Palette.lime
        case 6: Palette.yellow
        default: catBox
        }
    }

    /// The boxes the cats were already napping in: a bright lilac, unlike any piece's paint.
    static let catBox = Color(hex: 0xB57BFF)
    static let rugFill = Color(hex: 0x3B1680)
    static let rugWeave = Color(hex: 0x4A1F9C)
    static let rugBorder = Palette.magenta
    static let fringe = Palette.yellow
    static let tape = Color.white.opacity(0.5)

    // MARK: The rug

    /// The rug under the 8 by 8 spots of `rect`: a magenta border with yellow fringe at both ends,
    /// and a woven check so every spot reads as a spot.
    static func drawRug(_ ctx: inout GraphicsContext, rect: CGRect, cell: CGFloat) {
        let border = cell * 0.22
        let outer = rect.insetBy(dx: -border, dy: -border)
        // Fringe tassels top and bottom.
        let tassels = 18
        let step = outer.width / CGFloat(tassels)
        var fringePath = Path()
        for i in 0..<tassels {
            let x = outer.minX + (CGFloat(i) + 0.5) * step
            let w = step * 0.36
            let h = cell * 0.26
            fringePath.addRoundedRect(in: CGRect(x: x - w / 2, y: outer.minY - h, width: w, height: h + cell * 0.1), cornerSize: CGSize(width: w / 2, height: w / 2))
            fringePath.addRoundedRect(in: CGRect(x: x - w / 2, y: outer.maxY - cell * 0.1, width: w, height: h + cell * 0.1), cornerSize: CGSize(width: w / 2, height: w / 2))
        }
        ctx.fill(fringePath, with: .color(fringe))
        ctx.stroke(fringePath, with: .color(Palette.ink), lineWidth: max(1, cell * 0.035))
        let outerPath = Path(roundedRect: outer, cornerRadius: cell * 0.3)
        ctx.fill(outerPath, with: .color(rugBorder))
        ctx.stroke(outerPath, with: .color(Palette.ink), lineWidth: max(2, cell * 0.08))
        ctx.fill(Path(roundedRect: rect, cornerRadius: cell * 0.12), with: .color(rugFill))
        var weave = Path()
        for row in 0..<8 {
            for col in 0..<8 where (row + col) % 2 == 0 {
                weave.addRect(CGRect(x: rect.minX + CGFloat(col) * cell, y: rect.minY + CGFloat(row) * cell, width: cell, height: cell))
            }
        }
        ctx.clip(to: Path(roundedRect: rect, cornerRadius: cell * 0.12))
        ctx.fill(weave, with: .color(rugWeave))
    }

    // MARK: Boxes

    /// One box in spot `rect`. Boxes are drawn a hair inside their spot so neighbors read apart.
    /// The starting boxes (`BoxFortRules.clutter`) each hold a napping cat; `peek` puts a cat
    /// looking out of a piece's box. `coat` picks the cat's fur.
    static func drawBox(_ ctx: inout GraphicsContext, rect spot: CGRect, tint: Int, peek: Bool = false, coat: Int = 0) {
        let s = spot.width
        let r = spot.insetBy(dx: s * 0.045, dy: s * 0.045)
        let paint = paint(tint)
        let line = max(1.5, s * 0.07)
        let body = Path(roundedRect: r, cornerRadius: s * 0.14)
        let napping = tint == BoxFortRules.clutter
        guard napping || peek else {
            ctx.fill(body, with: .color(paint))
            var inner = ctx
            inner.clip(to: body)
            // Shade along the bottom, a lid highlight along the top, packing tape down the middle.
            inner.fill(Path(CGRect(x: r.minX, y: r.maxY - r.height * 0.24, width: r.width, height: r.height * 0.24)), with: .color(Palette.ink.opacity(0.22)))
            inner.fill(Path(CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height * 0.2)), with: .color(.white.opacity(0.32)))
            inner.fill(Path(CGRect(x: r.midX - r.width * 0.09, y: r.minY, width: r.width * 0.18, height: r.height * 0.56)), with: .color(tape))
            ctx.stroke(body, with: .color(Palette.ink), lineWidth: line)
            return
        }
        // An open box: its dark inside, a cat's head, then the front panel over the cat's chin.
        ctx.fill(body, with: .color(paint))
        var inner = ctx
        inner.clip(to: body)
        inner.fill(Path(r), with: .color(Palette.ink.opacity(0.45)))
        drawCat(&inner, in: r, coat: coats[coat % coats.count], awake: !napping, line: line * 0.8)
        let front = CGRect(x: r.minX, y: r.minY + r.height * 0.62, width: r.width, height: r.height * 0.38)
        inner.fill(Path(front), with: .color(paint))
        inner.fill(Path(CGRect(x: front.minX, y: front.minY, width: front.width, height: front.height * 0.28)), with: .color(.white.opacity(0.3)))
        var rim = Path()
        rim.move(to: CGPoint(x: front.minX, y: front.minY))
        rim.addLine(to: CGPoint(x: front.maxX, y: front.minY))
        inner.stroke(rim, with: .color(Palette.ink), lineWidth: line * 0.8)
        ctx.stroke(body, with: .color(Palette.ink), lineWidth: line)
    }

    /// Cat fur for the cats in boxes: ginger, smoke, snow and midnight.
    private static let coats: [Color] = [Color(hex: 0xFF9A3C), Color(hex: 0xA7B0C8), .white, Color(hex: 0x4B3A78)]

    /// A cat's head rising out of a box: round, two ears, and eyes shut (napping) or open.
    private static func drawCat(_ ctx: inout GraphicsContext, in r: CGRect, coat: Color, awake: Bool, line: CGFloat) {
        let w = r.width
        let center = CGPoint(x: r.midX, y: r.minY + w * 0.47)
        let radius = w * 0.29
        var head = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius * 0.9, width: 2 * radius, height: 2 * radius * 0.9))
        for dir in [-1.0, 1.0] {
            var ear = Path()
            ear.move(to: CGPoint(x: center.x + dir * radius * 0.98, y: center.y - radius * 0.05))
            ear.addLine(to: CGPoint(x: center.x + dir * radius * 0.9, y: center.y - radius * 1.35))
            ear.addLine(to: CGPoint(x: center.x + dir * radius * 0.15, y: center.y - radius * 0.7))
            ear.closeSubpath()
            head = head.union(ear)
        }
        ctx.fill(head, with: .color(coat))
        ctx.stroke(head, with: .color(Palette.ink), style: StrokeStyle(lineWidth: line, lineJoin: .round))
        let eyeY = center.y - radius * 0.12
        let eyeInk: Color = coat == coats[3] ? .white : Palette.ink
        for dx in [-0.42, 0.42] {
            let x = center.x + dx * radius
            if awake {
                let eye = CGRect(x: x - w * 0.06, y: eyeY - w * 0.075, width: w * 0.12, height: w * 0.15)
                ctx.fill(Path(ellipseIn: eye), with: .color(eyeInk))
            } else {
                var lid = Path()
                lid.move(to: CGPoint(x: x - w * 0.08, y: eyeY))
                lid.addQuadCurve(to: CGPoint(x: x + w * 0.08, y: eyeY), control: CGPoint(x: x, y: eyeY + w * 0.08))
                ctx.stroke(lid, with: .color(eyeInk), style: StrokeStyle(lineWidth: max(1, w * 0.05), lineCap: .round))
            }
        }
    }

    /// Whether the box in spot `index` has a cat peeking out: about one box in nine, fixed by
    /// where it is and its paint, so a rug always looks the same for the same boxes.
    static func peeks(index: Int, tint: Int) -> Bool {
        tint != BoxFortRules.clutter && (index * 5 + tint * 3) % 9 == 0
    }

    /// Every box on `rug`, its 8 by 8 spots filling `rect`.
    static func drawBoxes(_ ctx: inout GraphicsContext, rug: [Int], rect: CGRect) {
        let cell = rect.width / 8
        for (i, tint) in rug.enumerated() where tint != 0 {
            let spot = CGRect(x: rect.minX + CGFloat(i % 8) * cell, y: rect.minY + CGFloat(i / 8) * cell, width: cell, height: cell)
            drawBox(&ctx, rect: spot, tint: tint, peek: peeks(index: i, tint: tint), coat: i * 3 + tint)
        }
    }

    /// `piece` with its top-left at `origin`, each box `cell` wide.
    static func drawPiece(_ ctx: inout GraphicsContext, piece: BoxFortPiece, origin: CGPoint, cell: CGFloat) {
        for c in piece.cells {
            let spot = CGRect(x: origin.x + CGFloat(c.col) * cell, y: origin.y + CGFloat(c.row) * cell, width: cell, height: cell)
            drawBox(&ctx, rect: spot, tint: piece.tint)
        }
    }
}

/// One piece, drawn at `cell` per box, sized to its boxes. Equatable, so moving it (a drag)
/// moves its layer without drawing it again.
struct BoxFortPieceView: View, Equatable {
    let piece: BoxFortPiece
    let cell: CGFloat

    var body: some View {
        let size = piece.size
        Canvas { ctx, _ in
            BoxFortArt.drawPiece(&ctx, piece: piece, origin: .zero, cell: cell)
        }
        .frame(width: CGFloat(size.col) * cell, height: CGFloat(size.row) * cell)
    }
}

/// The rug and its boxes: one layer, drawn again only when the boxes change.
struct BoxFortRugView: View, Equatable {
    let rug: [Int]
    let cell: CGFloat

    var body: some View {
        let side = cell * 8
        let border = cell * 0.5
        Canvas { ctx, size in
            let rect = CGRect(x: border, y: border, width: side, height: side)
            var under = ctx
            BoxFortArt.drawRug(&under, rect: rect, cell: cell)
            BoxFortArt.drawBoxes(&ctx, rug: rug, rect: rect)
        }
        .frame(width: side + 2 * border, height: side + 2 * border)
        .padding(-border)
    }
}
