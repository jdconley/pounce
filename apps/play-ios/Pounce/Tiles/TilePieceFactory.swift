import PounceKit
import SpriteKit
import SwiftUI
import UIKit

/// How a toy token is drawn. Two designs were tried side by side at real size (30 pt on the rug,
/// 48 pt in the stash); `token` is the one the game ships with. `flat` stays for comparison
/// (DEBUG `-piece-style flat`).
enum TilePieceStyle: String {
    /// A glossy token in its toy's colour: the numeral on top, the toy's glossy glyph under it,
    /// the toy's texture band along the bottom edge.
    case token
    /// Two-tone: the numeral on the toy's colour, a flat white silhouette on a darker foot.
    case flat

    static let current: TilePieceStyle = {
        #if DEBUG
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "-piece-style"), args.indices.contains(i + 1), let style = TilePieceStyle(rawValue: args[i + 1]) {
            return style
        }
        #endif
        return .token
    }()
}

/// Draws each toy token once into a texture, so a piece is a single sprite at runtime (tile game
/// spec §3.3). Never a pale tile with coloured ink: a saturated body in the toy's colour, a white
/// numeral in the app's ink outline, and the toy three ways (its glyph, its texture band and its
/// colour), so colour is never the only thing that tells two toys apart.
///
/// Two sizes are drawn: `large` for the stash and the loupe, and `small` for the rug, where the
/// numeral takes most of the token and the band is simpler. Also draws the token's back, the
/// plates and badges that show a set's state, and the action strip's buttons.
@MainActor
final class TilePieceFactory {
    static let shared = TilePieceFactory()

    enum Size: Hashable {
        case large, small

        /// The point size a face is drawn at; sprites scale it to the layout's piece size.
        var canvas: CGSize {
            switch self {
            case .large: CGSize(width: 60, height: 72)
            case .small: CGSize(width: 36, height: 43)
            }
        }
    }

    private struct FaceKey: Hashable {
        let tile: TileID
        let size: Size
        /// What a Yarn stands for where it sits (nil on a rack, and for number pieces).
        let ghostValue: Int?
        let ghostSuit: TileSuit?
        let style: TilePieceStyle
    }

    private var faces: [FaceKey: SKTexture] = [:]
    private var misc: [String: SKTexture] = [:]
    var style = TilePieceStyle.current

    // MARK: colours

    static func color(_ suit: TileSuit) -> UIColor {
        switch suit {
        case .fish: UIColor(Palette.teal)
        case .mouse: UIColor(Palette.violet)
        case .feather: UIColor(Palette.orange)
        case .bell: UIColor(Color(hex: 0xFFD21F))
        }
    }

    /// The darker tone of a toy's colour: the token's side, its band and the flat style's foot.
    static func shade(_ suit: TileSuit) -> UIColor {
        switch suit {
        case .fish: UIColor(Color(hex: 0x008F8A))
        case .mouse: UIColor(Color(hex: 0x4E13C4))
        case .feather: UIColor(Color(hex: 0xC85A00))
        case .bell: UIColor(Color(hex: 0xD99A00))
        }
    }

    /// The lighter tone at the top of the token's face.
    static func light(_ suit: TileSuit) -> UIColor {
        switch suit {
        case .fish: UIColor(Color(hex: 0x4FF2E4))
        case .mouse: UIColor(Color(hex: 0x9D63FF))
        case .feather: UIColor(Color(hex: 0xFFAE3D))
        case .bell: UIColor(Color(hex: 0xFFE66B))
        }
    }

    /// A Yarn's ghost numeral: the toy's colour, dark enough to read on the white token (3.5:1 or more).
    static func ghostColor(_ suit: TileSuit) -> UIColor {
        switch suit {
        case .fish: UIColor(Color(hex: 0x00807A))
        case .mouse: UIColor(Color(hex: 0x5A1FD6))
        case .feather: UIColor(Color(hex: 0xC25400))
        case .bell: UIColor(Color(hex: 0xA87400))
        }
    }

    static let ink = UIColor(Palette.ink)
    static let yarn = UIColor(Palette.magenta)

    // MARK: faces

