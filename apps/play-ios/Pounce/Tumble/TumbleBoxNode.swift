import PounceKit
import SpriteKit
import UIKit

/// One toy box at any cell size (spec §3, §5.2, §7): the toy chest with its cat peeking over the
/// rim, the settled toys and hairball rows, the falling toy, the paw-print landing outline, the
/// trick badges on cells, and the words over it ("Out", "Reconnecting"). The settled cells live in
/// one rasterized layer, re-made only when the box's cells or tricks change (a set-down or a
/// hit); only the falling toy and effects are live nodes. The phone's own box, the minis and the
/// TV all use it.
@MainActor
final class TumbleBoxNode: SKNode {
    enum Z: CGFloat { case cat = -1, frame = 0, well = 1, settled = 2, landing = 3, toy = 4, fx = 8, words = 10 }

    let seat: Int
    private(set) var rect: CGRect = .zero
    private(set) var cell: CGFloat = 20
    private let body = SKNode()
    private let frameNode = SKSpriteNode()
    private let well = SKSpriteNode()
    private let settled = SKEffectNode()
    private var settledSprites: [SKSpriteNode] = []
    private let landingNode = SKNode()
    private var landingSprites: [SKSpriteNode] = []
    private let toyNode = SKNode()
    private var toySprites: [SKSpriteNode] = []
    let cat = SKSpriteNode()
    private let nextNode = SKNode()
    private var nextSprites: [SKSpriteNode] = []
    private let words = SKSpriteNode()
    private let zz = SKSpriteNode()
    private let nameNode = SKSpriteNode()
    private let winsNode = SKSpriteNode()
    private let catnipGlow = SKSpriteNode()
    private var drawn: (cells: [Int], tricks: [Int])?
    private var catIndex = 0
    private(set) var pose: CatPose = .idle
    private(set) var tipped = false
    private var shownWords: String?
    /// Small: a mini at a phone's side. Names under it, no next toy.
    private(set) var mini = false
    /// The next toy on the cat's paw (the phone's own box).
    var showsNext = false

