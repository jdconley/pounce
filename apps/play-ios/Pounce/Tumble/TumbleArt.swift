import PounceKit
import SpriteKit
import SwiftUI
import UIKit

/// Toy Tumble's textures (spec §3), drawn once in code off the main thread (`prewarm`), so the
/// table never draws one in a frame:
/// - a round plush cushion for each of the four toy colours, stitched with its toy's silhouette;
/// - a gray fluffy hairball tuft for junk, drawn as fur wider than its cell so a row reads as one
///   strip of fur with a gap, never as blocks;
/// - a glowing badge for each trick;
/// - the dashed paw-print outline where the toy will land;
/// - the toy box itself, a bright toy chest with a lid rim, sliced so it stretches to any size.
@MainActor
final class TumbleArt {
    static let shared = TumbleArt()

    nonisolated static let cellCanvas = CGSize(width: 64, height: 64)
    nonisolated static let badgeCanvas = CGSize(width: 72, height: 72)
    nonisolated static let boxCanvas = CGSize(width: 120, height: 160)
    /// The box's slice: its rim and walls keep their thickness.
    static let boxSlice = CGRect(x: 0.3, y: 0.25, width: 0.4, height: 0.45)
    nonisolated static let ink = UIColor(Palette.ink)

    private var cushions: [TileSuit: SKTexture] = [:]
    private var badges: [TumbleTrick: SKTexture] = [:]
    private var fur: SKTexture?
    private var paw: SKTexture?
    private var box: SKTexture?
    private var well: SKTexture?
    private var warming: Task<Void, Never>?

    static var scale: CGFloat {
        #if os(tvOS)
        return 2
        #else
        return max(UIScreen.main.scale, 2)
        #endif
    }

    /// Everything, off the main thread. Once a launch; later calls return at once.
    func prewarm() async {
        if warming == nil {
            let scale = Self.scale
            warming = Task {
                let made = await Self.drawAll(scale: scale)
                cushions = made.cushions
                badges = made.badges
                fur = made.fur
                paw = made.paw
                box = made.box
                well = made.well
            }
        }
        await warming?.value
    }

    var ready: Bool { box != nil }

    func cushion(_ suit: TileSuit) -> SKTexture { cushions[suit] ?? Self.fallback }
    func badge(_ trick: TumbleTrick) -> SKTexture { badges[trick] ?? Self.fallback }
    func furTexture() -> SKTexture { fur ?? Self.fallback }
    func pawTexture() -> SKTexture { paw ?? Self.fallback }
    func boxTexture() -> SKTexture { box ?? Self.fallback }
    func wellTexture() -> SKTexture { well ?? Self.fallback }

    private static let fallback = SKTexture()

    struct Made: @unchecked Sendable {
        var cushions: [TileSuit: SKTexture] = [:]
        var badges: [TumbleTrick: SKTexture] = [:]
        var fur: SKTexture?
        var paw: SKTexture?
        var box: SKTexture?
        var well: SKTexture?
    }

    @concurrent
    private static func drawAll(scale: CGFloat) async -> Made {
        var made = Made()
        for suit in TileSuit.allCases {
            made.cushions[suit] = SKTexture(image: render(cellCanvas, scale: scale) { drawCushion(suit, in: $0) })
        }
        for trick in TumbleTrick.allCases {
            made.badges[trick] = SKTexture(image: render(badgeCanvas, scale: scale) { drawBadge(trick, in: $0) })
        }
        made.fur = SKTexture(image: render(CGSize(width: 84, height: 72), scale: scale) { drawFur(in: $0) })
        made.paw = SKTexture(image: render(cellCanvas, scale: scale) { drawPawOutline(in: $0) })
        made.box = SKTexture(image: render(boxCanvas, scale: scale) { drawBox(in: $0) })
        made.well = SKTexture(image: render(CGSize(width: 48, height: 48), scale: scale) { drawWell(in: $0) })
        let all = Array(made.cushions.values) + Array(made.badges.values) + [made.fur, made.paw, made.box, made.well].compactMap { $0 }
        await SKTexture.preload(all)
        return made
    }