    /// A piece's face. `standing` is what a Yarn stands for in the set it sits in: its ghost.
    func face(_ tile: TileID, size: Size, standing: TileStanding? = nil) -> SKTexture {
        let isYarn = Tile.isYarn(tile)
        // The two copies of a piece look identical, so they share a texture.
        let canonical = isYarn ? Tile.yarnIDs[0] : (Tile.value(tile).flatMap { v in Tile.suit(tile).map { Tile.id(v, $0) } } ?? tile)
        let key = FaceKey(
            tile: canonical, size: size, ghostValue: isYarn ? standing?.value : nil,
            ghostSuit: isYarn ? standing?.suit : nil, style: style)
        if let cached = faces[key] { return cached }
        let image = Self.render(size.canvas) { rect in
            Self.drawFace(key, in: rect)
        }
        let texture = SKTexture(image: image)
        faces[key] = texture
        return texture
    }

    /// A face as an image, for SwiftUI (the game over card, previews).
    func image(_ tile: TileID, size: Size = .large) -> UIImage {
        UIImage(cgImage: face(tile, size: size).cgImage(), scale: UIScreen.main.scale, orientation: .up)
    }

    /// The back of a token: violet with the paw, like Cat Tower's card back. Other seats' racks,
    /// a piece on its way out of the toy box, the pass curtain.
    func back(size: Size = .small) -> SKTexture {
        let key = "back|\(size)"
        if let cached = misc[key] { return cached }
        let image = Self.render(size.canvas) { rect in
            let face = Self.drawBody(in: rect, top: UIColor(Color(hex: 0x9D63FF)), base: UIColor(Palette.violet), side: UIColor(Color(hex: 0x4E13C4)))
            let side = face.width * 0.62
            UIImage(named: ArtName.iconPawMenu)?.draw(
                in: CGRect(x: face.midX - side / 2, y: face.midY - side / 2, width: side, height: side), blendMode: .normal, alpha: 0.9)
        }
        let texture = SKTexture(image: image)
        misc[key] = texture
        return texture
    }

