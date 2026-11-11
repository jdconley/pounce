import PounceKit
import SpriteKit
import SwiftUI
import UIKit

/// Atlas and image-set textures for the table, loaded once.
@MainActor
enum TableArt {
    private static var atlases: [String: SKTextureAtlas] = [:]
    private static var images: [String: SKTexture] = [:]

    /// A sprite from one of the sprite atlases (`ArtName.Atlas`).
    static func texture(_ name: String, atlas: String) -> SKTexture {
        let a: SKTextureAtlas
        if let cached = atlases[atlas] {
            a = cached
        } else {
            a = SKTextureAtlas(named: atlas)
            atlases[atlas] = a
        }
        return a.textureNamed(name)
    }

    /// A plain image set from the asset catalog (backgrounds, badges).
    static func image(_ name: String) -> SKTexture {
        if let cached = images[name] { return cached }
        let t = SKTexture(imageNamed: name)
        images[name] = t
        return t
    }

    static func cat(_ index: Int, _ pose: CatPose) -> SKTexture {
        texture(ArtName.cat(min(max(index, 0), ArtName.catCount - 1), pose), atlas: ArtName.Atlas.cats)
    }

    static func table(_ name: String) -> SKTexture { texture(name, atlas: ArtName.Atlas.table) }
    static func cards(_ name: String) -> SKTexture { texture(name, atlas: ArtName.Atlas.cards) }

    /// Starts decoding every table atlas off the main thread.
    static func preload() {
        let names = [ArtName.Atlas.cats, ArtName.Atlas.cards, ArtName.Atlas.table, ArtName.Atlas.fx]
        let list = names.map { name in
            let a = atlases[name] ?? SKTextureAtlas(named: name)
            atlases[name] = a
            return a
        }
        SKTextureAtlas.preloadTextureAtlases(list) {}
    }
}

/// Draws each card face once (frame + numeral + `glyph-<c>` + `coat-<c>`, or the Yarn /
/// Cucumber art) into one texture per id, so a card is a single sprite at runtime. Every card,
/// back included, gets the same frame: a white keyline outside a thick ink outline. On the
/// dark violet floor the white edge carries the contrast (6:1 or more), on the bright rug the
/// ink does (4.5:1 or more); some edge reads at 3:1 or better on any surface.
/// Also renders the outlined numerals the table uses (count bubbles, shelf badges).
@MainActor
final class CardFaceFactory {
    static let shared = CardFaceFactory()

    /// Card art is drawn at this point size (the manifest's `card-face`).
    static let cardSize = CGSize(width: 64, height: 90)

    private struct FaceKey: Hashable {
        let card: CardID
        let compact: Bool
    }

    private var faces: [FaceKey: SKTexture] = [:]
    private var numerals: [String: SKTexture] = [:]

    private var blankTexture: SKTexture?

    /// The full face (hand, piles, cards in flight), or the compact one for cards drawn small
    /// (laid groups, trays): a corner index half again as big and a smaller cat.
    func texture(for card: CardID, compact: Bool = false) -> SKTexture {
        let key = FaceKey(card: card, compact: compact)
        if let cached = faces[key] { return cached }
        let t = SKTexture(image: Self.renderFace(card, compact: compact))
        faces[key] = t
        return t
    }

    /// The face is already drawn (`texture(for:compact:)` returns it at once).
    func hasTexture(for card: CardID, compact: Bool = false) -> Bool {
        faces[FaceKey(card: card, compact: compact)] != nil
    }

    /// Draws ahead what a drag over the laid groups shows for the first time: the preview
    /// rings, the "+N" badges a group's gap can fold to and the numbers a Yarn stands for.
    /// Each is cached, so a second call costs nothing.
    func prewarmPreview() {
        _ = ring(UIColor(Palette.lime))
        _ = ring(UIColor(Palette.refuse))
        for n in 1...12 {
            _ = badge("+\(n)", size: LaidZoneNode.badgeSize)
            _ = badge(String(n), size: LaidZoneNode.badgeSize + 4)
        }
    }

    /// The open table's card back (§9.4), an art name; cards drawn from now on take it.
    private(set) var backName = ArtName.cardBack
    private var backTextures: [String: SKTexture] = [:]

    /// Sets the table's back from its look's id (an unknown id is the classic back).
    func setBack(_ id: String) {
        backName = ArtName.Habit.back(id)
    }

    func back() -> SKTexture {
        if let cached = backTextures[backName] { return cached }
        let t = SKTexture(image: backName == ArtName.cardBack ? Self.backImage : Self.backImage(backName))
        backTextures[backName] = t
        return t
    }

