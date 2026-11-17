import PounceKit
import SpriteKit
import SwiftUI
import UIKit

// What only a TV's table draws (a scene whose store is a screen, `RoomStore.isScreen`), for both
// games: the turn banner along the bottom, a seat's score under its name, and the big moment when
// someone lays down. The web's TV page (apps/play-web/src/ui/tv/tv-table.tsx) is the reference for
// what each shows and says. Everything is sized in the TV's plan points (`TableLayout.tvUnit`), so
// 4K draws exactly twice 1080p, and nothing that matters is under 28 points at 1080p.

extension TVInsets {
    /// A view's safe area as the TV's table keeps it clear: tvOS's TV-safe area (60/80 points).
    init(_ insets: UIEdgeInsets) {
        self.init(top: insets.top, left: insets.left, bottom: insets.bottom, right: insets.right)
    }
}

/// The TV's own words, exactly as the web's TV page says them.
enum TVWords {
    /// The turn banner: "<Name>'s turn".
    static func turn(_ name: String) -> String {
        String(localized: "\(name)'s turn", comment: "TV banner: whose turn it is")
    }

    /// The name's part of `turn`: what comes after it.
    static var turnTail: String { String(localized: "'s turn", comment: "TV banner, after the name: whose turn it is") }

    static var reconnecting: String { String(localized: "Reconnecting", comment: "TV banner: the TV lost the table and is finding it again") }

    /// Someone laid their level down: "<Name> laid down", "Level 4".
    static func laidDown(_ name: String) -> String {
        String(localized: "\(name) laid down", comment: "TV, big over the table: a player laid their level down")
    }

    static func level(_ level: Int) -> String {
        String(localized: "Level \(level)", comment: "TV, under '<Name> laid down': the level they laid down")
    }
}

/// The TV's banners and moments, drawn once per name, colour and size and kept. A table warms every
/// seat's banner off the main thread as it opens (`warm`), so a turn changing never stops a frame
/// to draw one; one not ready yet is drawn on the spot (a few milliseconds, once).
@MainActor
final class TVArt {
    static let shared = TVArt()

    private var textures: [String: SKTexture] = [:]
    private var drawing: Set<String> = []

    /// What a picture is: the words, their colour and the room they have, at a plan unit.
    enum Piece: Hashable, Sendable {
        /// The turn banner's pill: the name cut to fit `maxWidth` points, then "'s turn".
        case banner(name: String, ring: Int, unit: CGFloat, minWidth: CGFloat, maxWidth: CGFloat)
        /// The banner while the TV has lost the table.
        case reconnecting(unit: CGFloat, minWidth: CGFloat)
        /// A moment's title on a pill in the seat's colour.
        case title(String, ring: Int, unit: CGFloat, maxWidth: CGFloat)
        /// Outlined words, no pill (a moment's "Level 4", a seat's score).
        case words(String, size: CGFloat, yellow: Bool)

        /// Spelled out: a string of the case itself is Swift's reflection, which costs a frame the
        /// first time it runs.
        nonisolated var key: String {
            switch self {
            case .banner(let name, let ring, let unit, let minWidth, let maxWidth):
                "banner|\(name)|\(ring)|\(Double(unit))|\(Double(minWidth))|\(Double(maxWidth))"
            case .reconnecting(let unit, let minWidth): "lost|\(Double(unit))|\(Double(minWidth))"
            case .title(let text, let ring, let unit, let maxWidth): "title|\(text)|\(ring)|\(Double(unit))|\(Double(maxWidth))"
            case .words(let text, let size, let yellow): "words|\(text)|\(Double(size))|\(yellow)"
            }
        }
    }

    func texture(_ piece: Piece) -> SKTexture {
        let key = piece.key
        if let cached = textures[key] { return cached }
        let work = FrameWork("tv.art"); defer { work.end() }
        let t = SKTexture(image: Self.image(piece, scale: Self.scale))
        textures[key] = t
        return t
    }

