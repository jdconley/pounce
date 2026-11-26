import PounceKit
import SpriteKit
import SwiftUI
import UIKit

/// Draws Birdwatch's 57 card faces once into textures (design §3.3), so a card is one sprite at
/// runtime. Cat Tower's chunky card in Tuna Tiles' toy colours: a saturated body with a lit top and
/// a darker lip, the numeral big and white in the app's ink outline at the top left with the toy
/// under it (what shows when cards overlap in a hand), the toy again large in the middle, and on
/// a counter a gold seed badge with its points. The Bird has its own white face so it never passes
/// for a suit, with its own badge. Backs are Cat Tower's violet paw back.
///
/// Everything is drawn off the main thread (`prewarm`, `docs/main-thread.md`); the table waits for
/// it before its first frame, so it never draws a face itself.
@MainActor
final class BirdCardFactory {
    static let shared = BirdCardFactory()

    /// The point size a face is drawn at; sprites scale it to the layout's card size.
    nonisolated static let canvas = CGSize(width: 80, height: 114)

    private var faces: [BirdCardID: SKTexture] = [:]
    private var images: [BirdCardID: UIImage] = [:]
    private var badges: [String: SKTexture] = [:]
    private var warming: Task<Void, Never>?

    /// The scale faces are drawn at: the screen's, at least 2 (a TV's sill cards are large).
    static var scale: CGFloat {
        #if os(tvOS)
        return max(UIScreen.main.scale * 2.5, 2)
        #else
        return max(UIScreen.main.scale * 1.25, 2)
        #endif
    }

    nonisolated static let ink = UIColor(Palette.ink)
    nonisolated static let seedGold = UIColor(Color(hex: 0xFFC21A))
    nonisolated static let seedLight = UIColor(Color(hex: 0xFFE680))

    // MARK: faces

    func face(_ id: BirdCardID) -> SKTexture {
        if let cached = faces[id] { return cached }
        let work = FrameWork("bird.texture.face"); defer { work.end() }
        let image = Self.render(Self.canvas, scale: Self.scale) { Self.drawFace(id, in: $0) }
        let texture = SKTexture(image: image)
        faces[id] = texture
        images[id] = image
        return texture
    }

    /// A face as an image, for SwiftUI (the partner picker, the summary).
    func image(_ id: BirdCardID) -> UIImage {
        if let cached = images[id] { return cached }
        _ = face(id)
        return images[id] ?? UIImage()
    }

    func back() -> SKTexture { CardFaceFactory.shared.back() }

    /// Every face, off the main thread. Once a launch; later calls return at once.
    func prewarm() async {
        if warming == nil {
            let ids = (0..<BirdCard.deckSize).filter { faces[$0] == nil }
            let scale = Self.scale
            warming = Task {
                let made = await Self.drawFaces(ids, scale: scale)
                for (id, image, texture) in made where faces[id] == nil {
                    faces[id] = texture
                    images[id] = image
                }
                for suit in BirdSuit.allCases {
                    let key = Self.badgeKey(suit)
                    if badges[key] == nil { badges[key] = await Self.drawBadge(suit, scale: scale) }
                }
            }
        }
        await warming?.value
    }

    @concurrent
    private static func drawFaces(_ ids: [BirdCardID], scale: CGFloat) async -> sending [(BirdCardID, UIImage, SKTexture)] {
        let made = ids.map { id in
            let image = render(canvas, scale: scale) { drawFace(id, in: $0) }
            return (id, image, SKTexture(image: image))
        }
        await SKTexture.preload(made.map(\.2))
        return made
    }

    /// The trump badge: the toy on a glowing disc of its colour (96 by 96 points).
    func trumpBadge(_ suit: BirdSuit) -> SKTexture {
        let key = Self.badgeKey(suit)
        if let cached = badges[key] { return cached }
        let work = FrameWork("bird.texture.badge"); defer { work.end() }
        let texture = SKTexture(image: Self.render(Self.badgeSize, scale: Self.scale) { Self.drawTrumpBadge(suit, in: $0) })
        badges[key] = texture
        return texture
    }