    /// A card back's art in the card frame, for SwiftUI (the look tray).
    static func backImage(_ name: String) -> UIImage {
        render(scale: 1) { inner in
            UIImage(named: name)?.draw(in: inner.insetBy(dx: -1.5, dy: -1.5))
        }
    }

    /// A face with nothing on it (the discard pile's under-cards).
    func blank() -> SKTexture {
        if let blankTexture { return blankTexture }
        let t = SKTexture(image: Self.render(scale: 1) { inner in Self.drawFace(in: inner) })
        blankTexture = t
        return t
    }

    /// The card back in its frame, for SwiftUI screens too.
    static let backImage: UIImage = render(scale: 1) { inner in
        // A little larger than the hole so the art's own rim tucks under the ink.
        UIImage(named: ArtName.cardBack)?.draw(in: inner.insetBy(dx: -1.5, dy: -1.5))
    }

    /// How far a card's corner index reaches from its left edge (card points, compact face):
    /// a fanned group overlaps the next card no further, so every numeral shows.
    static func indexWidth(_ card: CardID) -> CGFloat {
        guard case .number(let value, _) = Card(id: card) else { return 36 }
        if let cached = indexWidths[value] { return cached }
        let style = IndexStyle.compact
        let text = String(value)
        let size = style.size(text)
        var attrs = numeralAttributes(size: size)
        attrs[.kern] = style.kern(text)
        let width = ceil(style.corner.x + (text as NSString).size(withAttributes: attrs).width + indexOutline * 2 + 2)
        indexWidths[value] = width
        return width
    }

    private static var indexWidths: [Int: CGFloat] = [:]

    /// A numeral in SF Pro Rounded Black with a thick ink outline, cached by content.
    func numeral(_ text: String, size: CGFloat, fill: UIColor = .white, outline: CGFloat = 3) -> SKTexture {
        let key = "\(text)|\(size)|\(fill.hexKey)|\(outline)"
        if let cached = numerals[key] { return cached }
        let attrs = Self.numeralAttributes(size: size)
        let textSize = (text as NSString).size(withAttributes: attrs)
        let canvas = CGSize(width: ceil(textSize.width + outline * 2), height: ceil(textSize.height + outline * 2))
        let image = UIGraphicsImageRenderer(size: canvas).image { _ in
            Self.drawOutlined(text, at: CGPoint(x: outline, y: outline), size: size, fill: fill, outline: outline)
        }
        let t = SKTexture(image: image)
        numerals[key] = t
        return t
    }

    /// A "+3" pill for cards folded out of a laid group: white on ink (18:1) inside a white
    /// keyline, so it reads on a card face and on the rug alike. Cached by content.
    func badge(_ text: String, size: CGFloat) -> SKTexture {
        let key = "badge|\(text)|\(size)"
        if let cached = numerals[key] { return cached }
        let attrs = Self.numeralAttributes(size: size)
        let textSize = (text as NSString).size(withAttributes: attrs)
        let h = ceil(textSize.height + 4)
        let canvas = CGSize(width: max(h, ceil(textSize.width + h * 0.6)), height: h)
        let image = UIGraphicsImageRenderer(size: canvas).image { _ in
            let pill = CGRect(origin: .zero, size: canvas)
            UIColor.white.setFill()
            UIBezierPath(roundedRect: pill, cornerRadius: h / 2).fill()
            UIColor(Palette.ink).setFill()
            UIBezierPath(roundedRect: pill.insetBy(dx: 1.5, dy: 1.5), cornerRadius: h / 2 - 1.5).fill()
            var fill = attrs
            fill[.foregroundColor] = UIColor.white
            (text as NSString).draw(at: CGPoint(x: (canvas.width - textSize.width) / 2, y: 2), withAttributes: fill)
        }
        let t = SKTexture(image: image)
        numerals[key] = t
        return t
    }

    /// Name text size on the table: an 11 pt cap height in SF Pro Rounded Black.
    static let nameSize: CGFloat = 16