    private static func render(_ size: CGSize, _ draw: (CGRect) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = max(UIScreen.main.scale, 2)
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(CGRect(origin: .zero, size: size))
        }
    }

    /// The token's body: an ink outline, a darker side showing along the bottom (so the piece
    /// has thickness), and the face on top, lit from above. Returns the face's rect.
    @discardableResult
    private static func drawBody(in rect: CGRect, top: UIColor, base: UIColor, side: UIColor) -> CGRect {
        let w = rect.width
        let line = max(w * 0.055, 1.6)
        let radius = w * 0.25
        ink.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: radius).fill()
        let inner = rect.insetBy(dx: line, dy: line)
        side.setFill()
        UIBezierPath(roundedRect: inner, cornerRadius: radius - line).fill()
        let lip = w * 0.085
        let face = CGRect(x: inner.minX, y: inner.minY, width: inner.width, height: inner.height - lip)
        let path = UIBezierPath(roundedRect: face, cornerRadius: radius - line)
        guard let ctx = UIGraphicsGetCurrentContext() else { return face }
        ctx.saveGState()
        path.addClip()
        let colors = [top.cgColor, base.cgColor, base.cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.55, 1]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: face.minY), end: CGPoint(x: 0, y: face.maxY), options: [])
        }
        // The gloss: a soft band of light under the top edge.
        UIColor.white.withAlphaComponent(0.3).setFill()
        UIBezierPath(
            roundedRect: CGRect(x: face.minX + w * 0.1, y: face.minY + w * 0.045, width: face.width - w * 0.2, height: w * 0.1),
            cornerRadius: w * 0.05
        ).fill()
        ctx.restoreGState()
        return face
    }

    private static func drawFace(_ key: FaceKey, in rect: CGRect) {
        guard case .number(let value, let suit)? = Tile.decode(key.tile) else {
            return drawYarn(key, in: rect)
        }
        let w = rect.width
        let small = key.size == .small
        let face = drawBody(in: rect, top: light(suit), base: color(suit), side: shade(suit))
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let radius = w * 0.25 - max(w * 0.055, 1.6)
        let text = String(value)

        switch key.style {
        case .token:
            // The toy's texture band along the bottom edge of the face.
            let bandH = face.height * (small ? 0.13 : 0.14)
            let band = CGRect(x: face.minX, y: face.maxY - bandH, width: face.width, height: bandH)
            ctx.saveGState()
            UIBezierPath(roundedRect: face, cornerRadius: radius).addClip()
            drawBand(suit, in: band, small: small)
            ctx.restoreGState()
            // The numeral: top centre, as large as the token allows.
            let digits = CGFloat(text.count)
            let fontSize = w * (digits > 1 ? (small ? 0.56 : 0.5) : (small ? 0.64 : 0.56))
            let outline = max(w * (small ? 0.05 : 0.045), 1.4)
            let numeralMid = face.minY + (face.height - bandH) * (small ? 0.31 : 0.29)
            drawNumeral(text, centeredAt: CGPoint(x: face.midX, y: numeralMid), size: fontSize, outline: outline, kern: digits > 1 ? -fontSize * 0.07 : 0)
            // The toy under it.
            let glyphSide = w * (small ? 0.42 : 0.42)
            let glyphMid = face.minY + (face.height - bandH) * (small ? 0.79 : 0.77)
            UIImage(named: ArtName.Tiles.glyph(suit))?.draw(
                in: CGRect(x: face.midX - glyphSide / 2, y: glyphMid - glyphSide / 2, width: glyphSide, height: glyphSide))
        case .flat:
            // A darker foot with the toy's silhouette in flat white; the numeral above it.
            let footH = face.height * 0.42
            let foot = CGRect(x: face.minX, y: face.maxY - footH, width: face.width, height: footH)
            ctx.saveGState()
            UIBezierPath(roundedRect: face, cornerRadius: radius).addClip()
            shade(suit).setFill()
            UIRectFill(foot)
            ctx.restoreGState()
            let digits = CGFloat(text.count)
            let fontSize = w * (digits > 1 ? 0.52 : 0.6)
            let outline = max(w * 0.05, 1.4)
            drawNumeral(
                text, centeredAt: CGPoint(x: face.midX, y: face.minY + (face.height - footH) * 0.52), size: fontSize,
                outline: outline, kern: digits > 1 ? -fontSize * 0.07 : 0)
            let side = min(foot.height * 0.82, w * 0.5)
            UIColor.white.setFill()
            silhouette(suit, in: CGRect(x: foot.midX - side / 2, y: foot.midY - side / 2, width: side, height: side)).fill()
        }
    }

    /// Yarn: the magenta yarn ball from Cat Tower on a white token inside a magenta rim, so it
    /// never passes for a toy. In a set, a small ghost of the piece it stands for rides on top.
    private static func drawYarn(_ key: FaceKey, in rect: CGRect) {
        let w = rect.width
        let small = key.size == .small
        let face = drawBody(in: rect, top: .white, base: .white, side: UIColor(Color(hex: 0xC2187A)))
        let line = max(w * 0.055, 1.6)
        let rim = UIBezierPath(roundedRect: face.insetBy(dx: line * 0.75, dy: line * 0.75), cornerRadius: w * 0.25 - line * 1.75)
        rim.lineWidth = line * 1.5
        yarn.setStroke()
        rim.stroke()
        let ghost = key.ghostValue
        let ballSide = w * (ghost == nil ? 0.74 : (small ? 0.56 : 0.6))
        let ballMid = CGPoint(x: face.midX, y: ghost == nil ? face.midY : face.maxY - ballSide / 2 - w * 0.07)
        UIImage(named: ArtName.cardYarn)?.draw(
            in: CGRect(x: ballMid.x - ballSide / 2, y: ballMid.y - ballSide / 2, width: ballSide, height: ballSide))
        guard let ghost else { return }
        // The ghost: the number it stands for, in that toy's colour when the set says which,
        // lighter than a real numeral and with no ink outline, so it reads as a stand-in.
        let text = String(ghost)
        let fontSize = w * (text.count > 1 ? (small ? 0.46 : 0.4) : (small ? 0.5 : 0.44))
        let tint = key.ghostSuit.map(ghostColor) ?? UIColor(Color(hex: 0xC2187A))
        let font = numeralFont(size: fontSize)
        var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: tint]
        if text.count > 1 { attrs[.kern] = -fontSize * 0.07 }
        let size = (text as NSString).size(withAttributes: attrs)
        let glyphSide: CGFloat = small || key.ghostSuit == nil ? 0 : w * 0.24
        let total = size.width + (glyphSide > 0 ? glyphSide + 1 : 0)
        let top = face.minY + w * 0.1
        (text as NSString).draw(at: CGPoint(x: face.midX - total / 2, y: top - (font.ascender - font.capHeight)), withAttributes: attrs)
        if glyphSide > 0, let suit = key.ghostSuit {
            tint.setFill()
            silhouette(suit, in: CGRect(x: face.midX - total / 2 + size.width + 1, y: top + font.capHeight / 2 - glyphSide / 2, width: glyphSide, height: glyphSide)).fill()
        }
    }

    /// Each toy's texture, in its darker tone: scallop scales, dots, diagonal stripes, bands.
    private static func drawBand(_ suit: TileSuit, in band: CGRect, small: Bool) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.saveGState()
        ctx.clip(to: band)
        shade(suit).withAlphaComponent(0.55).setFill()
        UIRectFill(band)
        let mark = shade(suit)
        mark.setFill()
        mark.setStroke()
        let h = band.height
        switch suit {
        case .fish:
            // Scallops: a row of half discs standing on the bottom edge.
            let r = h * 0.62
            var x = band.minX
            while x < band.maxX + r {
                UIBezierPath(ovalIn: CGRect(x: x - r, y: band.maxY - r, width: 2 * r, height: 2 * r)).fill()
                x += 2 * r + h * 0.14
            }
        case .mouse:
            let r = h * 0.26
            var x = band.minX + r * 1.6
            while x < band.maxX {
                UIBezierPath(ovalIn: CGRect(x: x - r, y: band.midY - r, width: 2 * r, height: 2 * r)).fill()
                x += r * 3.4
            }
        case .feather:
            let path = UIBezierPath()
            let step = h * 0.9
            var x = band.minX - h
            while x < band.maxX + h {
                path.move(to: CGPoint(x: x, y: band.maxY))
                path.addLine(to: CGPoint(x: x + h, y: band.minY))
                x += step
            }
            path.lineWidth = h * 0.36
            path.stroke()
        case .bell:
            let path = UIBezierPath()
            for k in [0.3, 0.76] {
                path.move(to: CGPoint(x: band.minX, y: band.minY + h * k))
                path.addLine(to: CGPoint(x: band.maxX, y: band.minY + h * k))
            }
            path.lineWidth = h * 0.22
            path.stroke()
        }
        ctx.restoreGState()
    }

    /// A toy as a flat shape, for the flat style, a Yarn's ghost and the "why not" badges.
    static func silhouette(_ suit: TileSuit, in r: CGRect) -> UIBezierPath {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y) }
        let path = UIBezierPath()
        switch suit {
        case .fish:
            // A plump body with the tail to the right.
            path.append(UIBezierPath(ovalIn: CGRect(x: r.minX, y: r.minY + r.height * 0.2, width: r.width * 0.72, height: r.height * 0.6)))
            path.move(to: p(0.6, 0.5))
            path.addLine(to: p(1, 0.16))
            path.addQuadCurve(to: p(1, 0.84), controlPoint: p(0.82, 0.5))
            path.close()
        case .mouse:
            // A round body, one big ear and a tail curling up.
            path.append(UIBezierPath(ovalIn: CGRect(x: r.minX, y: r.minY + r.height * 0.4, width: r.width * 0.74, height: r.height * 0.52)))
            path.append(UIBezierPath(ovalIn: CGRect(x: r.minX + r.width * 0.24, y: r.minY + r.height * 0.12, width: r.width * 0.4, height: r.height * 0.4)))
            let tail = UIBezierPath()
            tail.move(to: p(0.68, 0.78))
            tail.addCurve(to: p(0.9, 0.3), controlPoint1: p(1.02, 0.86), controlPoint2: p(1.04, 0.42))
            path.append(UIBezierPath(cgPath: tail.cgPath.copy(strokingWithWidth: r.width * 0.12, lineCap: .round, lineJoin: .round, miterLimit: 1)))
        case .feather:
            // One curved feather, quill at the bottom left.
            path.move(to: p(0.08, 0.96))
            path.addCurve(to: p(0.92, 0.06), controlPoint1: p(0.06, 0.4), controlPoint2: p(0.5, 0.04))
            path.addCurve(to: p(0.2, 0.9), controlPoint1: p(0.98, 0.52), controlPoint2: p(0.62, 0.9))
            path.close()
        case .bell:
            // A round bell with its loop; the slot is cut out.
            path.append(UIBezierPath(ovalIn: CGRect(x: r.minX + r.width * 0.1, y: r.minY + r.height * 0.2, width: r.width * 0.8, height: r.height * 0.8)))
            path.append(UIBezierPath(ovalIn: CGRect(x: r.minX + r.width * 0.36, y: r.minY, width: r.width * 0.28, height: r.height * 0.28)))
            let slot = UIBezierPath(roundedRect: CGRect(x: r.minX + r.width * 0.26, y: r.minY + r.height * 0.6, width: r.width * 0.48, height: r.height * 0.1), cornerRadius: r.height * 0.05)
            path.append(slot.reversing())
        }
        return path
    }

    // MARK: numerals

    static func numeralFont(size: CGFloat) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: .black)
        return base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base
    }

    /// White in the app's ink outline, its cap height centred on `center`.
    static func drawNumeral(
        _ text: String, centeredAt center: CGPoint, size: CGFloat, outline: CGFloat, kern: CGFloat = 0, fill: UIColor = .white
    ) {
        let font = numeralFont(size: size)
        var stroke: [NSAttributedString.Key: Any] = [.font: font, .kern: kern, .strokeColor: ink, .strokeWidth: outline * 2 / size * 100]
        let width = (text as NSString).size(withAttributes: [.font: font, .kern: kern]).width - kern
        let origin = CGPoint(x: center.x - width / 2, y: center.y - font.capHeight / 2 - (font.ascender - font.capHeight))
        (text as NSString).draw(at: origin, withAttributes: stroke)
        stroke = [.font: font, .kern: kern, .foregroundColor: fill]
        (text as NSString).draw(at: origin, withAttributes: stroke)
    }

    /// Outlined words or numbers as one texture (the turn button's label, counts, the meter).
    func label(_ text: String, size: CGFloat, fill: UIColor = .white, outline: CGFloat = 2.5) -> SKTexture {
        let key = "label|\(text)|\(size)|\(fill.description)|\(outline)"
        if let cached = misc[key] { return cached }
        let font = Self.numeralFont(size: size)
        let measured = (text as NSString).size(withAttributes: [.font: font])
        let canvas = CGSize(width: ceil(measured.width + outline * 2 + 2), height: ceil(font.capHeight + outline * 2 + 4))
        let image = Self.render(canvas) { rect in
            Self.drawNumeral(text, centeredAt: CGPoint(x: rect.midX, y: rect.midY), size: size, outline: outline, fill: fill)
        }
        let texture = SKTexture(image: image)
        misc[key] = texture
        return texture
    }

    // MARK: set plates and badges

    enum Plate: String {
        /// A set at rest: a soft dark bed that gathers its pieces.
        case plain
        /// Changed this turn and fine: a solid lime glow.
        case changed
        /// Before opening: a thin ring, the rug's sets are locked.
        case locked
        /// The set a dragged or selected piece would join.
        case target
        /// What changed since my turn.
        case recap
    }

    /// A stretchable rounded plate (use `plateCenter` as the sprite's `centerRect`).
    func plate(_ plate: Plate, tint: UIColor? = nil) -> SKTexture {
        let key = "plate|\(plate.rawValue)|\(tint?.description ?? "")"
        if let cached = misc[key] { return cached }
        let side: CGFloat = 36
        let image = Self.render(CGSize(width: side, height: side)) { rect in
            let radius: CGFloat = 10
            switch plate {
            case .plain:
                Self.ink.withAlphaComponent(0.26).setFill()
                UIBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerRadius: radius).fill()
            case .locked:
                Self.ink.withAlphaComponent(0.26).setFill()
                UIBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerRadius: radius).fill()
                let ring = UIBezierPath(roundedRect: rect.insetBy(dx: 1.75, dy: 1.75), cornerRadius: radius - 0.75)
                ring.lineWidth = 1.5
                UIColor.white.withAlphaComponent(0.75).setStroke()
                ring.stroke()
            case .changed, .target, .recap:
                let color = tint ?? (plate == .changed ? UIColor(Palette.lime) : UIColor.white)
                Self.ink.withAlphaComponent(0.3).setFill()
                UIBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerRadius: radius).fill()
                let outer = UIBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: radius + 0.5)
                outer.lineWidth = 1
                Self.ink.setStroke()
                outer.stroke()
                let ring = UIBezierPath(roundedRect: rect.insetBy(dx: 2.5, dy: 2.5), cornerRadius: radius - 1.5)
                ring.lineWidth = 3
                color.setStroke()
                ring.stroke()
            }
        }
        let texture = SKTexture(image: image)
        misc[key] = texture
        return texture
    }

    static let plateCenter = CGRect(x: 0.36, y: 0.36, width: 0.28, height: 0.28)

    /// The loupe's panel: an opaque night-violet card in the ink outline with a teal rim (stretch
    /// it with `plateCenter`).
    func panel() -> SKTexture {
        let key = "panel"
        if let cached = misc[key] { return cached }
        let side: CGFloat = 36
        let image = Self.render(CGSize(width: side, height: side)) { rect in
            Self.ink.setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 12).fill()
            UIColor(Palette.teal).setFill()
            UIBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), cornerRadius: 10).fill()
            UIColor(Color(hex: 0x3A1785)).setFill()
            UIBezierPath(roundedRect: rect.insetBy(dx: 4.5, dy: 4.5), cornerRadius: 7.5).fill()
        }
        let texture = SKTexture(image: image)
        misc[key] = texture
        return texture
    }

    enum Badge: Hashable {
        /// Fine and changed this turn: the check paw.
        case check
        case locked
        case problem(TilesDraft.Problem)
        /// A piece placed this turn: a small paw dot.
        case placed
    }

    /// A round badge that says, with no words, how a set stands (tile game spec §5.5): a "3" for
    /// too short, two different toys for a mixed row, one toy twice for a doubled match, a
    /// broken chain for a gap.
    func badge(_ badge: Badge) -> SKTexture {
        let key = "badge|\(badge)"
        if let cached = misc[key] { return cached }
        let side: CGFloat = 26
        let image = Self.render(CGSize(width: side, height: side)) { rect in
            let fill: UIColor
            switch badge {
            case .check: fill = UIColor(Palette.lime)
            case .locked: fill = UIColor(Palette.violet)
            case .problem: fill = UIColor(Palette.refuse)
            case .placed: fill = UIColor(Palette.magenta)
            }
            UIColor.white.setFill()
            UIBezierPath(ovalIn: rect).fill()
            Self.ink.setFill()
            UIBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            fill.setFill()
            UIBezierPath(ovalIn: rect.insetBy(dx: 3, dy: 3)).fill()
            let inner = rect.insetBy(dx: 6, dy: 6)
            switch badge {
            case .check:
                UIImage(named: ArtName.iconCheck)?.draw(in: rect.insetBy(dx: 4, dy: 4))
            case .locked:
                UIImage(named: ArtName.Habit.iconPadlock)?.draw(in: rect.insetBy(dx: 4, dy: 4))
            case .placed:
                UIImage(named: ArtName.iconPawMenu)?.draw(in: rect.insetBy(dx: 4.5, dy: 4.5))
            case .problem(.tooShort):
                Self.drawNumeral("3", centeredAt: CGPoint(x: rect.midX, y: rect.midY), size: 17, outline: 1.6)
            case .problem(.mixedSuits):
                UIColor.white.setFill()
                Self.silhouette(.fish, in: CGRect(x: inner.minX - 1, y: inner.minY - 1, width: inner.width * 0.62, height: inner.height * 0.62)).fill()
                Self.silhouette(.bell, in: CGRect(x: inner.midX - 1, y: inner.midY - 1.5, width: inner.width * 0.6, height: inner.height * 0.6)).fill()
            case .problem(.suitTwice):
                UIColor.white.setFill()
                Self.silhouette(.fish, in: CGRect(x: inner.minX, y: inner.minY - 1.5, width: inner.width * 0.72, height: inner.height * 0.6)).fill()
                Self.silhouette(.fish, in: CGRect(x: inner.minX + inner.width * 0.28, y: inner.midY - 0.5, width: inner.width * 0.72, height: inner.height * 0.6)).fill()
            case .problem(.gap):
                // Two chain links pulled apart.
                UIColor.white.setStroke()
                for x in [inner.minX - 1, inner.midX + 1.5] {
                    let link = UIBezierPath(roundedRect: CGRect(x: x, y: inner.midY - 3.2, width: inner.width / 2 - 0.5, height: 6.4), cornerRadius: 3.2)
                    link.lineWidth = 2.2
                    link.stroke()
                }
            }
        }
        let texture = SKTexture(image: image)
        misc[key] = texture
        return texture
    }

    // MARK: the action strip

    enum Symbol: String {
        case undo = "arrow.uturn.backward"
        case reset = "arrow.counterclockwise"
        case sortNumber = "textformat.123"
        case tidy = "wand.and.sparkles"
        case hint = "lightbulb.fill"
        case close = "xmark"
        case changed = "eye.fill"
        case handle = "hand.draw.fill"
    }

    /// A chunky round button: `color` inside the ink outline with a hard shadow, a white symbol
    /// (or a toy's glyph) on it. `on` is a toggle that is set: orange, so state is not hue alone
    /// (the shell also draws it pressed in). `dim` is a control with nothing to do.
    func button(_ symbol: Symbol? = nil, suit: TileSuit? = nil, side: CGFloat, on: Bool = false, dim: Bool = false) -> SKTexture {
        let key = "button|\(symbol?.rawValue ?? "")|\(suit?.rawValue ?? "")|\(side)|\(on)|\(dim)"
        if let cached = misc[key] { return cached }
        let shadow: CGFloat = on ? 1 : 3
        let image = Self.render(CGSize(width: side, height: side + 3)) { _ in
            let disc = CGRect(x: 0, y: 3 - shadow, width: side, height: side)
            Self.ink.withAlphaComponent(0.6).setFill()
            UIBezierPath(ovalIn: disc.offsetBy(dx: 0, dy: shadow)).fill()
            Self.ink.setFill()
            UIBezierPath(ovalIn: disc).fill()
            (on ? UIColor(Palette.orange) : UIColor(Palette.violet)).setFill()
            UIBezierPath(ovalIn: disc.insetBy(dx: 2.5, dy: 2.5)).fill()
            UIColor.white.withAlphaComponent(0.22).setFill()
            UIBezierPath(ovalIn: CGRect(x: disc.minX + side * 0.2, y: disc.minY + side * 0.1, width: side * 0.6, height: side * 0.3)).fill()
            let inner = disc.insetBy(dx: side * 0.24, dy: side * 0.24)
            if let suit {
                UIImage(named: ArtName.Tiles.glyph(suit))?.draw(in: disc.insetBy(dx: side * 0.17, dy: side * 0.17))
            } else if let symbol {
                let config = UIImage.SymbolConfiguration(pointSize: inner.height * 0.78, weight: .black)
                if let glyph = UIImage(systemName: symbol.rawValue, withConfiguration: config)?.withTintColor(.white, renderingMode: .alwaysOriginal) {
                    let fit = min(inner.width / glyph.size.width, inner.height / glyph.size.height, 1.25)
                    let size = CGSize(width: glyph.size.width * fit, height: glyph.size.height * fit)
                    glyph.draw(in: CGRect(x: disc.midX - size.width / 2, y: disc.midY - size.height / 2, width: size.width, height: size.height))
                }
            }
        }
        let texture = SKTexture(image: dim ? Self.dimmed(image) : image)
        misc[key] = texture
        return texture
    }

    private static func dimmed(_ image: UIImage) -> UIImage {
        render(image.size) { rect in image.draw(in: rect, blendMode: .normal, alpha: 0.4) }
    }

    enum Pill: String {
        /// Draw: teal. Pass: sky. Play: the big lime paw. Blocked: grey.
        case draw, pass, play, blocked
    }

    /// The turn button's body: a wide glossy pill with a hard shadow.
    func pill(_ pill: Pill, size: CGSize, pressed: Bool = false) -> SKTexture {
        let key = "pill|\(pill.rawValue)|\(size.width)x\(size.height)|\(pressed)"
        if let cached = misc[key] { return cached }
        let shadow: CGFloat = pressed ? 1 : 4
        let image = Self.render(CGSize(width: size.width, height: size.height + 4)) { _ in
            let body = CGRect(x: 0, y: 4 - shadow, width: size.width, height: size.height)
            let radius = size.height / 2
            Self.ink.withAlphaComponent(0.6).setFill()
            UIBezierPath(roundedRect: body.offsetBy(dx: 0, dy: shadow), cornerRadius: radius).fill()
            Self.ink.setFill()
            UIBezierPath(roundedRect: body, cornerRadius: radius).fill()
            let colors: (UIColor, UIColor)
            switch pill {
            case .draw: colors = (UIColor(Color(hex: 0x4FF2E4)), UIColor(Palette.teal))
            case .pass: colors = (UIColor(Color(hex: 0x7DD4FF)), UIColor(Palette.sky))
            case .play: colors = (UIColor(Color(hex: 0xC6F56A)), UIColor(Palette.lime))
            case .blocked: colors = (UIColor(Color(hex: 0x8C7DB0)), UIColor(Color(hex: 0x6A5A93)))
            }
            let inner = body.insetBy(dx: 3, dy: 3)
            guard let ctx = UIGraphicsGetCurrentContext() else { return }
            ctx.saveGState()
            UIBezierPath(roundedRect: inner, cornerRadius: radius - 3).addClip()
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [colors.0.cgColor, colors.1.cgColor] as CFArray, locations: [0, 0.7]) {
                ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: inner.minY), end: CGPoint(x: 0, y: inner.maxY), options: [.drawsAfterEndLocation])
            }
            UIColor.white.withAlphaComponent(0.35).setFill()
            UIBezierPath(
                roundedRect: CGRect(x: inner.minX + radius * 0.5, y: inner.minY + 2.5, width: inner.width - radius, height: size.height * 0.16),
                cornerRadius: size.height * 0.08
            ).fill()
            ctx.restoreGState()
        }
        let texture = SKTexture(image: image)
        misc[key] = texture
        return texture
    }

    /// The opening meter's track and its fill (tile game spec §5.5): a pill that fills toward
    /// 30 and turns gold when it gets there.
    func meter(size: CGSize, fraction: CGFloat, gold: Bool) -> SKTexture {
        let step = (min(max(fraction, 0), 1) * 30).rounded()
        let key = "meter|\(size.width)x\(size.height)|\(step)|\(gold)"
        if let cached = misc[key] { return cached }
        let image = Self.render(size) { rect in
            let radius = rect.height / 2
            UIColor.white.setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: radius).fill()
            Self.ink.setFill()
            UIBezierPath(roundedRect: rect.insetBy(dx: 1.5, dy: 1.5), cornerRadius: radius - 1.5).fill()
            let track = rect.insetBy(dx: 4, dy: 4)
            UIColor(Color(hex: 0x4A2A8C)).setFill()
            UIBezierPath(roundedRect: track, cornerRadius: track.height / 2).fill()
            guard step > 0, let ctx = UIGraphicsGetCurrentContext() else { return }
            ctx.saveGState()
            UIBezierPath(roundedRect: track, cornerRadius: track.height / 2).addClip()
            (gold ? UIColor(Color(hex: 0xFFD21F)) : UIColor(Palette.magenta)).setFill()
            UIRectFill(CGRect(x: track.minX, y: track.minY, width: track.width * step / 30, height: track.height))
            UIColor.white.withAlphaComponent(0.3).setFill()
            UIRectFill(CGRect(x: track.minX, y: track.minY + 1, width: track.width * step / 30, height: track.height * 0.3))
            ctx.restoreGState()
        }
        let texture = SKTexture(image: image)
        misc[key] = texture
        return texture
    }

    /// A count on a small ink pill (the toy box's pieces).
    func count(_ value: Int, size: CGFloat) -> SKTexture {
        CardFaceFactory.shared.badge(String(value), size: size)
    }

    /// A dashed outline for a set that isn't one yet, or the "new row" slot: drawn per size,
    /// since a stretched dash would smear.
    func dashed(_ size: CGSize, color: UIColor, fill: UIColor = .clear) -> SKTexture {
        let key = "dashed|\(Int(size.width))x\(Int(size.height))|\(color.description)|\(fill.description)"
        if let cached = misc[key] { return cached }
        let image = Self.render(size) { rect in
            let path = UIBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), cornerRadius: 9)
            fill.setFill()
            path.fill()
            path.lineWidth = 4.5
            Self.ink.setStroke()
            path.setLineDash([7, 5], count: 2, phase: 0)
            path.lineCapStyle = .round
            path.stroke()
            path.lineWidth = 2.5
            color.setStroke()
            path.stroke()
        }
        let texture = SKTexture(image: image)
        misc[key] = texture
        return texture
    }
}
