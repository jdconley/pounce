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
    /// The turn banner: "<Name>'s turn". The banner's only source of its words.
    nonisolated static func turn(_ name: String) -> String {
        String(localized: "\(name)'s turn", comment: "TV banner: whose turn it is")
    }

    nonisolated static var reconnecting: String { String(localized: "Reconnecting", comment: "TV banner: the TV lost the table and is finding it again") }

    /// Someone laid their level down: "<Name> laid down", "Level 4".
    nonisolated static func laidDown(_ name: String) -> String {
        String(localized: "\(name) laid down", comment: "TV, big over the table: a player laid their level down")
    }

    nonisolated static func level(_ level: Int) -> String {
        String(localized: "Level \(level)", comment: "TV, under '<Name> laid down': the level they laid down")
    }
}

/// The TV's banners, moments and scores, drawn once per words, colour and size and kept. Every
/// picture is drawn off the main thread (`docs/main-thread.md`): a table warms what it will show as
/// it opens (`warm`), and anything not ready yet is handed over when it is (`whenReady`), never
/// drawn on the spot.
@MainActor
final class TVArt {
    static let shared = TVArt()

    private var textures: [String: SKTexture] = [:]
    /// Pictures being drawn, and who is waiting for each.
    private var waiting: [String: [() -> Void]] = [:]

    /// The display's pixels per point (2 at 4K), from the table's view (`TableScene`,
    /// `TilesScene` set it as they're shown), so words stay sharp. A change drops what was drawn.
    var scale: CGFloat = 1 {
        didSet {
            guard scale != oldValue else { return }
            textures.removeAll()
        }
    }

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

    /// The picture if it is drawn already.
    func ready(_ piece: Piece) -> SKTexture? { textures[piece.key] }

    /// Calls `then` with the pictures: at once when every one is drawn, else once the missing ones
    /// are, off the main thread.
    func whenReady(_ pieces: [Piece], _ then: @escaping ([SKTexture]) -> Void) {
        let deliver = { [weak self] in
            guard let self else { return }
            let made = pieces.compactMap { self.textures[$0.key] }
            if made.count == pieces.count { then(made) }
        }
        let missing = pieces.filter { textures[$0.key] == nil }
        guard !missing.isEmpty else { return deliver() }
        // Called back once the last missing picture lands.
        var left = Set(missing.map(\.key))
        for piece in missing {
            let key = piece.key
            waiting[key, default: []].append {
                left.remove(key)
                if left.isEmpty { deliver() }
            }
        }
        warm(missing)
    }

    /// Draws `pieces` off the main thread for the next time they show.
    func warm(_ pieces: [Piece]) {
        var seen: Set<String> = []
        let missing = pieces.filter { textures[$0.key] == nil && !drawingKeys.contains($0.key) && seen.insert($0.key).inserted }
        guard !missing.isEmpty else { return }
        missing.forEach { drawingKeys.insert($0.key) }
        let scale = scale
        Task {
            let made = await Self.draw(missing, scale: scale)
            for (key, texture) in made {
                drawingKeys.remove(key)
                if textures[key] == nil, scale == self.scale { textures[key] = texture }
            }
            for (key, _) in made {
                let calls = waiting.removeValue(forKey: key) ?? []
                calls.forEach { $0() }
            }
        }
    }

    private var drawingKeys: Set<String> = []