    nonisolated static let badgeSize = CGSize(width: 96, height: 96)
    nonisolated private static func badgeKey(_ suit: BirdSuit) -> String { "trump|\(suit.rawValue)" }

    @concurrent
    private static func drawBadge(_ suit: BirdSuit, scale: CGFloat) async -> SKTexture {
        let texture = SKTexture(image: render(badgeSize, scale: scale) { drawTrumpBadge(suit, in: $0) })
        await SKTexture.preload([texture])
        return texture
    }

    // MARK: drawing (safe off the main thread)

    nonisolated static func render(_ size: CGSize, scale: CGFloat, _ draw: (CGRect) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in draw(CGRect(origin: .zero, size: size)) }
    }

    nonisolated static func drawFace(_ id: BirdCardID, in rect: CGRect) {
        guard let card = BirdCard(id: id) else { return }
        switch card {
        case .bird: drawBirdFace(in: rect)
        case .suited(let suit, let rank): drawSuitFace(suit, rank: rank, points: card.points, in: rect)
        }
    }

    /// The card's body: an ink rim, a darker lip along the bottom, the face lit from the top.
    /// Returns the face's rect.
    @discardableResult
    nonisolated static func drawBody(in rect: CGRect, top: UIColor, base: UIColor, side: UIColor) -> CGRect {
        let w = rect.width
        let line = max(w * 0.05, 2)
        let radius = w * 0.15
        ink.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: radius).fill()
        let inner = rect.insetBy(dx: line, dy: line)
        side.setFill()
        UIBezierPath(roundedRect: inner, cornerRadius: radius - line).fill()
        let face = CGRect(x: inner.minX, y: inner.minY, width: inner.width, height: inner.height - w * 0.06)
        guard let ctx = UIGraphicsGetCurrentContext() else { return face }
        ctx.saveGState()
        UIBezierPath(roundedRect: face, cornerRadius: radius - line).addClip()
        let colors = [top.cgColor, base.cgColor, base.cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: face.minY), end: CGPoint(x: 0, y: face.maxY), options: [])
        }
        UIColor.white.withAlphaComponent(0.28).setFill()
        UIBezierPath(
            roundedRect: CGRect(x: face.minX + w * 0.1, y: face.minY + w * 0.04, width: face.width - w * 0.2, height: w * 0.08),
            cornerRadius: w * 0.04
        ).fill()
        ctx.restoreGState()
        return face
    }

    nonisolated static func drawSuitFace(_ suit: BirdSuit, rank: Int, points: Int, in rect: CGRect) {
        let w = rect.width
        let face = drawBody(in: rect, top: TilePieceFactory.light(suit), base: TilePieceFactory.color(suit), side: TilePieceFactory.shade(suit))
        let text = String(rank)
        // The corner index: what shows of a card under its neighbour (the left 40%).
        let indexX = face.minX + w * 0.2
        let size = w * (text.count > 1 ? 0.36 : 0.42)
        TilePieceFactory.drawNumeral(
            text, centeredAt: CGPoint(x: indexX, y: face.minY + w * 0.21), size: size, outline: max(w * 0.045, 1.6),
            kern: text.count > 1 ? -size * 0.08 : 0)
        let small = w * 0.24
        UIImage(named: ArtName.Tiles.glyph(suit))?.draw(
            in: CGRect(x: indexX - small / 2, y: face.minY + w * 0.42, width: small, height: small))
        // The toy, large, in the middle.
        let big = w * 0.56
        UIImage(named: ArtName.Tiles.glyph(suit))?.draw(
            in: CGRect(x: face.midX - big / 2 + w * 0.08, y: face.midY - big / 2 + w * 0.1, width: big, height: big))
        if points > 0 { drawSeed(points, in: face, w: w) }
    }

    nonisolated static func drawBirdFace(in rect: CGRect) {
        let w = rect.width
        let face = drawBody(
            in: rect, top: .white, base: UIColor(Color(hex: 0xEAF4FF)), side: UIColor(Color(hex: 0x9CC8FF)))
        // A sky-blue rim inside the face, so the Bird reads as its own card at any size.
        let rim = UIBezierPath(roundedRect: face.insetBy(dx: w * 0.06, dy: w * 0.06), cornerRadius: w * 0.09)
        rim.lineWidth = max(w * 0.035, 1.4)
        UIColor(Palette.sky).setStroke()
        rim.stroke()
        // The corner index: a small Bird.
        let small = w * 0.32
        drawBird(in: CGRect(x: face.minX + w * 0.05, y: face.minY + w * 0.05, width: small, height: small))
        let big = w * 0.74
        drawBird(in: CGRect(x: face.midX - big / 2 + w * 0.04, y: face.midY - big / 2 + w * 0.06, width: big, height: big))
        drawSeed(20, in: face, w: w)
    }

    /// The Bird's art; a plain round songbird until the art is in the catalog.
    nonisolated static func drawBird(in rect: CGRect) {
        if let art = UIImage(named: ArtName.Bird.card) {
            art.draw(in: rect)
            return
        }
        let body = rect.insetBy(dx: rect.width * 0.12, dy: rect.width * 0.12)
        ink.setFill()
        UIBezierPath(ovalIn: body.insetBy(dx: -2, dy: -2)).fill()
        UIColor(Color(hex: 0xFFD21F)).setFill()
        UIBezierPath(ovalIn: body).fill()
        UIColor(Palette.sky).setFill()
        UIBezierPath(ovalIn: CGRect(x: body.minX, y: body.midY, width: body.width * 0.45, height: body.height * 0.3)).fill()
        UIColor(Palette.orange).setFill()
        let beak = UIBezierPath()
        beak.move(to: CGPoint(x: body.maxX - body.width * 0.05, y: body.midY - body.height * 0.12))
        beak.addLine(to: CGPoint(x: body.maxX + body.width * 0.18, y: body.midY - body.height * 0.02))
        beak.addLine(to: CGPoint(x: body.maxX - body.width * 0.05, y: body.midY + body.height * 0.08))
        beak.close()
        beak.fill()
        ink.setFill()
        UIBezierPath(ovalIn: CGRect(x: body.midX + body.width * 0.12, y: body.minY + body.height * 0.25, width: body.width * 0.12, height: body.width * 0.12)).fill()
    }

    /// The gold seed with the card's points, at the face's bottom right.
    nonisolated static func drawSeed(_ points: Int, in face: CGRect, w: CGFloat) {
        let side = w * 0.36
        let seed = CGRect(x: face.maxX - side - w * 0.04, y: face.maxY - side * 1.12 - w * 0.03, width: side, height: side * 1.12)
        ink.setFill()
        UIBezierPath(ovalIn: seed.insetBy(dx: -max(w * 0.03, 1.4), dy: -max(w * 0.03, 1.4))).fill()
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.saveGState()
        UIBezierPath(ovalIn: seed).addClip()
        let colors = [seedLight.cgColor, seedGold.cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: seed.minY), end: CGPoint(x: 0, y: seed.maxY), options: [])
        }
        ctx.restoreGState()
        let text = String(points)
        let size = side * (text.count > 1 ? 0.56 : 0.68)
        TilePieceFactory.drawNumeral(
            text, centeredAt: CGPoint(x: seed.midX, y: seed.midY + side * 0.04), size: size, outline: 0.01, kern: -size * 0.06,
            fill: ink)
    }

    nonisolated static func drawTrumpBadge(_ suit: BirdSuit, in rect: CGRect) {
        let disc = rect.insetBy(dx: 6, dy: 6)
        UIColor(Palette.yellow).withAlphaComponent(0.55).setFill()
        UIBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
        ink.setFill()
        UIBezierPath(ovalIn: disc).fill()
        TilePieceFactory.color(suit).setFill()
        UIBezierPath(ovalIn: disc.insetBy(dx: 5, dy: 5)).fill()
        UIColor.white.withAlphaComponent(0.25).setFill()
        UIBezierPath(ovalIn: CGRect(x: disc.minX + disc.width * 0.22, y: disc.minY + disc.height * 0.12, width: disc.width * 0.56, height: disc.height * 0.26)).fill()
        UIImage(named: ArtName.Tiles.glyph(suit))?.draw(in: disc.insetBy(dx: disc.width * 0.2, dy: disc.width * 0.2))
    }
}
