import PounceKit
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

    /// Tile faces: a given, yours, a hint's, a clash (the first rules) or a wrong number (lives),
    /// and the solution shown out of lives: soft, not a scolding.
    static let given = Color.white
    static let mine = Palette.sky
    static let hinted = Palette.yellow
    static let clash = Palette.refuse
    static let shown = Palette.violet.mix(with: .white, by: 0.62)
    /// A number on its way to the server: neutral, neither right nor wrong, until the answer lands.
    static let checking = Palette.night.mix(with: .white, by: 0.42)
    /// A life: a bright cat head. A lost one is a dim ghost of it.
    static let life = Palette.magenta.mix(with: Palette.orange, by: 0.25)
    static let lifeLost = Palette.ink.opacity(0.5)
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
    enum Kind: Equatable { case given, mine, hinted, clash, wrong, shown, checking }

    let digit: Int
    let kind: Kind
    let size: CGFloat

    private var face: Color {
        switch kind {
        case .given: NineLivesStyle.given
        case .mine: NineLivesStyle.mine
        case .hinted: NineLivesStyle.hinted
        case .clash, .wrong: NineLivesStyle.clash
        case .shown: NineLivesStyle.shown
        case .checking: NineLivesStyle.checking
        }
    }

    /// Light faces carry an ink digit; bright faces a white digit with an ink drop.
    private var inkDigit: Bool { kind == .given || kind == .hinted || kind == .shown }

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

/// A cat's head: a round face with two pointed ears, as one outline.
struct CatHeadShape: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        let face = Path(ellipseIn: CGRect(x: r.minX + w * 0.04, y: r.minY + h * 0.26, width: w * 0.92, height: h * 0.72))
        var ears = Path()
        for side in [-1.0, 1.0] {
            ears.move(to: CGPoint(x: r.midX + side * w * 0.08, y: r.minY + h * 0.34))
            ears.addLine(to: CGPoint(x: r.midX + side * w * 0.36, y: r.minY + h * 0.03))
            ears.addLine(to: CGPoint(x: r.midX + side * w * 0.46, y: r.minY + h * 0.5))
            ears.closeSubpath()
        }
        return face.union(ears)
    }
}

/// The pink inside of each ear.
private struct InnerEarsShape: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()
        for side in [-1.0, 1.0] {
            p.move(to: CGPoint(x: r.midX + side * w * 0.19, y: r.minY + h * 0.33))
            p.addLine(to: CGPoint(x: r.midX + side * w * 0.345, y: r.minY + h * 0.14))
            p.addLine(to: CGPoint(x: r.midX + side * w * 0.39, y: r.minY + h * 0.36))
            p.closeSubpath()
        }
        return p
    }
}

/// One life: a bright cat head with eyes and a nose, or, once lost, its dim ghost.
struct LifeHead: View {
    let alive: Bool
    let size: CGFloat

    var body: some View {
        let rim = max(2, size * 0.075)
        ZStack {
            CatHeadShape().fill(alive ? NineLivesStyle.life : NineLivesStyle.lifeLost)
            if alive {
                InnerEarsShape().fill(Palette.yellow.mix(with: NineLivesStyle.life, by: 0.35))
            }
            CatHeadShape().stroke(alive ? Palette.ink : Color.white.opacity(0.35), style: StrokeStyle(lineWidth: rim, lineJoin: .round))
            if alive {
                HStack(spacing: size * 0.22) {
                    Capsule().fill(Palette.ink).frame(width: size * 0.12, height: size * 0.19)
                    Capsule().fill(Palette.ink).frame(width: size * 0.12, height: size * 0.19)
                }
                .offset(y: size * 0.11)
                Ellipse().fill(Palette.ink).frame(width: size * 0.12, height: size * 0.08).offset(y: size * 0.29)
            } else {
                // Closed eyes: gone, not grim.
                HStack(spacing: size * 0.2) {
                    Capsule().fill(Color.white.opacity(0.4)).frame(width: size * 0.17, height: size * 0.06)
                    Capsule().fill(Color.white.opacity(0.4)).frame(width: size * 0.17, height: size * 0.06)
                }
                .offset(y: size * 0.14)
            }
        }
        .frame(width: size, height: size)
        // One layer: a ghosted head never shows its rim through its face.
        .compositingGroup()
    }
}

/// Lives left, as three cat heads; a lost one ghosts and shrinks a little.
struct LivesRow: View {
    let left: Int
    let size: CGFloat

    var body: some View {
        HStack(spacing: size * 0.22) {
            ForEach(0..<NineLivesRules.lifeCount, id: \.self) { k in
                LifeHead(alive: k < left, size: size)
                    .scaleEffect(k < left ? 1 : 0.86)
                    .opacity(k < left ? 1 : 0.8)
                    // The one just lost pops off.
                    .pop(trigger: k < left)
            }
        }
        .compositingGroup()
    }
}
