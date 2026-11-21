import SwiftUI

/// Nine Lives' look: a quilt of 3 by 3 cushions, and every digit on a paw-shaped tile. Shared by
/// the play view and the TV's watch view, so it uses SwiftUI and the palette only (no UIKit).
enum NineLivesStyle {
    /// The quilt's two cushion colors, alternating like a checkerboard of boxes.
    static let cushionA = Palette.violet
    static let cushionB = Palette.violet.mix(with: Palette.magenta, by: 0.32)
    /// An empty cell's socket.
    static let socket = Palette.ink.opacity(0.42)
    /// Sockets in the selected cell's row, column and box.
    static let socketLit = Color.white.opacity(0.2)

    /// Tile faces: a given, yours, a hint's, and a clash.
    static let given = Color.white
    static let mine = Palette.sky
    static let hinted = Palette.yellow
    static let clash = Palette.refuse
    /// The ring on the selected cell, and on tiles with the selected digit.
    static let selectRing = Palette.yellow
    static let sameRing = Palette.lime
}

/// A paw: a round-cornered pad with four toe beans across its top. The digit sits on the pad.
struct PawShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        let padTop = r.minY + h * 0.26
        p.addRoundedRect(
            in: CGRect(x: r.minX, y: padTop, width: w, height: r.maxY - padTop),
            cornerSize: CGSize(width: w * 0.3, height: h * 0.3), style: .continuous)
        let toes: [(x: CGFloat, y: CGFloat)] = [(0.15, 0.27), (0.38, 0.14), (0.62, 0.14), (0.85, 0.27)]
        let rx = w * 0.135, ry = h * 0.15
        for toe in toes {
            p.addEllipse(in: CGRect(x: r.minX + w * toe.x - rx, y: r.minY + h * toe.y - ry + ry * 0.9, width: rx * 2, height: ry * 2))
        }
        return p
    }
}

/// One paw tile: an ink rim, a darker lip below, a glossy face and the digit.
struct PawTile: View {
    enum Kind: Equatable { case given, mine, hinted, clash }

    let digit: Int
    let kind: Kind
    let size: CGFloat

    private var face: Color {
        switch kind {
        case .given: NineLivesStyle.given
        case .mine: NineLivesStyle.mine
        case .hinted: NineLivesStyle.hinted
        case .clash: NineLivesStyle.clash
        }
    }

    /// Light faces carry an ink digit; bright faces a white digit with an ink drop.
    private var inkDigit: Bool { kind == .given || kind == .hinted }

    var body: some View {
        let rim = max(1.5, size * 0.05)
        let lip = max(1.5, size * 0.06)
        ZStack {
            PawShape().fill(face.mix(with: Palette.ink, by: 0.45))
                .overlay(PawShape().stroke(Palette.ink, lineWidth: rim * 2))
                .offset(y: lip)
            PawShape().stroke(Palette.ink, lineWidth: rim * 2)
            PawShape().fill(
                LinearGradient(
                    colors: [face.mix(with: .white, by: 0.35), face, face.mix(with: Palette.ink, by: 0.08)],
                    startPoint: .top, endPoint: .bottom))
            Text(verbatim: "\(digit)")
                .font(.system(size: size * 0.52, weight: .black, design: .rounded))
                .foregroundStyle(inkDigit ? Palette.ink : .white)
                .shadow(color: inkDigit ? .clear : Palette.ink, radius: 0, x: size * 0.03, y: size * 0.04)
                .offset(y: size * 0.13)
        }
        .frame(width: size, height: size)
        // One layer: a faded tile never shows its rim through its face.
        .compositingGroup()
    }
}