    /// Draws `pieces` off the main thread (`docs/main-thread.md`) for the next time they show.
    func warm(_ pieces: [Piece]) {
        let missing = Array(Set(pieces.filter { textures[$0.key] == nil && !drawing.contains($0.key) }))
        guard !missing.isEmpty else { return }
        missing.forEach { drawing.insert($0.key) }
        let scale = Self.scale
        Task {
            for (key, texture) in await Self.draw(missing, scale: scale) {
                drawing.remove(key)
                if textures[key] == nil { textures[key] = texture }
            }
        }
    }

    @concurrent
    private static func draw(_ pieces: [Piece], scale: CGFloat) async -> sending [(String, SKTexture)] {
        let made = pieces.map { ($0.key, SKTexture(image: image($0, scale: scale))) }
        await SKTexture.preload(made.map(\.1))
        return made
    }

    /// The display's pixels per point (2 at 4K), so words stay sharp.
    private static var scale: CGFloat { max(UITraitCollection.current.displayScale, 1) }

    // MARK: drawing (safe off the main thread)

    nonisolated private static func font(_ size: CGFloat) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: .black)
        return base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base
    }

    nonisolated private static func width(_ text: String, _ size: CGFloat) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font(size)]).width)
    }

    /// `text`, or as much of it as fits `width` and an ellipsis.
    nonisolated private static func cut(_ text: String, size: CGFloat, toFit room: CGFloat) -> String {
        if width(text, size) <= room { return text }
        var cut = text
        while !cut.isEmpty {
            cut.removeLast()
            let trimmed = cut.trimmingCharacters(in: .whitespaces)
            if width(trimmed + "…", size) <= room { return trimmed + "…" }
        }
        return "…"
    }

    /// White words with an ink outline that grows outward (the app's lettering).
    nonisolated private static func outlined(_ text: String, at origin: CGPoint, size: CGFloat, fill: UIColor) {
        let outline = max(size * 0.09, 2)
        let ink = UIColor(Palette.ink)
        (text as NSString).draw(at: origin, withAttributes: [
            .font: font(size), .strokeColor: ink, .strokeWidth: outline * 2 / size * 100,
        ])
        (text as NSString).draw(at: origin, withAttributes: [.font: font(size), .foregroundColor: fill])
    }

    nonisolated private static func ring(_ index: Int) -> UIColor { UIColor(SeatInfo.ringColor(index)) }

    /// A pill in a seat's colour: a light top fading into the colour, an ink outline, a yellow ring
    /// round that (`halo`), a hard ink shadow under it and a gloss along the top.
    nonisolated private static func pill(_ r: CGRect, color: UIColor, line: CGFloat, halo: CGFloat, drop: CGFloat, in ctx: CGContext) {
        let radius = r.height / 2
        let ink = UIColor(Palette.ink)
        ink.setFill()
        UIBezierPath(roundedRect: r.insetBy(dx: -halo, dy: -halo).offsetBy(dx: 0, dy: drop), cornerRadius: radius + halo).fill()
        if halo > 0 {
            UIColor(Palette.yellow).setFill()
            UIBezierPath(roundedRect: r.insetBy(dx: -halo, dy: -halo), cornerRadius: radius + halo).fill()
        }
        ink.setFill()
        UIBezierPath(roundedRect: r, cornerRadius: radius).fill()
        let inner = r.insetBy(dx: line, dy: line)
        ctx.saveGState()
        UIBezierPath(roundedRect: inner, cornerRadius: inner.height / 2).addClip()
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let light = UIColor(hue: h, saturation: s * 0.45, brightness: min(b * 0.55 + 0.45, 1), alpha: 1)
        let colors = [light.cgColor, color.cgColor, color.cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.6, 1]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: inner.minY), end: CGPoint(x: 0, y: inner.maxY), options: [])
        }
        UIColor.white.withAlphaComponent(0.45).setFill()
        UIBezierPath(
            roundedRect: CGRect(x: inner.minX + radius * 0.6, y: inner.minY + line * 0.4, width: inner.width - radius * 1.2, height: line),
            cornerRadius: line / 2
        ).fill()
        ctx.restoreGState()
    }

    nonisolated private static func image(_ piece: Piece, scale: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = scale
        switch piece {
        case .banner(let name, let index, let u, let minWidth, let maxWidth):
            // The cat leans in on the left (drawn over it by `TVBanner`), the words after it.
            let size = 54 * u, line = 6 * u, halo = 6 * u, drop = 12 * u, height = TVBanner.height * u
            let lead = 150 * u, trail = 36 * u
            let tail = TVWords.turnTail
            let room = maxWidth - 2 * halo - lead - trail - width(tail, size)
            let shown = cut(name, size: size, toFit: room)
            let words = shown + tail
            let w = min(max(minWidth - 2 * halo, lead + width(words, size) + trail), maxWidth - 2 * halo)
            let canvas = CGSize(width: w + 2 * halo, height: height + 2 * halo + drop)
            return UIGraphicsImageRenderer(size: canvas, format: format).image { ctx in
                let r = CGRect(x: halo, y: halo, width: w, height: height)
                pill(r, color: ring(index), line: line, halo: halo, drop: drop, in: ctx.cgContext)
                let fontHeight = font(size).lineHeight
                outlined(words, at: CGPoint(x: r.minX + lead, y: r.midY - fontHeight / 2), size: size, fill: .white)
            }
        case .reconnecting(let u, let minWidth):
            let size = 48 * u, height = TVBanner.height * u, drop = 10 * u, dot = 24 * u, pad = 36 * u, gap = 20 * u
            let words = TVWords.reconnecting
            let w = max(minWidth, pad + dot + gap + width(words, size) + pad)
            let canvas = CGSize(width: w, height: height + drop)
            return UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
                let r = CGRect(x: 0, y: 0, width: w, height: height)
                UIColor(Palette.ink).withAlphaComponent(0.6).setFill()
                UIBezierPath(roundedRect: r.offsetBy(dx: 0, dy: drop), cornerRadius: height / 2).fill()
                UIColor(Palette.ink).setFill()
                UIBezierPath(roundedRect: r, cornerRadius: height / 2).fill()
                let total = dot + gap + width(words, size)
                let x = (w - total) / 2
                UIColor(Palette.refuse).setFill()
                UIBezierPath(ovalIn: CGRect(x: x, y: r.midY - dot / 2, width: dot, height: dot)).fill()
                let attrs: [NSAttributedString.Key: Any] = [.font: font(size), .foregroundColor: UIColor.white]
                (words as NSString).draw(at: CGPoint(x: x + dot + gap, y: r.midY - font(size).lineHeight / 2), withAttributes: attrs)
            }
        case .title(let text, let index, let u, let maxWidth):
            let size = 84 * u, line = 6 * u, drop = 12 * u, padX = 56 * u
            let height = ceil(font(size).lineHeight + 26 * u)
            let shown = cut(text, size: size, toFit: maxWidth - 2 * padX)
            let w = width(shown, size) + 2 * padX
            let canvas = CGSize(width: w, height: height + drop)
            return UIGraphicsImageRenderer(size: canvas, format: format).image { ctx in
                let r = CGRect(x: 0, y: 0, width: w, height: height)
                pill(r, color: ring(index), line: line, halo: 0, drop: drop, in: ctx.cgContext)
                outlined(shown, at: CGPoint(x: padX, y: r.midY - font(size).lineHeight / 2), size: size, fill: .white)
            }
        case .words(let text, let size, let yellow):
            let outline = max(size * 0.09, 2)
            let canvas = CGSize(width: width(text, size) + 2 * outline + 2, height: ceil(font(size).lineHeight + 2 * outline))
            return UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
                outlined(text, at: CGPoint(x: outline + 1, y: outline), size: size, fill: yellow ? UIColor(Palette.yellow) : .white)
            }
        }
    }
}