    // MARK: drawing (safe off the main thread)

    nonisolated static func render(_ size: CGSize, scale: CGFloat, _ draw: (CGRect) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in draw(CGRect(origin: .zero, size: size)) }
    }

    /// A plush cushion: puffy rounded body with a soft lit top, a dashed stitch around the edge,
    /// and its toy's silhouette stitched in the middle in the darker tone.
    nonisolated static func drawCushion(_ suit: TileSuit, in rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let w = rect.width
        let body = rect.insetBy(dx: w * 0.03, dy: w * 0.03)
        let radius = w * 0.34
        ink.setFill()
        UIBezierPath(roundedRect: body, cornerRadius: radius).fill()
        let plush = body.insetBy(dx: w * 0.05, dy: w * 0.05)
        ctx.saveGState()
        UIBezierPath(roundedRect: plush, cornerRadius: radius * 0.85).addClip()
        let colors = [TilePieceFactory.light(suit).cgColor, TilePieceFactory.color(suit).cgColor, TilePieceFactory.shade(suit).cgColor] as CFArray
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.55, 1]) {
            ctx.drawRadialGradient(
                g, startCenter: CGPoint(x: plush.midX - w * 0.1, y: plush.minY + w * 0.22), startRadius: 0,
                endCenter: CGPoint(x: plush.midX, y: plush.midY), endRadius: w * 0.62, options: [.drawsAfterEndLocation])
        }
        // A shine on the puff.
        UIColor.white.withAlphaComponent(0.35).setFill()
        UIBezierPath(ovalIn: CGRect(x: plush.minX + w * 0.14, y: plush.minY + w * 0.08, width: w * 0.36, height: w * 0.16)).fill()
        ctx.restoreGState()
        // The stitch.
        let stitch = UIBezierPath(roundedRect: plush.insetBy(dx: w * 0.07, dy: w * 0.07), cornerRadius: radius * 0.6)
        stitch.lineWidth = max(w * 0.035, 1.2)
        stitch.setLineDash([w * 0.07, w * 0.055], count: 2, phase: 0)
        stitch.lineCapStyle = .round
        UIColor.white.withAlphaComponent(0.7).setStroke()
        stitch.stroke()
        // The silhouette, in the darker tone.
        if let glyph = UIImage(named: ArtName.Tiles.glyph(suit))?.withRenderingMode(.alwaysTemplate) {
            let side = w * 0.5
            let r = CGRect(x: plush.midX - side / 2, y: plush.midY - side / 2 + w * 0.02, width: side, height: side)
            ctx.saveGState()
            ctx.setAlpha(0.55)
            TilePieceFactory.shade(suit).setFill()
            glyph.withTintColor(TilePieceFactory.shade(suit)).draw(in: r)
            ctx.restoreGState()
        }
    }

    /// A gray fluffy tuft, wider than its cell: side by side they make a strip of fur.
    nonisolated static func drawFur(in rect: CGRect) {
        let w = rect.width
        let h = rect.height
        let dark = UIColor(Color(hex: 0x6E6A80))
        let mid = UIColor(Color(hex: 0x9C98AE))
        let light = UIColor(Color(hex: 0xD6D3E2))
        // Fluff: overlapping puffs, darker underneath.
        let puffs: [(CGFloat, CGFloat, CGFloat)] = [
            (0.18, 0.5, 0.26), (0.36, 0.34, 0.27), (0.52, 0.56, 0.28), (0.68, 0.36, 0.26), (0.84, 0.52, 0.24), (0.5, 0.42, 0.3),
        ]
        ink.withAlphaComponent(0.85).setFill()
        for (x, y, r) in puffs {
            UIBezierPath(ovalIn: CGRect(x: w * x - h * r - 2, y: h * y - h * r - 2, width: h * r * 2 + 4, height: h * r * 2 + 4)).fill()
        }
        dark.setFill()
        for (x, y, r) in puffs { UIBezierPath(ovalIn: CGRect(x: w * x - h * r, y: h * y - h * r, width: h * r * 2, height: h * r * 2)).fill() }
        mid.setFill()
        for (x, y, r) in puffs {
            UIBezierPath(ovalIn: CGRect(x: w * x - h * r * 0.8, y: h * y - h * r * 0.95, width: h * r * 1.6, height: h * r * 1.5)).fill()
        }
        // Fur strands.
        light.setStroke()
        for i in 0..<9 {
            let x = w * (0.12 + CGFloat(i) * 0.095)
            let p = UIBezierPath()
            p.move(to: CGPoint(x: x, y: h * 0.62))
            p.addQuadCurve(to: CGPoint(x: x + w * 0.04, y: h * 0.28), controlPoint: CGPoint(x: x - w * 0.04, y: h * 0.45))
            p.lineWidth = max(h * 0.035, 1)
            p.lineCapStyle = .round
            p.stroke()
        }
    }

    /// The dashed paw-print outline of a landing cell.
    nonisolated static func drawPawOutline(in rect: CGRect) {
        let w = rect.width
        let outline = UIBezierPath(roundedRect: rect.insetBy(dx: w * 0.1, dy: w * 0.1), cornerRadius: w * 0.3)
        outline.lineWidth = max(w * 0.06, 1.5)
        outline.setLineDash([w * 0.1, w * 0.08], count: 2, phase: 0)
        UIColor.white.withAlphaComponent(0.8).setStroke()
        outline.stroke()
        UIColor.white.withAlphaComponent(0.45).setFill()
        // Pad and four toes.
        UIBezierPath(ovalIn: CGRect(x: w * 0.36, y: w * 0.48, width: w * 0.28, height: w * 0.22)).fill()
        for (x, y) in [(0.27, 0.36), (0.4, 0.28), (0.56, 0.28), (0.69, 0.36)] as [(CGFloat, CGFloat)] {
            UIBezierPath(ovalIn: CGRect(x: w * x - w * 0.055, y: w * y - w * 0.055, width: w * 0.11, height: w * 0.11)).fill()
        }
    }

    /// The toy chest: thick bright walls with a rim, an ink outline and a darker inside.
    nonisolated static func drawBox(in rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let w = rect.width
        let wall = w * 0.1
        ink.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: w * 0.14).fill()
        let outer = rect.insetBy(dx: 4, dy: 4)
        ctx.saveGState()
        UIBezierPath(roundedRect: outer, cornerRadius: w * 0.12).addClip()
        let colors = [UIColor(Color(hex: 0xFF5FB8)).cgColor, UIColor(Palette.magenta).cgColor, UIColor(Color(hex: 0xB0006A)).cgColor] as CFArray
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: outer.minY), end: CGPoint(x: 0, y: outer.maxY), options: [])
        }
        // Painted dots on the walls.
        UIColor(Palette.yellow).setFill()
        for (x, y) in [(0.05, 0.3), (0.05, 0.7), (0.95, 0.5), (0.5, 0.96)] as [(CGFloat, CGFloat)] {
            UIBezierPath(ovalIn: CGRect(x: rect.width * x - 3, y: rect.height * y - 3, width: 6, height: 6)).fill()
        }
        ctx.restoreGState()
        // The rim along the top: a yellow lip.
        let rim = CGRect(x: outer.minX - 2, y: outer.minY, width: outer.width + 4, height: wall * 0.9)
        ink.setFill()
        UIBezierPath(roundedRect: rim.insetBy(dx: -2, dy: -2), cornerRadius: wall * 0.5).fill()
        UIColor(Palette.yellow).setFill()
        UIBezierPath(roundedRect: rim, cornerRadius: wall * 0.45).fill()
        UIColor.white.withAlphaComponent(0.4).setFill()
        UIBezierPath(roundedRect: CGRect(x: rim.minX + 6, y: rim.minY + 2, width: rim.width - 12, height: rim.height * 0.3), cornerRadius: 2).fill()
        // The inside.
        let inside = CGRect(x: outer.minX + wall, y: rim.maxY, width: outer.width - wall * 2, height: outer.maxY - wall - rim.maxY)
        ink.setFill()
        UIBezierPath(roundedRect: inside.insetBy(dx: -2, dy: -2), cornerRadius: w * 0.05).fill()
    }

    /// The box's floor and back wall behind the toys: a deep violet with faint quilting.
    nonisolated static func drawWell(in rect: CGRect) {
        UIColor(Color(hex: 0x3A1580)).setFill()
        UIBezierPath(rect: rect).fill()
        UIColor(Color(hex: 0x4A1E9C)).setFill()
        UIBezierPath(ovalIn: rect.insetBy(dx: rect.width * 0.3, dy: rect.width * 0.3)).fill()
    }

    // MARK: trick badges

    nonisolated static func badgeColor(_ trick: TumbleTrick) -> UIColor {
        switch trick {
        case .hairball: UIColor(Color(hex: 0x8C88A0))
        case .swipe: UIColor(Palette.orange)
        case .catnip: UIColor(Palette.lime)
        case .scoop: UIColor(Palette.sky)
        case .settle: UIColor(Palette.teal)
        case .nap: UIColor(Palette.violet)
        case .swap: UIColor(Palette.magenta)
        case .bath: UIColor(Color(hex: 0x58D6FF))
        }
    }

    /// A badge: a glowing star-ish disc in the trick's colour with its mark.
    nonisolated static func drawBadge(_ trick: TumbleTrick, in rect: CGRect) {
        let w = rect.width
        UIColor(Palette.yellow).withAlphaComponent(0.6).setFill()
        UIBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
        let disc = rect.insetBy(dx: w * 0.1, dy: w * 0.1)
        ink.setFill()
        UIBezierPath(ovalIn: disc).fill()
        badgeColor(trick).setFill()
        UIBezierPath(ovalIn: disc.insetBy(dx: w * 0.06, dy: w * 0.06)).fill()
        UIColor.white.withAlphaComponent(0.3).setFill()
        UIBezierPath(ovalIn: CGRect(x: disc.minX + w * 0.18, y: disc.minY + w * 0.1, width: disc.width * 0.5, height: disc.height * 0.22)).fill()
        drawMark(trick, in: disc.insetBy(dx: w * 0.2, dy: w * 0.2))
    }

    nonisolated static func drawMark(_ trick: TumbleTrick, in r: CGRect) {
        let w = r.width
        let white = UIColor.white
        white.setFill()
        white.setStroke()
        switch trick {
        case .hairball:
            UIColor(Color(hex: 0xD6D3E2)).setFill()
            UIBezierPath(ovalIn: r.insetBy(dx: w * 0.08, dy: w * 0.08)).fill()
            ink.setStroke()
            for i in 0..<3 {
                let p = UIBezierPath(arcCenter: CGPoint(x: r.midX, y: r.midY), radius: w * (0.15 + CGFloat(i) * 0.1),
                                     startAngle: CGFloat(i), endAngle: CGFloat(i) + 2.4, clockwise: true)
                p.lineWidth = max(w * 0.07, 1)
                p.stroke()
            }
        case .swipe:
            // A paw with three claw streaks.
            UIBezierPath(ovalIn: CGRect(x: r.minX + w * 0.1, y: r.midY, width: w * 0.42, height: w * 0.34)).fill()
            for i in 0..<3 {
                let p = UIBezierPath()
                let y = r.minY + w * (0.18 + CGFloat(i) * 0.16)
                p.move(to: CGPoint(x: r.minX + w * 0.45, y: y + w * 0.12))
                p.addLine(to: CGPoint(x: r.maxX - w * 0.05, y: y))
                p.lineWidth = max(w * 0.09, 1.2)
                p.lineCapStyle = .round
                p.stroke()
            }
        case .catnip:
            let leaf = UIBezierPath()
            leaf.move(to: CGPoint(x: r.minX + w * 0.1, y: r.maxY - w * 0.1))
            leaf.addQuadCurve(to: CGPoint(x: r.maxX - w * 0.08, y: r.minY + w * 0.08), controlPoint: CGPoint(x: r.minX + w * 0.05, y: r.minY))
            leaf.addQuadCurve(to: CGPoint(x: r.minX + w * 0.1, y: r.maxY - w * 0.1), controlPoint: CGPoint(x: r.maxX, y: r.maxY))
            UIColor(Color(hex: 0x1E7A1E)).setFill()
            leaf.fill()
            let vein = UIBezierPath()
            vein.move(to: CGPoint(x: r.minX + w * 0.14, y: r.maxY - w * 0.14))
            vein.addLine(to: CGPoint(x: r.maxX - w * 0.15, y: r.minY + w * 0.15))
            vein.lineWidth = max(w * 0.06, 1)
            vein.stroke()
        case .scoop:
            let scoop = UIBezierPath()
            scoop.move(to: CGPoint(x: r.minX, y: r.midY))
            scoop.addLine(to: CGPoint(x: r.maxX, y: r.midY))
            scoop.addQuadCurve(to: CGPoint(x: r.minX, y: r.midY), controlPoint: CGPoint(x: r.midX, y: r.maxY + w * 0.15))
            scoop.fill()
            UIBezierPath(roundedRect: CGRect(x: r.midX - w * 0.07, y: r.minY, width: w * 0.14, height: w * 0.5), cornerRadius: w * 0.07).fill()
        case .settle:
            for i in 0..<2 {
                let y = r.minY + w * (0.1 + CGFloat(i) * 0.38)
                let p = UIBezierPath()
                p.move(to: CGPoint(x: r.minX + w * 0.1, y: y))
                p.addLine(to: CGPoint(x: r.midX, y: y + w * 0.32))
                p.addLine(to: CGPoint(x: r.maxX - w * 0.1, y: y))
                p.lineWidth = max(w * 0.12, 1.5)
                p.lineCapStyle = .round
                p.lineJoinStyle = .round
                p.stroke()
            }
        case .nap:
            // Three z's, small to big.
            for (i, s) in [0.26, 0.34, 0.44].enumerated() {
                let side = w * CGFloat(s)
                let x = r.minX + w * CGFloat(i) * 0.26
                let y = r.maxY - side - w * CGFloat(i) * 0.24
                let z = UIBezierPath()
                z.move(to: CGPoint(x: x, y: y))
                z.addLine(to: CGPoint(x: x + side, y: y))
                z.addLine(to: CGPoint(x: x, y: y + side))
                z.addLine(to: CGPoint(x: x + side, y: y + side))
                z.lineWidth = max(w * 0.08, 1)
                z.lineJoinStyle = .round
                z.stroke()
            }
        case .swap:
            for flip in [false, true] {
                let p = UIBezierPath()
                let y = flip ? r.maxY - w * 0.28 : r.minY + w * 0.28
                let from = flip ? r.maxX - w * 0.05 : r.minX + w * 0.05
                let to = flip ? r.minX + w * 0.1 : r.maxX - w * 0.1
                p.move(to: CGPoint(x: from, y: y))
                p.addLine(to: CGPoint(x: to, y: y))
                p.move(to: CGPoint(x: to + (flip ? w * 0.18 : -w * 0.18), y: y - w * 0.16))
                p.addLine(to: CGPoint(x: to, y: y))
                p.addLine(to: CGPoint(x: to + (flip ? w * 0.18 : -w * 0.18), y: y + w * 0.16))
                p.lineWidth = max(w * 0.1, 1.4)
                p.lineCapStyle = .round
                p.lineJoinStyle = .round
                p.stroke()
            }
        case .bath:
            for (x, y, s) in [(0.3, 0.6, 0.36), (0.66, 0.42, 0.3), (0.52, 0.16, 0.2)] as [(CGFloat, CGFloat, CGFloat)] {
                let b = UIBezierPath(ovalIn: CGRect(x: r.minX + w * x - w * s / 2, y: r.minY + w * y - w * s / 2, width: w * s, height: w * s))
                b.lineWidth = max(w * 0.07, 1)
                b.stroke()
                UIColor.white.withAlphaComponent(0.5).setFill()
                b.fill()
            }
        }
    }
}