    /// A player's name on a pill no wider than `maxWidth`, cut short with an ellipsis when it
    /// doesn't fit. At rest white on ink inside a white keyline (18:1, readable on the rug, the
    /// floor and card faces alike); `active` (whose turn it is) ink on orange (7.6:1). Cached.
    func nameTag(_ name: String, maxWidth: CGFloat, active: Bool) -> SKTexture {
        let size = Self.nameSize
        let key = "name|\(name)|\(Int(maxWidth))|\(active)"
        if let cached = numerals[key] { return cached }
        let attrs = Self.numeralAttributes(size: size)
        let h = ceil(("Ag" as NSString).size(withAttributes: attrs).height + 4)
        let pad = h * 0.24
        let text = Self.truncated(name, toFit: max(maxWidth - 2 * pad, size), attributes: attrs)
        let textSize = (text as NSString).size(withAttributes: attrs)
        let canvas = CGSize(width: max(h, ceil(textSize.width + 2 * pad)), height: h)
        let image = UIGraphicsImageRenderer(size: canvas).image { _ in
            let pill = CGRect(origin: .zero, size: canvas)
            UIColor.white.setFill()
            UIBezierPath(roundedRect: pill, cornerRadius: h / 2).fill()
            UIColor(active ? Palette.orange : Palette.ink).setFill()
            UIBezierPath(roundedRect: pill.insetBy(dx: 1.5, dy: 1.5), cornerRadius: h / 2 - 1.5).fill()
            var fill = attrs
            fill[.foregroundColor] = active ? UIColor(Palette.ink) : UIColor.white
            (text as NSString).draw(at: CGPoint(x: (canvas.width - textSize.width) / 2, y: 2), withAttributes: fill)
        }
        let t = SKTexture(image: image)
        numerals[key] = t
        return t
    }

