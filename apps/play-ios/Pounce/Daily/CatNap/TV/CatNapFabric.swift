import SwiftUI

/// Cat Nap's quilt fabric: a loud color and a pattern for each patch. The pattern and the thick
/// seams carry which patch a cell is in, so the colors never carry it alone. Pounce's own
/// palette and patterns; shared by the phone's play view and the TV's watch view.
enum CatNapFabric {
    /// One patch's cloth: its color, and the tint its pattern is drawn in (white on the dark
    /// colors, ink on the bright ones, so every pattern reads).
    struct Cloth {
        let color: Color
        let tint: Color
        let pattern: Pattern
        /// Spoken with the cell: "violet stripes".
        let name: String
    }

    enum Pattern: CaseIterable {
        case stripes, dots, checks, zigzag, pinstripes, crosshatch, bars, pluses, waves
    }

    private static let light = Color.white.opacity(0.32)
    private static let dark = Palette.ink.opacity(0.2)

    /// Nine patches at most (a 9 by 9 quilt); each one's cloth differs in color and pattern.
    static let cloths: [Cloth] = [
        Cloth(color: Palette.violet, tint: light, pattern: .stripes, name: "violet stripes"),
        Cloth(color: Palette.yellow, tint: dark, pattern: .dots, name: "yellow dots"),
        Cloth(color: Palette.teal, tint: dark, pattern: .checks, name: "teal checks"),
        Cloth(color: Palette.magenta, tint: light, pattern: .zigzag, name: "pink zigzags"),
        Cloth(color: Palette.lime, tint: dark, pattern: .pinstripes, name: "green pinstripes"),
        Cloth(color: Color(hex: 0x3550FF), tint: light, pattern: .crosshatch, name: "blue crosshatch"),
        Cloth(color: Palette.orange, tint: dark, pattern: .bars, name: "orange bars"),
        Cloth(color: Palette.sky, tint: dark, pattern: .pluses, name: "sky pluses"),
        Cloth(color: Color(hex: 0xFF7AD9), tint: dark, pattern: .waves, name: "bubblegum waves"),
    ]

    static func cloth(_ patch: Int) -> Cloth { cloths[patch % cloths.count] }

    /// The pattern's marks over `rect`, sized to a cell of side `unit`, lined up with the quilt so
    /// a patch reads as one piece of cloth.
    static func path(_ pattern: Pattern, in rect: CGRect, unit u: CGFloat) -> (path: Path, stroke: CGFloat?) {
        var p = Path()
        let (x0, y0, x1, y1) = (rect.minX, rect.minY, rect.maxX, rect.maxY)
        switch pattern {
        case .stripes:
            let step = u / 3
            var x = x0 - (y1 - y0)
            while x < x1 {
                p.move(to: CGPoint(x: x, y: y1))
                p.addLine(to: CGPoint(x: x + (y1 - y0), y: y0))
                x += step
            }
            return (p, u / 9)
        case .dots:
            let step = u / 2.5, r = u / 11
            var row = 0
            for y in stride(from: y0 + step / 2, through: y1, by: step) {
                let shift = row % 2 == 0 ? 0 : step / 2
                for x in stride(from: x0 + step / 2 - shift, through: x1 + step, by: step) {
                    p.addEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
                }
                row += 1
            }
            return (p, nil)
        case .checks:
            let s = u / 3
            var i = 0
            for y in stride(from: y0, to: y1, by: s) {
                var j = 0
                for x in stride(from: x0, to: x1, by: s) {
                    if (i + j) % 2 == 0 { p.addRect(CGRect(x: x, y: y, width: s, height: s)) }
                    j += 1
                }
                i += 1
            }
            return (p, nil)
        case .zigzag:
            let step = u / 3, h = u / 10
            for y in stride(from: y0 + step / 2, through: y1, by: step) {
                p.move(to: CGPoint(x: x0, y: y))
                var x = x0, up = true
                while x < x1 {
                    x += step / 2
                    p.addLine(to: CGPoint(x: x, y: y + (up ? -h : h)))
                    up.toggle()
                }
            }
            return (p, u / 16)
        case .pinstripes:
            for y in stride(from: y0 + u / 8, through: y1, by: u / 4) {
                p.move(to: CGPoint(x: x0, y: y))
                p.addLine(to: CGPoint(x: x1, y: y))
            }
            return (p, u / 18)
        case .crosshatch:
            let step = u / 2.5, span = y1 - y0
            var x = x0 - span
            while x < x1 {
                p.move(to: CGPoint(x: x, y: y1))
                p.addLine(to: CGPoint(x: x + span, y: y0))
                p.move(to: CGPoint(x: x, y: y0))
                p.addLine(to: CGPoint(x: x + span, y: y1))
                x += step
            }
            return (p, u / 18)
        case .bars:
            for x in stride(from: x0 + u / 6, through: x1, by: u / 3) {
                p.move(to: CGPoint(x: x, y: y0))
                p.addLine(to: CGPoint(x: x, y: y1))
            }
            return (p, u / 8)
        case .pluses:
            let step = u / 2, arm = u / 10
            for y in stride(from: y0 + step / 2, through: y1, by: step) {
                for x in stride(from: x0 + step / 2, through: x1, by: step) {
                    p.move(to: CGPoint(x: x - arm, y: y))
                    p.addLine(to: CGPoint(x: x + arm, y: y))
                    p.move(to: CGPoint(x: x, y: y - arm))
                    p.addLine(to: CGPoint(x: x, y: y + arm))
                }
            }
            return (p, u / 16)
        case .waves:
            let step = u / 3, h = u / 12
            for y in stride(from: y0 + step / 2, through: y1, by: step) {
                p.move(to: CGPoint(x: x0, y: y))
                var x = x0, up = true
                while x < x1 {
                    p.addQuadCurve(to: CGPoint(x: x + step, y: y), control: CGPoint(x: x + step / 2, y: y + (up ? -h : h) * 2))
                    x += step
                    up.toggle()
                }
            }
            return (p, u / 16)
        }
    }
}
