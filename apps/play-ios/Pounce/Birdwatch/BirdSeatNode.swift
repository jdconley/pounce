import PounceKit
import SpriteKit
import SwiftUI

/// One seat at Birdwatch's window (design §5.2): its cat in the ring (Cat Tower's `CatNode`, with
/// the card count on a mini card back and the glow while it acts), the name tag under it with the
/// team ribbon, the dealer chip, the bid sign the cat holds up, and two private marks: the partner
/// heart (only on the partner's own face-up hand, never on a TV) and "left" for a seat a House Cat
/// took over.
@MainActor
final class BirdSeatNode: SKNode {
    let seat: Seat
    let side: CGFloat
    let cat: CatNode
    private let tag = SKSpriteNode()
    private let ribbon = SKSpriteNode()
    private let dealer = SKSpriteNode()
    let sign = SKSpriteNode()
    private let signText = SKSpriteNode()
    private let heart = SKSpriteNode()
    private(set) var shownSign: BirdTableModel.Sign?
    private(set) var catIndex: Int

    init(seat: Seat, catIndex: Int, side: CGFloat) {
        self.seat = seat
        self.side = side
        self.catIndex = catIndex
        cat = CatNode(cat: catIndex, ringColor: SeatInfo.ringColor(seat), diameter: side)
        super.init()
        addChild(cat)
        tag.zPosition = 8
        tag.position = CGPoint(x: 0, y: -side * 0.5 - 4)
        addChild(tag)
        ribbon.zPosition = 7.5
        addChild(ribbon)
        dealer.zPosition = 9
        dealer.isHidden = true
        addChild(dealer)
        sign.zPosition = 10
        sign.isHidden = true
        signText.zPosition = 1
        sign.addChild(signText)
        addChild(sign)
        heart.zPosition = 11
        heart.isHidden = true
        addChild(heart)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Lays the seat out for this redraw.
    func update(
        name: String, active: Bool, count: Int?, ribbon kind: BirdTableModel.Ribbon?, dealer isDealer: Bool,
        sign next: BirdTableModel.Sign?, partner: Bool, bot: Bool, left: Bool, presence: Presence?, maxTagWidth: CGFloat,
        textScale: CGFloat, edges: (left: CGFloat, right: CGFloat) = (.infinity, .infinity)
    ) {
        cat.setActive(active)
        cat.setCount(count)
        cat.setBadges(bot: bot, skip: false)
        cat.setPresence(bot ? nil : presence)
        let shown = left ? String(localized: "\(name) (left)", comment: "Birdwatch: a seat a House Cat plays for someone who left") : name
        let texture = CardFaceFactory.shared.nameTag(
            shown, maxWidth: maxTagWidth, active: active, size: (CardFaceFactory.nameSize * textScale).rounded())
        tag.texture = texture
        tag.size = texture.size()
        // Centred under the cat, slid inward where the screen's edge is nearer than half the tag.
        let half = tag.size.width / 2
        let slide: CGFloat = half > edges.left ? half - edges.left : (half > edges.right ? edges.right - half : 0)
        tag.position = CGPoint(x: slide, y: -side * 0.5 - tag.size.height * 0.35)
        // The ribbon: a band in the team's colour under the tag, as wide as the tag.
        if let kind {
            ribbon.isHidden = false
            ribbon.color = BirdArt.ribbon(kind)
            ribbon.size = CGSize(width: tag.size.width + 8, height: 7)
            ribbon.position = CGPoint(x: tag.position.x, y: tag.position.y - tag.size.height / 2 - 2)
        } else {
            ribbon.isHidden = true
        }
        dealer.isHidden = !isDealer
        if isDealer {
            let t = BirdArt.dealerChip()
            dealer.texture = t
            dealer.size = CGSize(width: side * 0.34, height: side * 0.34)
            dealer.position = CGPoint(x: -side * 0.42, y: -side * 0.36)
        }
        heart.isHidden = !partner
        if partner {
            heart.texture = BirdArt.partnerHeart()
            heart.size = CGSize(width: side * 0.4, height: side * 0.4)
            heart.position = CGPoint(x: -side * 0.42, y: side * 0.4)
        }
        setSign(next, textScale: textScale)
    }

    private func setSign(_ next: BirdTableModel.Sign?, textScale: CGFloat) {
        shownSign = next
        guard let next else {
            sign.isHidden = true
            cat.zRotation = 0
            return
        }
        sign.isHidden = false
        let (text, fill): (String, UIColor) = switch next {
        case .bid(let n): (String(n), UIColor(Palette.orange))
        case .pass: (String(localized: "Pass", comment: "Birdwatch: a bid sign, the seat passed"), UIColor(Palette.violet).withAlphaComponent(1))
        case .made(let n): (String(localized: "\(n) Made", comment: "Birdwatch: the bid sign after a hand the bid was made"), UIColor(Palette.lime))
        case .missed(let n): (String(localized: "\(n) Missed", comment: "Birdwatch: the bid sign after a hand the bid was missed"), UIColor(Palette.refuse))
        }
        let words = CardFaceFactory.shared.numeral(text, size: (max(15, side * 0.24) * textScale).rounded(), outline: 3)
        signText.texture = words
        signText.size = words.size()
        let board = BirdArt.sign(fill)
        sign.texture = board
        sign.centerRect = BirdArt.sliceCenter
        // `size` includes the scale: back to 1 first, or a sign caught mid-pop grows.
        sign.removeAllActions()
        sign.setScale(1)
        sign.size = CGSize(width: max(words.size().width + 16, side * 0.62), height: words.size().height + 10)
        sign.position = CGPoint(x: side * 0.46, y: side * 0.36)
        // A missed bid: the cat droops.
        if case .missed = next { cat.zRotation = -0.12 } else { cat.zRotation = 0 }
    }

    /// The sign pops up, as a bid lands.
    func popSign(reduceMotion: Bool) {
        guard !sign.isHidden, !reduceMotion else { return }
        sign.setScale(0.3)
        sign.run(.sequence([.scale(to: 1.15, duration: 0.12).eased(.easeOut), .scale(to: 1, duration: 0.1)]))
    }
}

/// Birdwatch's small pieces of table art, drawn once and kept: the window, the sill, signs and
/// chips. 9-slice textures, so each is one sprite at any size.
@MainActor
enum BirdArt {
    private static var cache: [String: SKTexture] = [:]
    /// The stretchable middle of every 9-slice texture here (each is 48 by 48 points, 16-point corners).
    static let sliceCenter = CGRect(x: 0.34, y: 0.34, width: 0.32, height: 0.32)

