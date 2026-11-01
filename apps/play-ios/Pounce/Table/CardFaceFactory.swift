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

/// Composites each card face once (`card-face` + `coat-<c>` + numeral + `glyph-<c>`, or the
/// Yarn / Cucumber art) into one texture per id, so a card is a single sprite at runtime.
/// Also renders the outlined numerals the table uses (count bubbles, shelf badges).
@MainActor
final class CardFaceFactory {
    static let shared = CardFaceFactory()

    /// Card art is drawn at this point size (the manifest's `card-face`).
    static let cardSize = CGSize(width: 64, height: 90)

    private var faces: [CardID: SKTexture] = [:]
    private var numerals: [String: SKTexture] = [:]
    private var backTexture: SKTexture?

    func texture(for card: CardID) -> SKTexture {
        if let cached = faces[card] { return cached }
        let image = Self.renderFace(card)
        let t = SKTexture(image: image)
        faces[card] = t
        return t
    }

    func back() -> SKTexture {
        if let backTexture { return backTexture }
        let t = TableArt.cards(ArtName.cardBack)
        backTexture = t
        return t
    }

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

    // MARK: drawing

    private static func renderFace(_ card: CardID) -> UIImage {
        let size = cardSize
        return UIGraphicsImageRenderer(size: size).image { _ in
            UIImage(named: ArtName.cardFace)?.draw(in: CGRect(origin: .zero, size: size))
            switch Card(id: card) {
            case .yarn:
                UIImage(named: ArtName.cardYarn)?.draw(in: CGRect(x: 6, y: 19, width: 52, height: 52))
            case .cucumber:
                UIImage(named: ArtName.cardCucumber)?.draw(in: CGRect(x: 6, y: 19, width: 52, height: 52))
            case .number(let value, let coat):
                // Cat face lower center, numeral top-left, glyph under the numeral.
                UIImage(named: ArtName.coat(coat))?.draw(in: CGRect(x: 12, y: 36, width: 46, height: 46))
                drawOutlined(String(value), at: CGPoint(x: 5, y: 2), size: value >= 10 ? 21 : 25,
                             fill: UIColor(Palette.violet), outline: 3)
                UIImage(named: ArtName.glyph(coat))?.draw(in: CGRect(x: 7, y: 33, width: 15, height: 15))
            }
        }
    }

    private static func numeralAttributes(size: CGFloat) -> [NSAttributedString.Key: Any] {
        let base = UIFont.systemFont(ofSize: size, weight: .black)
        let font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base
        return [.font: font]
    }

    /// Stroke first (centered on the glyph edge), then the fill on top, so the outline only
    /// grows outward and the numeral keeps its weight.
    private static func drawOutlined(_ text: String, at origin: CGPoint, size: CGFloat, fill: UIColor, outline: CGFloat) {
        var attrs = numeralAttributes(size: size)
        attrs[.strokeColor] = UIColor(Palette.ink)
        attrs[.strokeWidth] = outline * 2 / size * 100  // percent of the font size, stroke only
        (text as NSString).draw(at: origin, withAttributes: attrs)
        var fillAttrs = numeralAttributes(size: size)
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