    init(seat: Int) {
        self.seat = seat
        super.init()
        addChild(body)
        frameNode.zPosition = Z.frame.rawValue
        frameNode.anchorPoint = .zero
        body.addChild(frameNode)
        well.zPosition = Z.well.rawValue
        well.anchorPoint = .zero
        body.addChild(well)
        settled.shouldRasterize = true
        settled.shouldEnableEffects = true
        settled.zPosition = Z.settled.rawValue
        body.addChild(settled)
        landingNode.zPosition = Z.landing.rawValue
        body.addChild(landingNode)
        toyNode.zPosition = Z.toy.rawValue
        body.addChild(toyNode)
        cat.zPosition = Z.cat.rawValue
        body.addChild(cat)
        nextNode.zPosition = Z.toy.rawValue
        body.addChild(nextNode)
        catnipGlow.zPosition = Z.well.rawValue + 0.5
        catnipGlow.color = UIColor(Palette.lime)
        catnipGlow.colorBlendFactor = 1
        catnipGlow.alpha = 0
        catnipGlow.anchorPoint = .zero
        body.addChild(catnipGlow)
        words.zPosition = Z.words.rawValue
        words.isHidden = true
        body.addChild(words)
        zz.zPosition = Z.words.rawValue
        zz.isHidden = true
        body.addChild(zz)
        nameNode.zPosition = Z.words.rawValue
        nameNode.anchorPoint = CGPoint(x: 0, y: 0.5)
        addChild(nameNode)
        winsNode.zPosition = Z.words.rawValue
        winsNode.anchorPoint = CGPoint(x: 1, y: 0.5)
        addChild(winsNode)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: layout

    /// Lays the box out over `rect` (its 12 by 18 cells); `label` is the height of the name strip under a mini.
    func place(_ rect: CGRect, label: CGFloat = 0, mini: Bool) {
        let c = rect.width / CGFloat(TumbleLayout.columns)
        let moved = rect != self.rect || mini != self.mini
        self.rect = rect
        cell = c
        self.mini = mini
        position = rect.origin
        guard moved else { return }
        let art = TumbleArt.shared
        // The chest: walls a fixed share of a cell, so a mini's walls are thin too.
        let wall = max(c * 0.55, 3)
        let k = wall / 16
        frameNode.texture = art.boxTexture()
        frameNode.centerRect = TumbleArt.boxSlice
        frameNode.setScale(k)
        frameNode.size = CGSize(width: (rect.width + wall * 2) / k, height: (rect.height + wall * 2.2) / k)
        frameNode.position = CGPoint(x: -wall, y: -wall)
        well.texture = art.wellTexture()
        well.size = rect.size
        well.position = .zero
        catnipGlow.size = rect.size
        let catSide = mini ? max(c * 5, 16) : c * 4.2
        cat.size = CGSize(width: catSide, height: catSide)
        // Peeking over the rim at the right, so the next toy sits on its paw at the left.
        cat.position = CGPoint(x: rect.width - catSide * 0.62, y: rect.height + wall + catSide * 0.18)
        drawn = nil
        let fontSize = max(min(c * 1.6, 28), 11)
        words.zPosition = Z.words.rawValue
        words.position = CGPoint(x: rect.width / 2, y: rect.height / 2)
        if let shownWords { setWords(shownWords, size: fontSize) }
        zz.position = CGPoint(x: rect.width * 0.25, y: rect.height + wall + c)
        nameNode.position = CGPoint(x: 0, y: -wall - label / 2)
        winsNode.position = CGPoint(x: rect.width, y: -wall - label / 2)
        layoutNext()
    }

    private func layoutNext() {
        nextNode.position = CGPoint(x: cell * 0.5, y: rect.height + max(cell * 0.55, 3) + cell * 0.7)
    }

    // MARK: the settled cells

    /// Shows the box's settled toys, junk and tricks, re-making the layer only when they changed.
    func show(_ box: TumbleBox) {
        if let drawn, drawn.cells == box.cells, drawn.tricks == box.tricks { return }
        drawn = (box.cells, box.tricks)
        let art = TumbleArt.shared
        var used = 0
        func sprite() -> SKSpriteNode {
            if used < settledSprites.count {
                let s = settledSprites[used]
                used += 1
                return s
            }
            let s = SKSpriteNode()
            settled.addChild(s)
            settledSprites.append(s)
            used += 1
            return s
        }
        let c = cell
        // Junk first, under the toys, so the fur's fluff tucks behind them.
        for pass in 0..<3 {
            for y in 0..<TumbleLayout.rows {
                for x in 0..<TumbleLayout.columns {
                    let v = box.cell(x, y)
                    guard v != 0 else { continue }
                    let center = CGPoint(x: (CGFloat(x) + 0.5) * c, y: (CGFloat(y) + 0.5) * c)
                    switch pass {
                    case 0 where v == Tumble.junk:
                        let s = sprite()
                        s.texture = art.furTexture()
                        s.size = CGSize(width: c * 1.32, height: c * 1.12)
                        s.position = center
                        s.zPosition = 0
                        s.isHidden = false
                    case 1 where v != Tumble.junk:
                        guard let suit = TumbleLook.suit(cell: v) else { continue }
                        let s = sprite()
                        s.texture = art.cushion(suit)
                        s.size = CGSize(width: c * 1.04, height: c * 1.04)
                        s.position = center
                        s.zPosition = 1
                        s.isHidden = false
                    case 2:
                        guard let trick = TumbleTrick(code: box.trick(x, y)) else { continue }
                        let s = sprite()
                        s.texture = art.badge(trick)
                        s.size = CGSize(width: c * 0.78, height: c * 0.78)
                        s.position = center
                        s.zPosition = 2
                        s.isHidden = false
                    default:
                        continue
                    }
                }
            }
        }
        for i in used..<settledSprites.count { settledSprites[i].isHidden = true }
    }

    // MARK: the falling toy

    /// The toy in hand at row `y` (fractional while gliding), and its landing row. Rows above the
    /// box (18 and up) don't show.
    func showToy(_ toy: TumbleToyState?, y: Double, landing: Int?) {
        let cells = toy.map { TumbleToys.cells($0.toy, rot: $0.spot.rot) } ?? []
        while toySprites.count < cells.count {
            let s = SKSpriteNode()
            toyNode.addChild(s)
            toySprites.append(s)
            let l = SKSpriteNode(texture: TumbleArt.shared.pawTexture())
            landingNode.addChild(l)
            landingSprites.append(l)
        }
        let c = cell
        for (i, s) in toySprites.enumerated() {
            guard let toy, i < cells.count else {
                s.isHidden = true
                landingSprites[i].isHidden = true
                continue
            }
            let cx = CGFloat(toy.spot.x + cells[i].x)
            let cy = CGFloat(y) + CGFloat(cells[i].y)
            s.texture = TumbleArt.shared.cushion(TumbleLook.suit(toy.toy))
            s.size = CGSize(width: c * 1.04, height: c * 1.04)
            s.position = CGPoint(x: (cx + 0.5) * c, y: (cy + 0.5) * c)
            s.isHidden = cy >= CGFloat(TumbleLayout.rows) - 0.05
            let l = landingSprites[i]
            if let landing, landing < toy.spot.y {
                let ly = CGFloat(landing + cells[i].y)
                l.size = CGSize(width: c, height: c)
                l.position = CGPoint(x: (cx + 0.5) * c, y: (ly + 0.5) * c)
                l.isHidden = ly >= CGFloat(TumbleLayout.rows)
            } else {
                l.isHidden = true
            }
        }
    }

    /// The next toy, small, on the cat's paw at the rim.
    func showNext(_ toy: TumbleToy?) {
        let cells = toy.map { TumbleToys.cells($0, rot: 0) } ?? []
        while nextSprites.count < cells.count {
            let s = SKSpriteNode()
            nextNode.addChild(s)
            nextSprites.append(s)
        }
        let c = cell * 0.62
        for (i, s) in nextSprites.enumerated() {
            guard let toy, i < cells.count, showsNext else {
                s.isHidden = true
                continue
            }
            s.isHidden = false
            s.texture = TumbleArt.shared.cushion(TumbleLook.suit(toy))
            s.size = CGSize(width: c * 1.04, height: c * 1.04)
            s.position = CGPoint(x: (CGFloat(cells[i].x) + 0.5) * c, y: (CGFloat(cells[i].y) + 0.5) * c)
        }
    }

    // MARK: the cat, words and effects

    func setCat(_ index: Int, _ pose: CatPose) {
        guard index != catIndex || pose != self.pose || cat.texture == nil else { return }
        catIndex = index
        self.pose = pose
        cat.texture = TableArt.cat(index, pose)
    }

    func setWords(_ text: String?, size: CGFloat? = nil) {
        shownWords = text
        guard let text else {
            words.isHidden = true
            return
        }
        let s = size ?? max(min(cell * 1.6, 28), 11)
        let t = CardFaceFactory.shared.numeral(text, size: s, outline: max(s * 0.14, 2))
        words.texture = t
        words.size = t.size()
        if words.size.width > rect.width * 0.96 {
            let k = rect.width * 0.96 / words.size.width
            words.size = CGSize(width: words.size.width * k, height: words.size.height * k)
        }
        words.isHidden = false
    }

    func setNap(_ on: Bool) {
        guard on == zz.isHidden else { return }
        zz.isHidden = !on
        if on {
            let t = CardFaceFactory.shared.numeral("zz", size: max(cell * 1.2, 10), outline: 2)
            zz.texture = t
            zz.size = t.size()
        }
    }

    func setCatnip(_ on: Bool) {
        let want: CGFloat = on ? 0.18 : 0
        if abs(catnipGlow.alpha - want) > 0.01, catnipGlow.action(forKey: "nip") == nil {
            catnipGlow.run(.fadeAlpha(to: want, duration: 0.2), withKey: "nip")
        }
    }

    /// The name and wins strip under a mini (or a TV box).
    func setName(_ name: String, wins: Int, size: CGFloat) {
        let n = CardFaceFactory.shared.numeral(name, size: size, outline: max(size * 0.14, 1.5))
        nameNode.texture = n
        let w = rect.width - size * 1.6
        let k = min(1, w / max(n.size().width, 1))
        nameNode.size = CGSize(width: n.size().width * k, height: n.size().height * k)
        let t = CardFaceFactory.shared.numeral(String(wins), size: size, fill: UIColor(Palette.yellow), outline: max(size * 0.14, 1.5))
        winsNode.texture = t
        winsNode.size = t.size()
    }

    /// Rows cleared: their cushions pop like stuffing and the cat bats the fluff.
    func pop(rows: [Int]) {
        guard !rows.isEmpty else { return }
        let c = cell
        for y in rows where y < TumbleLayout.rows {
            for i in 0..<5 {
                let puff = SKSpriteNode(texture: TumbleArt.shared.furTexture())
                puff.color = .white
                puff.colorBlendFactor = 0.7
                puff.size = CGSize(width: c * 1.2, height: c)
                puff.position = CGPoint(x: (CGFloat(i) * 2.6 + 1) * c, y: (CGFloat(y) + 0.5) * c)
                puff.zPosition = Z.fx.rawValue
                body.addChild(puff)
                let dx = CGFloat(i - 2) * c * 0.8
                puff.run(.sequence([
                    .group([.moveBy(x: dx, y: c * 2.5, duration: 0.35), .scale(to: 1.8, duration: 0.35), .fadeOut(withDuration: 0.35)]),
                    .removeFromParent(),
                ]))
            }
        }
        let bat = SKAction.sequence([.rotate(toAngle: 0.25, duration: 0.08), .rotate(toAngle: -0.15, duration: 0.1), .rotate(toAngle: 0, duration: 0.08)])
        cat.run(bat, withKey: "bat")
    }

    /// A hit: the box shakes.
    func shake() {
        guard body.action(forKey: "shake") == nil else { return }
        let d = max(cell * 0.3, 2)
        body.run(.sequence([
            .moveBy(x: d, y: 0, duration: 0.04), .moveBy(x: -d * 2, y: 0, duration: 0.06), .moveBy(x: d * 1.5, y: 0, duration: 0.05),
            .moveBy(x: -d * 0.5, y: 0, duration: 0.04),
        ]), withKey: "shake")
    }

    /// Out: the cat tips the box over and toys spill.
    func tip() {
        guard !tipped else { return }
        tipped = true
        let pivot = CGPoint(x: rect.width, y: 0)
        body.position = pivot
        for child in body.children { child.position = CGPoint(x: child.position.x - pivot.x, y: child.position.y - pivot.y) }
        body.run(.rotate(toAngle: -0.18, duration: 0.35, shortestUnitArc: true))
        settled.run(.sequence([.wait(forDuration: 0.2), .fadeAlpha(to: 0.55, duration: 0.3)]))
    }

    /// A new round: upright and full.
    func reset() {
        if tipped {
            body.removeAllActions()
            body.zRotation = 0
            let pivot = body.position
            body.position = .zero
            for child in body.children { child.position = CGPoint(x: child.position.x + pivot.x, y: child.position.y + pivot.y) }
            settled.alpha = 1
            tipped = false
        }
        drawn = nil
    }

    /// The point of a cell in the scene, for effects that fly to it.
    func scenePoint(x: CGFloat, y: CGFloat) -> CGPoint {
        CGPoint(x: rect.minX + x * cell, y: rect.minY + y * cell)
    }
}