/// "<Name>'s turn", big along the bottom of a TV's table in the seat's colour, with their cat
/// leaning in. It pops as each turn starts; between rounds and after the game it is gone. While
/// the TV has lost the table it says "Reconnecting" over the last table shown.
@MainActor
final class TVBanner: SKNode {
    /// The banner's height (plan points).
    nonisolated static let height: CGFloat = 88

    private let pill = SKSpriteNode()
    private let cat = SKSpriteNode()
    /// What shows now: a seat's turn (its seat, name and cat), "Reconnecting", or nothing.
    private(set) var shown: Shown?

    enum Shown: Equatable {
        case turn(seat: Seat, name: String, cat: Int)
        case reconnecting
    }

    override init() {
        super.init()
        pill.zPosition = 0
        cat.zPosition = 1
        addChild(pill)
        addChild(cat)
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not used") }

    /// What a turn banner shows, for `warm`.
    static func piece(name: String, seat: Seat, banner: CGRect, room: CGRect, unit: CGFloat) -> TVArt.Piece {
        .banner(name: name, ring: seat, unit: unit, minWidth: banner.width + 12 * unit, maxWidth: room.width + 12 * unit)
    }

    /// Shows `next` centred on `banner` (no wider than `room`); `pop` springs it in, as a new turn
    /// does. Returns the motion to run, if any.
    func show(_ next: Shown?, banner: CGRect, room: CGRect, unit: CGFloat, pop: Bool, reduceMotion: Bool) -> (SKAction, SKNode)? {
        let changed = next != shown
        shown = next
        guard let next, banner.width > 0 else {
            isHidden = true
            return nil
        }
        isHidden = false
        position = CGPoint(x: banner.midX, y: banner.midY)
        let texture: SKTexture
        switch next {
        case .turn(let seat, let name, let catIndex):
            texture = TVArt.shared.texture(Self.piece(name: name, seat: seat, banner: banner, room: room, unit: unit))
            let side = 132 * unit
            cat.isHidden = false
            cat.texture = TableArt.cat(catIndex, .awake)
            cat.size = CGSize(width: side, height: side)
        case .reconnecting:
            texture = TVArt.shared.texture(.reconnecting(unit: unit, minWidth: banner.width))
            cat.isHidden = true
        }
        pill.texture = texture
        pill.size = texture.size()
        // The texture holds the halo and the shadow below the pill: line the pill itself up on the
        // banner's place.
        let halo: CGFloat = next == .reconnecting ? 0 : 6 * unit
        let drop = pill.size.height - Self.height * unit - 2 * halo
        pill.position = CGPoint(x: 0, y: -drop / 2)
        // The cat sits on the pill's left end, its feet a little below the pill's bottom edge.
        cat.position = CGPoint(x: -pill.size.width / 2 + halo + 6 * unit + cat.size.width / 2, y: -Self.height * unit / 2 + cat.size.height / 2 - 4 * unit)
        guard pop || changed, !reduceMotion else {
            setScale(1)
            return nil
        }
        guard pop else { return nil }
        setScale(0.7)
        return (.sequence([
            .scale(to: 1.06, duration: 0.25).eased(.easeOut),
            .scale(to: 1, duration: 0.17).eased(.easeInEaseOut),
        ]), self)
    }
}

/// A player laying down, big in the middle of the TV's table for a moment: their cat celebrating on
/// a turning sunburst, "<Name> laid down" on a pill in their colour and "Level 4" under it. It fades
/// in and out as one layer (`FadeGroup`), over the table, and holds nothing up: play goes on under it.
@MainActor
enum TVMoment {
    static let seconds: TimeInterval = 2.4