    /// A seat's phase chip: "L4" in ink on a glossy gold pill (the tower's shelf-badge gold)
    /// inside an ink outline, with a hard shadow; a trophy on it once every phase is done. The
    /// "P" is small and the number big, cap heights at least 11 pt. Not a card shape and not
    /// white numerals, so it never reads as the card count. Cached by mark and height.
    func phaseChip(_ mark: PhaseMark, height: CGFloat) -> SKTexture {
        let h = max(height.rounded(), 20)
        let key = "phase|\(mark.text ?? "done")|\(h)"
        if let cached = numerals[key] { return cached }
        let digitSize = (h * 0.8).rounded()
        let letterSize = max((digitSize * 0.72).rounded(), 16)
        let ink = UIColor(Palette.ink)
        let text = NSMutableAttributedString()
        if let number = mark.number {
            text.append(NSAttributedString(string: "L", attributes: [
                .font: Self.numeralFont(size: letterSize), .foregroundColor: ink, .kern: 1,
            ]))
            text.append(NSAttributedString(string: String(number), attributes: [
                .font: Self.numeralFont(size: digitSize), .foregroundColor: ink,
            ]))
        }
        let pad = (h * 0.32).rounded()
        let textWidth = ceil(text.size().width)
        let width = mark.isDone ? (h * 1.6).rounded() : max(h, textWidth + pad * 2)
        let shadow: CGFloat = 2
        let canvas = CGSize(width: width, height: h + shadow)
        let image = UIGraphicsImageRenderer(size: canvas).image { ctx in
            let pill = CGRect(x: 0, y: 0, width: width, height: h)
            ink.withAlphaComponent(0.55).setFill()
            UIBezierPath(roundedRect: pill.offsetBy(dx: 0, dy: shadow), cornerRadius: h / 2).fill()
            ink.setFill()
            UIBezierPath(roundedRect: pill, cornerRadius: h / 2).fill()
            let inner = pill.insetBy(dx: 2, dy: 2)
            ctx.cgContext.saveGState()
            UIBezierPath(roundedRect: inner, cornerRadius: inner.height / 2).addClip()
            let colors = [Self.chipGoldTop.cgColor, Self.chipGold.cgColor, Self.chipGoldDeep.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1]) {
                ctx.cgContext.drawLinearGradient(
                    gradient, start: CGPoint(x: 0, y: inner.minY), end: CGPoint(x: 0, y: inner.maxY), options: [])
            }
            // A soft gloss along the top, the tower art's rim light.
            UIColor.white.withAlphaComponent(0.35).setFill()
            UIBezierPath(
                roundedRect: CGRect(x: inner.minX + h * 0.3, y: inner.minY + 1.5, width: inner.width - h * 0.6, height: h * 0.18),
                cornerRadius: h * 0.09
            ).fill()
            ctx.cgContext.restoreGState()
            if mark.isDone {
                let side = h * 0.86
                UIImage(named: ArtName.iconTrophy)?.draw(
                    in: CGRect(x: (width - side) / 2, y: (h - side) / 2, width: side, height: side))
            } else {
                // Center the digits' cap height in the pill; the "P" shares their baseline.
                let font = Self.numeralFont(size: digitSize)
                let baseline = h / 2 + font.capHeight / 2
                text.draw(at: CGPoint(x: (width - textWidth) / 2, y: baseline - font.ascender))
            }
        }
        let t = SKTexture(image: image)
        numerals[key] = t
        return t
    }

    /// The phase chip's gold, top to bottom (the tower's shelf badges).
    private static let chipGoldTop = UIColor(red: 1, green: 0.88, blue: 0.36, alpha: 1)
    private static let chipGold = UIColor(red: 1, green: 0.76, blue: 0.1, alpha: 1)
    private static let chipGoldDeep = UIColor(red: 0.98, green: 0.6, blue: 0, alpha: 1)

    /// A rounded ring for the laid group a dragged card is over: `color` inside an ink
    /// outline, so it reads on the rug and over card faces. Stretch it with `ringCenter`.
    func ring(_ color: UIColor) -> SKTexture {
        let key = "ring|\(color.hexKey)"
        if let cached = numerals[key] { return cached }
        let side: CGFloat = 40
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            let outer = UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: side, height: side), cornerRadius: 12)
            let inner = UIBezierPath(roundedRect: CGRect(x: 8, y: 8, width: side - 16, height: side - 16), cornerRadius: 6)
            outer.append(inner)
            outer.usesEvenOddFillRule = true
            UIColor(Palette.ink).setFill()
            outer.fill()
            let band = UIBezierPath(roundedRect: CGRect(x: 2, y: 2, width: side - 4, height: side - 4), cornerRadius: 10)
            band.append(UIBezierPath(roundedRect: CGRect(x: 6, y: 6, width: side - 12, height: side - 12), cornerRadius: 7))
            band.usesEvenOddFillRule = true
            color.setFill()
            band.fill()
        }
        let t = SKTexture(image: image)
        numerals[key] = t
        return t
    }

    /// `text`, or as much of it as fits `width` followed by an ellipsis.
    private static func truncated(_ text: String, toFit width: CGFloat, attributes: [NSAttributedString.Key: Any]) -> String {
        func fits(_ s: String) -> Bool { (s as NSString).size(withAttributes: attributes).width <= width }
        if fits(text) { return text }
        var cut = text
        while !cut.isEmpty {
            cut.removeLast()
            let trimmed = cut.trimmingCharacters(in: .whitespaces)
            if fits(trimmed + "…") { return trimmed + "…" }
        }
        return "…"
    }

    /// The stretchable middle of `ring(_:)`.
    static let ringCenter = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)

    // MARK: drawing

    /// White keyline, then the ink outline, then whatever `inside` draws, clipped to the hole.
    private static let keyline: CGFloat = 2
    private static let inkLine: CGFloat = 3
    private static let corner: CGFloat = 10
    private static let indexOutline: CGFloat = 3

    /// Where and how big the corner index is drawn (card points).
    private enum IndexStyle {
        case full, compact

        var corner: CGPoint { self == .full ? CGPoint(x: 7, y: 7) : CGPoint(x: 6, y: 6) }

        func size(_ text: String) -> CGFloat {
            switch self {
            case .full: text.count > 1 ? 21 : 25
            case .compact: text.count > 1 ? 30 : 34
            }
        }

        /// Two digits sit a little tighter so they fit a fanned card's visible strip.
        func kern(_ text: String) -> CGFloat {
            guard text.count > 1 else { return 0 }
            return self == .full ? -0.8 : -1.8
        }
    }

    /// Extra pixels for a screen whose tables can be roomy (`TableLayout.roomyMinSide`), where
    /// hand cards are drawn up to 104 pt wide: the art keeps its edges at that size.
    static let detail: CGFloat = {
        let screen = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }.first
        guard let side = screen.map({ min($0.bounds.width, $0.bounds.height) }) else { return 1 }
        return side >= TableLayout.roomyMinSide ? 1.6 : 1
    }()

    /// Compact faces are only ever drawn small, so they render at three quarters the pixels.
    private static func render(scale: CGFloat, _ inside: (CGRect) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale *= scale * detail
        let bounds = CGRect(origin: .zero, size: cardSize)
        return UIGraphicsImageRenderer(size: cardSize, format: format).image { ctx in
            UIColor.white.setFill()
            UIBezierPath(roundedRect: bounds, cornerRadius: corner).fill()
            UIColor(Palette.ink).setFill()
            UIBezierPath(roundedRect: bounds.insetBy(dx: keyline, dy: keyline), cornerRadius: corner - keyline).fill()
            let inner = bounds.insetBy(dx: keyline + inkLine, dy: keyline + inkLine)
            ctx.cgContext.saveGState()
            UIBezierPath(roundedRect: inner, cornerRadius: corner - keyline - inkLine).addClip()
            inside(inner)
            ctx.cgContext.restoreGState()
        }
    }

    /// Plain white where the numerals sit; a soft lilac toward the bottom for a little gloss.
    private static func drawFace(in inner: CGRect) {
        UIColor.white.setFill()
        UIRectFill(inner)
        let colors = [UIColor.white.cgColor, UIColor(red: 0.93, green: 0.89, blue: 1, alpha: 1).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]),
           let ctx = UIGraphicsGetCurrentContext() {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: inner.minY + inner.height * 0.62),
                                   end: CGPoint(x: 0, y: inner.maxY), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
    }

    static func numeralColor(_ coat: Coat) -> UIColor {
        switch coat {
        case .tabby: UIColor(Palette.numeralTabby)
        case .tuxedo: UIColor(Palette.numeralTuxedo)
        case .calico: UIColor(Palette.numeralCalico)
        case .gray: UIColor(Palette.numeralGray)
        }
    }

    private static func renderFace(_ card: CardID, compact: Bool) -> UIImage {
        render(scale: compact ? 0.75 : 1) { _ in
            drawFace(in: CGRect(origin: .zero, size: cardSize))
            switch Card(id: card) {
            case .yarn:
                UIImage(named: ArtName.cardYarn)?.draw(in: compact ? CGRect(x: 6, y: 6, width: 44, height: 44) : CGRect(x: 8, y: 21, width: 48, height: 48))
            case .cucumber:
                UIImage(named: ArtName.cardCucumber)?.draw(in: compact ? CGRect(x: 6, y: 6, width: 44, height: 44) : CGRect(x: 8, y: 21, width: 48, height: 48))
            case .number(let value, let coat):
                // Numeral top-left, glyph under it, cat face lower right.
                let style: IndexStyle = compact ? .compact : .full
                let text = String(value)
                let capHeight = drawIndex(text, style: style, fill: numeralColor(coat))
                let glyphY = style.corner.y + capHeight + indexOutline * 2 + 2
                if compact {
                    UIImage(named: ArtName.glyph(coat))?.draw(in: CGRect(x: 8, y: glyphY, width: 15, height: 15))
                    UIImage(named: ArtName.coat(coat))?.draw(in: CGRect(x: 24, y: 46, width: 34, height: 34))
                } else {
                    UIImage(named: ArtName.coat(coat))?.draw(in: CGRect(x: 13, y: 37, width: 44, height: 44))
                    UIImage(named: ArtName.glyph(coat))?.draw(in: CGRect(x: 8, y: glyphY, width: 14, height: 14))
                }
            }
        }
    }

    /// Draws the corner index with its outlined cap top-left at the style's corner; returns
    /// the cap height.
    private static func drawIndex(_ text: String, style: IndexStyle, fill: UIColor) -> CGFloat {
        let size = style.size(text)
        let font = numeralFont(size: size)
        let origin = CGPoint(
            x: style.corner.x + indexOutline,
            y: style.corner.y + indexOutline - (font.ascender - font.capHeight))
        drawOutlined(text, at: origin, size: size, fill: fill, outline: indexOutline, kern: style.kern(text))
        return font.capHeight
    }

    private static func numeralFont(size: CGFloat) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: .black)
        return base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base
    }

    private static func numeralAttributes(size: CGFloat) -> [NSAttributedString.Key: Any] {
        [.font: numeralFont(size: size)]
    }

    /// Stroke first (centered on the glyph edge), then the fill on top, so the outline only
    /// grows outward and the numeral keeps its weight.
    private static func drawOutlined(
        _ text: String, at origin: CGPoint, size: CGFloat, fill: UIColor, outline: CGFloat, kern: CGFloat = 0
    ) {
        var attrs = numeralAttributes(size: size)
        attrs[.kern] = kern
        attrs[.strokeColor] = UIColor(Palette.ink)
        attrs[.strokeWidth] = outline * 2 / size * 100  // percent of the font size, stroke only
        (text as NSString).draw(at: origin, withAttributes: attrs)
        var fillAttrs = numeralAttributes(size: size)
        fillAttrs[.kern] = kern
        fillAttrs[.foregroundColor] = fill
        (text as NSString).draw(at: origin, withAttributes: fillAttrs)
    }
}

extension UIColor {
    /// A stable cache key for a color.
    fileprivate var hexKey: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02x%02x%02x%02x", Int(r * 255), Int(g * 255), Int(b * 255), Int(a * 255))
    }
}