    @concurrent
    private static func draw(_ pieces: [Piece], scale: CGFloat) async -> sending [(String, SKTexture)] {
        let made = pieces.map { ($0.key, SKTexture(image: image($0, scale: scale))) }
        await SKTexture.preload(made.map(\.1))
        return made
    }

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
            // The words around the name, measured with an empty one.
            let room = maxWidth - 2 * halo - lead - trail - width(TVWords.turn(""), size)
            let words = TVWords.turn(cut(name, size: size, toFit: room))
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
    /// does. Returns the motion to run, if any. The banner's picture is drawn off the main thread:
    /// one not drawn yet shows the moment it is (a table warms them all as it opens).
    func show(_ next: Shown?, banner: CGRect, room: CGRect, unit: CGFloat, pop: Bool, reduceMotion: Bool) -> (SKAction, SKNode)? {
        shown = next
        guard let next, banner.width > 0 else {
            isHidden = true
            return nil
        }
        position = CGPoint(x: banner.midX, y: banner.midY)
        let piece: TVArt.Piece
        switch next {
        case .turn(let seat, let name, let catIndex):
            piece = Self.piece(name: name, seat: seat, banner: banner, room: room, unit: unit)
            let side = 132 * unit
            cat.texture = TableArt.cat(catIndex, .awake)
            cat.size = CGSize(width: side, height: side)
        case .reconnecting:
            piece = Self.lost(banner: banner, unit: unit)
        }
        TVArt.shared.whenReady([piece]) { [weak self] textures in
            // Still what the banner shows (nothing newer asked for since).
            guard let self, self.shown == next, let texture = textures.first else { return }
            self.apply(texture, next, unit: unit)
            self.drawLanded()
        }
        guard pop, !reduceMotion else { return nil }
        setScale(0.7)
        return (.sequence([
            .scale(to: 1.06, duration: 0.25).eased(.easeOut),
            .scale(to: 1, duration: 0.17).eased(.easeInEaseOut),
        ]), self)
    }

    /// "Reconnecting", for `warm`.
    static func lost(banner: CGRect, unit: CGFloat) -> TVArt.Piece { .reconnecting(unit: unit, minWidth: banner.width) }

    private func apply(_ texture: SKTexture, _ shown: Shown, unit: CGFloat) {
        isHidden = false
        pill.texture = texture
        pill.size = texture.size()
        cat.isHidden = shown == .reconnecting
        // The texture holds the halo and the shadow below the pill: line the pill itself up on the
        // banner's place.
        let halo: CGFloat = shown == .reconnecting ? 0 : 6 * unit
        let drop = pill.size.height - Self.height * unit - 2 * halo
        pill.position = CGPoint(x: 0, y: -drop / 2)
        // The cat sits on the pill's left end, its feet a little below the pill's bottom edge.
        cat.position = CGPoint(
            x: -pill.size.width / 2 + halo + 6 * unit + cat.size.width / 2, y: -Self.height * unit / 2 + cat.size.height / 2 - 4 * unit)
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

    /// `titleTexture` and `subTexture`: `title` and `level`, drawn (`TVArt.whenReady`).
    static func make(
        titleTexture: SKTexture, subTexture: SKTexture, cat: Int, center: CGPoint, unit u: CGFloat, reduceMotion: Bool
    ) -> (FadeGroup, SKAction) {
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
        let title = SKSpriteNode(texture: titleTexture, size: titleTexture.size())
        title.position = CGPoint(x: 0, y: -50 * u)
        title.zPosition = 2
        group.addChild(title)
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

    /// A score's picture, for `warm`.
    func piece(_ score: Int) -> TVArt.Piece { .words(String(score), size: scoreSize, yellow: false) }

    /// Puts `score` (nil hides it) on `node`, just under `tag`. A score whose picture isn't drawn yet
    /// shows the moment it is (the last one stays till then).
    @MainActor
    func place(score: Int?, on node: SKSpriteNode, under tag: SKSpriteNode) {
        guard let score else {
            node.isHidden = true
            node.name = nil
            return
        }
        let want = "score|\(score)"
        node.name = want
        let below = CGPoint(x: tag.position.x, y: tag.position.y - tag.size.height / 2)
        let unit = unit
        TVArt.shared.whenReady([piece(score)]) { [weak node] textures in
            guard let node, node.name == want, let texture = textures.first else { return }
            node.isHidden = false
            if node.texture !== texture {
                node.texture = texture
                node.size = texture.size()
            }
            node.position = CGPoint(x: below.x, y: below.y - node.size.height / 2 + 2 * unit)
            node.drawLanded()
        }
    }
}

extension SKNode {
    /// A picture drawn off the main thread (`TVArt.whenReady`) landed on this node: the table draws
    /// a frame for it, even if it went idle and paused its view while the picture was drawn.
    @MainActor
    func drawLanded() {
        switch scene {
        case let table as TableScene: table.director.wake()
        case let tiles as TilesScene: tiles.director.wake()
        default: break
        }
    }
}