    /// The moment's node, centred on `center`, and the motion that shows it and fades it away
    /// (the caller removes it after).
    /// The moment's title and its words under it, as `TVArt` draws them.
    static func title(name: String, seat: Seat, unit u: CGFloat) -> TVArt.Piece {
        .title(TVWords.laidDown(name), ring: seat, unit: u, maxWidth: 1500 * u)
    }

    static func level(_ level: Int, unit u: CGFloat) -> TVArt.Piece {
        .words(TVWords.level(level), size: (60 * u).rounded(), yellow: true)
    }

    static func make(name: String, seat: Seat, cat: Int, level: Int, center: CGPoint, unit u: CGFloat, reduceMotion: Bool) -> (FadeGroup, SKAction) {
        let group = FadeGroup()
        group.position = center
        let burst = SKSpriteNode(texture: TableArt.table(ArtName.sunburst), size: CGSize(width: 1100 * u, height: 1100 * u))
        burst.alpha = 0.7  // fade-ok: the sunburst alone at the back, nothing under it in the group
        burst.zPosition = 0
        group.addChild(burst)
        let face = SKSpriteNode(texture: TableArt.cat(cat, .celebrate), size: CGSize(width: 300 * u, height: 300 * u))
        face.position = CGPoint(x: 0, y: 120 * u)
        face.zPosition = 1
        group.addChild(face)
        let titleTexture = TVArt.shared.texture(Self.title(name: name, seat: seat, unit: u))
        let title = SKSpriteNode(texture: titleTexture, size: titleTexture.size())
        title.position = CGPoint(x: 0, y: -50 * u)
        title.zPosition = 2
        group.addChild(title)
        let subTexture = TVArt.shared.texture(Self.level(level, unit: u))
        let sub = SKSpriteNode(texture: subTexture, size: subTexture.size())
        sub.position = CGPoint(x: 0, y: title.position.y - title.size.height / 2 - 18 * u - sub.size.height / 2)
        sub.zPosition = 3
        group.addChild(sub)

        group.alpha = 0
        let t = seconds
        // Through the setter, so the group flattens while it is see-through.
        // fade-ok: the moment is a FadeGroup, faded whole
        let fade = SKAction.customAction(withDuration: t) { node, elapsed in
            let p = elapsed / CGFloat(t)
            (node as? FadeGroup)?.alpha = p < 0.08 ? p / 0.08 : p > 0.82 ? max((1 - p) / 0.18, 0) : 1
        }
        if !reduceMotion {
            burst.run(.rotate(byAngle: -.pi * 2 * t / 12, duration: t))
            for (i, node) in [face, title, sub].enumerated() {
                node.setScale(0.7)
                node.run(.sequence([
                    .wait(forDuration: Double(i) * 0.12),
                    .scale(to: 1.06, duration: 0.31).eased(.easeOut),
                    .scale(to: 1, duration: 0.21).eased(.easeInEaseOut),
                ]))
            }
        }
        return (group, fade)
    }
}

/// A TV seat's words under its cat: the name in 34-point type (never under 28, cut short past
/// that) as wide as the seat, and the score under it.
struct TVSeatWords {
    let nameWidth: CGFloat
    let nameSize: CGFloat
    let nameMinimum: CGFloat
    let scoreSize: CGFloat
    let linkSize: CGFloat
    let unit: CGFloat

    init(_ seat: CGRect, unit u: CGFloat) {
        unit = u
        nameWidth = max(seat.width - 12 * u, 1)
        nameSize = (34 * u).rounded()
        nameMinimum = (28 * u).rounded()
        scoreSize = (34 * u).rounded()
        linkSize = (28 * u).rounded()
    }

    /// Puts `score` (nil hides it) on `node`, just under `tag`.
    @MainActor
    func place(score: Int?, on node: SKSpriteNode, under tag: SKSpriteNode) {
        guard let score else {
            node.isHidden = true
            return
        }
        node.isHidden = false
        let texture = TVArt.shared.texture(.words(String(score), size: scoreSize, yellow: false))
        if node.texture !== texture {
            node.texture = texture
            node.size = texture.size()
        }
        node.position = CGPoint(x: tag.position.x, y: tag.position.y - tag.size.height / 2 - node.size.height / 2 + 2 * unit)
    }
}