    static func ribbon(_ kind: BirdTableModel.Ribbon) -> UIColor {
        switch kind {
        case .orange: UIColor(Palette.orange)
        case .teal: UIColor(Palette.teal)
        case .magenta: UIColor(Palette.magenta)
        case .gold: UIColor(Palette.yellow)
        }
    }

    static func ribbonColor(_ kind: BirdTableModel.Ribbon) -> Color {
        switch kind {
        case .orange: Palette.orange
        case .teal: Palette.teal
        case .magenta: Palette.magenta
        case .gold: Palette.yellow
        }
    }

    private static func cached(_ key: String, _ size: CGSize, _ draw: (CGRect) -> Void) -> SKTexture {
        if let t = cache[key] { return t }
        let work = FrameWork("bird.texture.art"); defer { work.end() }
        let t = SKTexture(image: BirdCardFactory.render(size, scale: BirdCardFactory.scale, draw))
        cache[key] = t
        return t
    }

    /// A rounded board: an ink rim around `fill`, lit on top.
    static func sign(_ fill: UIColor) -> SKTexture {
        cached("sign|\(fill.description)", CGSize(width: 48, height: 48)) { rect in
            BirdArt.drawBoard(rect, fill: fill, rim: 3, radius: 14)
        }
    }

    /// The window: sky inside a hot-magenta frame.
    static func window() -> SKTexture {
        cached("window", CGSize(width: 48, height: 48)) { rect in
            UIColor(Palette.ink).setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 16).fill()
            UIColor(Palette.magenta).setFill()
            UIBezierPath(roundedRect: rect.insetBy(dx: 3, dy: 3), cornerRadius: 13).fill()
            let sky = rect.insetBy(dx: 9, dy: 9)
            guard let ctx = UIGraphicsGetCurrentContext() else { return }
            ctx.saveGState()
            UIBezierPath(roundedRect: sky, cornerRadius: 8).addClip()
            let colors = [UIColor(Color(hex: 0x7FD8FF)).cgColor, UIColor(Palette.sky).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: sky.minY), end: CGPoint(x: 0, y: sky.maxY), options: [])
            }
            ctx.restoreGState()
        }
    }

    /// The sill: a deep violet ledge where the trick lands.
    static func sill() -> SKTexture {
        cached("sill", CGSize(width: 48, height: 48)) { rect in
            BirdArt.drawBoard(rect, fill: UIColor(Palette.night).withAlphaComponent(0.78), rim: 3, radius: 16)
        }
    }

    /// A chip on the score strip, in a side's colour (or violet).
    static func chip(_ fill: UIColor, lit: Bool) -> SKTexture {
        cached("chip|\(fill.description)|\(lit)", CGSize(width: 48, height: 48)) { rect in
            BirdArt.drawBoard(rect, fill: fill, rim: lit ? 4 : 3, radius: 16, glow: lit)
        }
    }

    static func dealerChip() -> SKTexture {
        let back = CardFaceFactory.backImage
        return cached("dealer", CGSize(width: 40, height: 40)) { rect in
            UIColor(Palette.ink).setFill()
            UIBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            UIColor.white.setFill()
            UIBezierPath(ovalIn: rect.insetBy(dx: 4, dy: 4)).fill()
            back.draw(in: rect.insetBy(dx: 10, dy: 8))
        }
    }

    /// The partner mark: a gold heart.
    static func partnerHeart() -> SKTexture {
        cached("heart", CGSize(width: 40, height: 40)) { rect in
            let path = heartPath(in: rect.insetBy(dx: 3, dy: 4))
            UIColor(Palette.ink).setFill()
            heartPath(in: rect.insetBy(dx: 1, dy: 2)).fill()
            UIColor(Palette.yellow).setFill()
            path.fill()
        }
    }

    nonisolated static func heartPath(in r: CGRect) -> UIBezierPath {
        let p = UIBezierPath()
        p.move(to: CGPoint(x: r.midX, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.3),
                   controlPoint1: CGPoint(x: r.midX - r.width * 0.1, y: r.maxY - r.height * 0.2),
                   controlPoint2: CGPoint(x: r.minX, y: r.midY))
        p.addArc(withCenter: CGPoint(x: r.minX + r.width * 0.25, y: r.minY + r.height * 0.3), radius: r.width * 0.25,
                 startAngle: .pi, endAngle: 0, clockwise: true)
        p.addArc(withCenter: CGPoint(x: r.maxX - r.width * 0.25, y: r.minY + r.height * 0.3), radius: r.width * 0.25,
                 startAngle: .pi, endAngle: 0, clockwise: true)
        p.addCurve(to: CGPoint(x: r.midX, y: r.maxY),
                   controlPoint1: CGPoint(x: r.maxX, y: r.midY),
                   controlPoint2: CGPoint(x: r.midX + r.width * 0.1, y: r.maxY - r.height * 0.2))
        p.close()
        return p
    }

    /// A card's glow while it waits to be put back, or came from the feeder.
    static func cardGlow() -> SKTexture {
        cached("cardglow", CGSize(width: 48, height: 48)) { rect in
            UIColor(Palette.yellow).setFill()
            UIBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), cornerRadius: 12).fill()
        }
    }

    nonisolated static func drawBoard(_ rect: CGRect, fill: UIColor, rim: CGFloat, radius: CGFloat, glow: Bool = false) {
        UIColor(Palette.ink).setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: radius).fill()
        let inner = rect.insetBy(dx: rim, dy: rim)
        fill.setFill()
        UIBezierPath(roundedRect: inner, cornerRadius: radius - rim).fill()
        UIColor.white.withAlphaComponent(glow ? 0.4 : 0.22).setFill()
        UIBezierPath(roundedRect: CGRect(x: inner.minX + 6, y: inner.minY + 3, width: inner.width - 12, height: 6), cornerRadius: 3).fill()
    }
}