/// Toy Tumble's House Cat levels as two pills, "Cats: Easy" and "Cats: Quick" (the lobby's).
struct TumbleCatsPills: View {
    @Binding var cats: TumbleCats
    var enabled = true
    var onPick: (TumbleCats) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(TumbleCats.allCases, id: \.self) { option in
                let on = option == cats
                Button {
                    guard enabled, !on else { return }
                    Haptics.shared.tick()
                    withAnimation(.spring(duration: 0.3).paced) { cats = option }
                    onPick(option)
                } label: {
                    Text(TumbleWords.catsLevel(option))
                        .font(.system(.headline, design: .rounded, weight: .black))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity)
                        .background(
                            Capsule().fill(on ? Palette.lime.mix(with: Palette.ink, by: 0.15) : Palette.ink.opacity(0.55))
                                .overlay(Capsule().strokeBorder(on ? Palette.ink : Palette.lime, lineWidth: 3))
                                .shadow(color: Palette.ink.opacity(on ? 0.6 : 0), radius: 0, x: 0, y: 3))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .allowsHitTesting(enabled)
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("tumble.cats.\(option.rawValue)")
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tumble.cats")
    }
}

/// Toy Tumble's words (spec §5.8): the trick names and the few short labels.
enum TumbleWords {
    static func trick(_ t: TumbleTrick) -> String {
        switch t {
        case .hairball: String(localized: "Hairball", comment: "Toy Tumble trick: adds a junk row")
        case .swipe: String(localized: "Paw Swipe", comment: "Toy Tumble trick: shoves rows sideways")
        case .catnip: String(localized: "Catnip", comment: "Toy Tumble trick: toys fall faster")
        case .scoop: String(localized: "Scoop", comment: "Toy Tumble trick: clears the bottom 2 rows")
        case .settle: String(localized: "Settle", comment: "Toy Tumble trick: everything falls to fill gaps")
        case .nap: String(localized: "Nap", comment: "Toy Tumble trick: nothing reaches the box for 10 seconds")
        case .swap: String(localized: "Swap", comment: "Toy Tumble trick: trade boxes")
        case .bath: String(localized: "Bath", comment: "Toy Tumble trick: wipes the box empty")
        }
    }

    static func round(_ r: Int) -> String { String(localized: "Round \(r)", comment: "Toy Tumble: the round number") }
    static var out: String { String(localized: "Out", comment: "Toy Tumble: a box that tipped over") }
    static var reconnecting: String { String(localized: "Reconnecting", comment: "Toy Tumble: a player's phone dropped") }
    static var youWin: String { String(localized: "You win the round", comment: "Toy Tumble: this player won the round") }
    static func waiting(for name: String) -> String { String(localized: "Waiting for \(name)", comment: "Toy Tumble: the next round waits for a player") }
    static func waiting(count: Int) -> String { String(localized: "Waiting for \(count)", comment: "Toy Tumble: the next round waits for several players") }
    static func playWithout(_ name: String) -> String { String(localized: "Play without \(name)", comment: "Toy Tumble: the host starts the round without a missing player") }
    static func catsLevel(_ c: TumbleCats) -> String {
        switch c {
        case .easy: String(localized: "Cats: Easy", comment: "Toy Tumble lobby: House Cats play slowly")
        case .quick: String(localized: "Cats: Quick", comment: "Toy Tumble lobby: House Cats play fast")
        }
    }
}
