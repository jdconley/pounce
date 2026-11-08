import PounceKit
import SpriteKit
import UIKit

/// The cat tower down the left edge: base, 10 shelves with number badges, the top cushion,
/// and each seat's mini cat head on the shelf of its current phase. A seat that finished
/// phase 10 sits on the top cushion; once the game is over the winners there wear a crown in
/// the `celebrate` pose with the sunburst behind them.
///
/// Folded by default (`isOpen` false): only `tab` shows, a squat tower on a chip at the
/// tower's foot (`TableLayout.towerTab`) wearing the shown hand's phase on the same gold "P4"
/// chip the cats in the top bar wear (`CardFaceFactory.phaseChip`). Open, the
/// whole tower springs up from its foot over the table's left edge on a dark backing panel.
/// `setOpen` moves between the two; nothing `update` sets is touched by it, so a redraw
/// never stops it half way.
///
/// `leap` and `crown` are the Shelf leap and Win verbs (spec §9.1); they move only what
/// `update` sets again, so a reconcile mid-way snaps every head to the truth.
@MainActor
final class TowerNode: SKNode {
    /// Set by the scene: motion runs through its director, bursts and badges go in its fx layer.
    var director: AnimationDirector?
    weak var fx: SKNode?

    /// Scales about the tower's foot to open and fold it; `content` inside it gives back the
    /// tower's own space (this node's), so nothing else changes while it is open.
    private let body = SKNode()
    private let content = SKNode()
    /// The open tower's dark backing; a celebration's spotlight fades it away.
    let panel = SKSpriteNode()
    /// The folded tower, at the tower's foot.
    let tab = SKNode()
    private let tabChip = SKSpriteNode()
    private let tabBadge = SKSpriteNode()
    private var tabPhase: Int?
    /// The tab's phase chip height, from the tab's size (`buildTab`).
    private var tabChipHeight: CGFloat = 0
    private var tabSide: CGFloat = 0
    /// The whole tower shows (else just the tab).
    private(set) var isOpen = false
    private let structure = SKNode()
    private let heads = SKNode()
    private let sunburst = SKSpriteNode(texture: TableArt.table(ArtName.sunburst))
    private var builtFor: CGRect?
    private var layout: TableLayout?
    private var topCenter: CGPoint = .zero
    private var headNodes: [Seat: SKNode] = [:]
    private var headKeys: [Seat: Int] = [:]
    private var faces: [Seat: SKSpriteNode] = [:]
    private var crowns: [Seat: SKSpriteNode] = [:]
    private var cats: [Seat: Int] = [:]
    /// The shelf each head is drawn on (`shelfCount` = the top cushion).
    private var shelves: [Seat: Int] = [:]

    /// The mini cat heads' size (`TableLayout.towerHeadSize`).
    private(set) var headSize: CGFloat = 26
    /// A winner's head on the top cushion is drawn this much bigger.
    static let winnerScale: CGFloat = 1.3

    override init() {
        super.init()
        panel.zPosition = -1
        sunburst.zPosition = -0.5  // behind the structure, inside the tower's z band
        sunburst.isHidden = true
        structure.zPosition = 0
        heads.zPosition = 5  // above every structure piece (layers stay inside a 10-wide z band)
        addChild(body)
        body.addChild(content)
        content.addChild(panel)
        content.addChild(sunburst)
        content.addChild(structure)
        content.addChild(heads)
        addChild(tab)
        tab.zPosition = 6
        tabChip.zPosition = 0
        tab.addChild(tabChip)
        tabBadge.zPosition = 3
        tab.addChild(tabBadge)
        snap(open: false)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(model: TableModel, layout: TableLayout) {
        self.layout = layout
        if builtFor != layout.towerFrame || tabBuiltFor != layout.towerTab { build(layout) }
        let foot = CGPoint(x: layout.towerFrame.midX, y: layout.towerFrame.minY)
        body.position = foot
        content.position = CGPoint(x: -foot.x, y: -foot.y)
        tab.position = CGPoint(x: layout.towerTab.midX, y: layout.towerTab.midY)
        guard let game = model.game else {
            heads.removeAllChildren()
            headNodes.removeAll()
            headKeys.removeAll()
            faces.removeAll()
            crowns.removeAll()
            shelves.removeAll()
            sunburst.isHidden = true
            return
        }
        let seats = Array(game.phase.indices)
        for (seat, node) in headNodes where !seats.contains(seat) {
            node.removeFromParent()
            headNodes[seat] = nil
            faces[seat] = nil
            crowns[seat] = nil
            shelves[seat] = nil
        }
        let over = game.status == .gameOver
        // Seats sharing a shelf sit side by side.
        var byShelf: [Int: [Seat]] = [:]
        for seat in seats {
            byShelf[min(game.phase[seat], TableLayout.shelfCount), default: []].append(seat)
        }
        for (shelf, group) in byShelf {
            for (j, seat) in group.enumerated() {
                let cat = SeatInfo.catIndex(model.room.seats[safe: seat])
                let head: SKNode
                if let existing = headNodes[seat], headKeys[seat] == cat {
                    head = existing
                } else {
                    headNodes[seat]?.removeFromParent()
                    head = makeHead(cat: cat, seat: seat)
                    headNodes[seat] = head
                    headKeys[seat] = cat
                    heads.addChild(head)
                }
                let winner = over && game.winners.contains(seat)
                head.position = spot(shelf: shelf, index: j, of: group.count)
                head.zPosition = CGFloat(j) * 0.1
                head.setScale(winner ? Self.winnerScale : 1)
                head.alpha = 1
                faces[seat]?.texture = TableArt.cat(cat, winner ? .celebrate : .idle)
                crowns[seat]?.isHidden = !winner
                crowns[seat]?.position = crownRest
                crowns[seat]?.alpha = 1
                shelves[seat] = shelf
            }
        }
        sunburst.isHidden = !over
        sunburst.position = topCenter
        sunburst.alpha = 1
        sunburst.setScale(1)
    }

    /// The head node of a seat.
    func head(for seat: Seat) -> SKNode? { headNodes[seat] }

    /// Where a seat's head sits, in this node's space: `shelf` 0...9, or `shelfCount` for the
    /// top cushion; `index` of `count` heads sharing it.
    func spot(shelf: Int, index: Int, of count: Int) -> CGPoint {
        guard let layout else { return .zero }
        let size = headSize
        let spread = min(14, (layout.towerFrame.width - size) / CGFloat(max(count - 1, 1)))
        let dx = (CGFloat(index) - CGFloat(count - 1) / 2) * spread
        if shelf >= TableLayout.shelfCount {
            let wide = min(22, layout.towerFrame.width * 0.5)
            let topDx = (CGFloat(index) - CGFloat(count - 1) / 2) * wide
            return CGPoint(x: topCenter.x + topDx, y: topCenter.y + 8)
        }
        let center = layout.shelf(shelf)
        return CGPoint(x: center.x + dx - 4, y: center.y + 12)
    }

    /// The point a focus zoom should center on for shelves `low...high` (top cushion included).
    func focusRect(low: Int, high: Int) -> CGRect {
        let a = spot(shelf: low, index: 0, of: 1)
        let b = spot(shelf: high, index: 0, of: 1)
        let w = layout?.towerFrame.width ?? 44
        return CGRect(x: min(a.x, b.x) - w / 2, y: min(a.y, b.y) - 24, width: w, height: abs(b.y - a.y) + 64)
    }

    // MARK: open and fold

    /// The open tower's tap area, in this node's space: the tower and its backing panel.
    static func openFrame(_ layout: TableLayout) -> CGRect {
        panelRect(layout).intersection(CGRect(origin: .zero, size: layout.size))
    }

    /// The phase the tab wears (0-based, `shelfCount` or more: finished), nil for none.
    func showPhase(_ phase: Int?) {
        let shown = phase.map { min(max($0, 0), TableLayout.shelfCount) }
        guard shown != tabPhase || tabBadge.texture == nil else { return }
        tabPhase = shown
        tabBadge.isHidden = shown == nil
        guard let shown, tabChipHeight > 0 else { return }
        let texture = CardFaceFactory.shared.phaseChip(PhaseMark(index: shown, laid: false), height: tabChipHeight)
        tabBadge.texture = texture
        tabBadge.size = texture.size()
        // Top right of the tower, its left end over the tower's middle.
        tabBadge.position = CGPoint(x: tabSide * 0.08 + tabBadge.size.width / 2, y: tabSide * 0.4)
    }

    /// What the tab's chip shows (DEBUG and tests): "P4", "done", nil when hidden.
    var tabPhaseText: String? {
        guard !tabBadge.isHidden, let tabPhase else { return nil }
        return PhaseMark(index: tabPhase, laid: false).text ?? "done"
    }

    /// The open or fold motion running now, if any (`settled` waits for it).
    private var motion: Task<Void, Never>?

    /// Waits until the last `setOpen` motion is done.
    func settled() async { await motion?.value }

    /// Opens the tower (it springs up out of the tab) or folds it back down into the tab.
    /// Reduce Motion: the two cross-fade. Calling it again mid-way turns it around from where
    /// it is. `isOpen` changes at once; the motion runs on (`settled`).
    func setOpen(_ open: Bool, animated: Bool) {
        guard open != isOpen else { return }
        isOpen = open
        director?.cancelActions(on: body)
        director?.cancelActions(on: tab)
        guard animated, let director else {
            motion = nil
            return snap(open: open)
        }
        let reduce = UIAccessibility.isReduceMotionEnabled
        var items: [(SKAction, SKNode)] = []
        if open {
            Sound.shared.play(ArtName.Sound.sfxPop, volume: 0.6)
            let wasHidden = body.isHidden
            body.isHidden = false
            if reduce {
                body.setScale(1)
                items.append((.fadeIn(withDuration: 0.18), body))
            } else {
                if wasHidden {  // grows from its foot, however it was last folded away
                    body.xScale = Self.foldedScale.width
                    body.yScale = Self.foldedScale.height
                }
                body.alpha = 1
                items.append((.group([
                    .sequence([
                        .scaleY(to: 1.08, duration: 0.2).eased(.easeOut),
                        .scaleY(to: 1, duration: 0.1).eased(.easeInEaseOut),
                    ]),
                    .scaleX(to: 1, duration: 0.2).eased(.easeOut),
                ]), body))
            }
            items.append((.sequence([.group([.fadeOut(withDuration: 0.12), .scale(to: reduce ? 1 : 0.5, duration: 0.12)]), .hide()]), tab))
        } else {
            tab.isHidden = false
            if reduce {
                tab.setScale(1)
                items.append((.fadeIn(withDuration: 0.18), tab))
                items.append((.sequence([.fadeOut(withDuration: 0.18), .hide()]), body))
            } else {
                items.append((.sequence([
                    .wait(forDuration: 0.12),
                    .group([.fadeIn(withDuration: 0.08), .scale(to: 1.12, duration: 0.12).eased(.easeOut)]),
                    .scale(to: 1, duration: 0.08).eased(.easeInEaseOut),
                ]), tab))
                items.append((.sequence([
                    .group([
                        .scaleY(to: Self.foldedScale.height, duration: 0.2).eased(.easeIn),
                        .scaleX(to: Self.foldedScale.width, duration: 0.2).eased(.easeIn),
                        .sequence([.wait(forDuration: 0.12), .fadeOut(withDuration: 0.08)]),
                    ]),
                    .hide(),
                ]), body))
            }
        }
        motion = Task { await director.runAll(items, decorative: true) }
    }

    /// The folded tower's squash, about its foot.
    private static let foldedScale = CGSize(width: 0.7, height: 0.04)

    /// Open or folded at once, no motion.
    private func snap(open: Bool) {
        body.isHidden = !open
        body.alpha = open ? 1 : 0
        body.xScale = open ? 1 : Self.foldedScale.width
        body.yScale = open ? 1 : Self.foldedScale.height
        tab.isHidden = open
        tab.alpha = 1
        tab.setScale(1)
    }

    // MARK: Shelf leap

    /// Shelf leap (spec §9.1): anticipation squat, an arc up to shelf `to` (the top cushion
    /// for `to >= shelfCount`), a squash landing, a star burst and the gold shelf badge with
    /// the new phase number popping beside the cat, `sfx-leap` and the celebrate haptic.
    /// Reduce Motion: the head fades out and back in on its new shelf, the badge fades in.
    func leap(seat: Seat, from: Int, to: Int) async {
        guard let director, let head = headNodes[seat], let face = faces[seat] else { return }
        let target = min(max(to, 0), TableLayout.shelfCount)
        let others = shelves.filter { $0.key != seat && $0.value == target }.count
        let start = head.position
        let end = spot(shelf: target, index: others, of: others + 1)
        let cat = cats[seat] ?? 0
        let reduce = UIAccessibility.isReduceMotionEnabled
        let t = CelebrationTiming.self
        head.zPosition = 1  // over its shelf-mates while it flies

        Sound.shared.play(ArtName.Sound.sfxLeap)
        if reduce {
            await director.run(.sequence([
                .fadeOut(withDuration: 0.15), .move(to: end, duration: 0), .fadeIn(withDuration: 0.15),
            ]), on: head)
        } else {
            let squat = SKAction.scaleX(to: 1.18, y: 0.78, duration: t.squat).eased(.easeOut)
            // The cat grows big at the top of its arc (a cartoon leap toward the camera) and
            // lands a little big, settling back once its badge has popped.
            let flight = SKAction.group([
                Effects.arc(from: start, to: end, lift: 30, duration: t.arc),
                .sequence([
                    .scaleX(to: 1.5, y: 2.3, duration: t.arc * 0.45).eased(.easeOut),
                    .scale(to: 1.6, duration: t.arc * 0.55).eased(.easeIn),
                ]),
                .sequence([.rotate(toAngle: 0.3, duration: t.arc * 0.5), .rotate(toAngle: 0, duration: t.arc * 0.5)]),
            ])
            let land = SKAction.sequence([
                .scaleX(to: 1.9, y: 1.1, duration: t.squash / 2).eased(.easeOut),
                .scale(to: 1.4, duration: t.squash / 2).eased(.easeIn),
            ])
            await director.run(.sequence([
                squat,
                .run { [weak face] in face?.texture = TableArt.cat(cat, .leap) },
                flight,
                .run { [weak face] in face?.texture = TableArt.cat(cat, .idle) },
                land,
            ]), on: head)
            face.texture = TableArt.cat(cat, .idle)
        }
        shelves[seat] = target
        Haptics.shared.celebrate()
        guard let fx else { return }
        let landing = fx.convert(end, from: heads)
        Effects.burst(.stars, at: landing, in: fx, director: director)
        await popBadge(phase: target, beside: landing, in: fx, director: director, reduce: reduce)
        if !reduce {
            Task { await director.run(.scale(to: 1, duration: 0.2).eased(.easeInEaseOut), on: head) }
        }
    }

    /// The big gold `shelf-badge` with the new phase number (a trophy past phase 10).
    private func popBadge(phase: Int, beside point: CGPoint, in fx: SKNode, director: AnimationDirector, reduce: Bool) async {
        let d: CGFloat = 84
        let badge = SKSpriteNode(texture: TableArt.table(ArtName.shelfBadge), size: CGSize(width: d, height: d))
        badge.position = CGPoint(x: point.x + d * 0.95, y: point.y + d * 0.45)
        badge.zPosition = 6
        if phase >= TableLayout.shelfCount {
            let trophy = SKSpriteNode(texture: TableArt.image(ArtName.iconTrophy), size: CGSize(width: d * 0.56, height: d * 0.56))
            trophy.position = CGPoint(x: 0, y: -d * 0.06)
            trophy.zPosition = 0.01
            badge.addChild(trophy)
        } else {
            let digits = CardFaceFactory.shared.numeral(String(phase + 1), size: 44, fill: UIColor(Palette.orange), outline: 5)
            let number = SKSpriteNode(texture: digits, size: digits.size())
            number.position = CGPoint(x: 0, y: -d * 0.08)
            number.zPosition = 0.01
            badge.addChild(number)
        }
        fx.addChild(badge)
        Effects.burst(.sparkle, at: badge.position, in: fx, director: director)
        let t = CelebrationTiming.self
        let appear: SKAction
        if reduce {
            badge.alpha = 0
            appear = .fadeIn(withDuration: t.pop)
        } else {
            appear = Effects.pop()
        }
        await director.run(.sequence([appear, .wait(forDuration: t.badgeHold)]), on: badge, decorative: true)
        // The badge drifts up and fades on its own; the next leap doesn't wait for it.
        let away = SKAction.group([.fadeOut(withDuration: 0.3), .moveBy(x: 0, y: 16, duration: 0.3)])
        Task {
            await director.run(away, on: badge, decorative: true)
            badge.removeFromParent()
        }
    }

    // MARK: Win

    /// Winners on the top cushion: each head hops there if it isn't already, takes the
    /// `celebrate` pose and grows, then a crown drops onto it with a star burst.
    func crown(_ winners: [Seat]) async {
        guard let director else { return }
        let reduce = UIAccessibility.isReduceMotionEnabled
        let t = CelebrationTiming.self
        var items: [(SKAction, SKNode)] = []
        let top = TableLayout.shelfCount
        let onTop = winners.filter { headNodes[$0] != nil }
        for (i, seat) in onTop.enumerated() {
            guard let head = headNodes[seat], let crown = crowns[seat] else { continue }
            let cat = cats[seat] ?? 0
            let end = spot(shelf: top, index: i, of: onTop.count)
            shelves[seat] = top
            head.zPosition = 2 + CGFloat(i) * 0.1
            faces[seat]?.texture = TableArt.cat(cat, .celebrate)
            let move: SKAction = reduce
                ? .group([.move(to: end, duration: 0), .scale(to: Self.winnerScale, duration: 0.2)])
                : .group([
                    Effects.arc(from: head.position, to: end, lift: 10, duration: 0.25),
                    .scale(to: Self.winnerScale, duration: 0.25).eased(.easeOut),
                ])
            items.append((move, head))
            crown.isHidden = false
            let high = CGPoint(x: crownRest.x, y: crownRest.y + 70)
            crown.position = reduce ? crownRest : high
            crown.alpha = 0
            let drop: SKAction = reduce
                ? .fadeIn(withDuration: 0.2)
                : .sequence([
                    .wait(forDuration: 0.15 + Double(i) * 0.12),
                    .group([.fadeIn(withDuration: 0.1), .move(to: crownRest, duration: t.crownDrop).eased(.easeIn)]),
                    Effects.squash(),
                ])
            items.append((drop, crown))
        }
        await director.runAll(items)
        guard let fx else { return }
        for seat in onTop {
            guard let crown = crowns[seat] else { continue }
            Effects.burst(.stars, at: fx.convert(crown.position, from: crown.parent ?? self), in: fx, director: director)
        }
    }

    /// The sunburst behind the top cushion pops in and turns once, slowly, then stops.
    /// Decorative (only rotation and alpha), so it runs on past the reconcile that follows.
    /// The sunburst behind `point` (tower space; the top cushion by default), turning once
    /// (`CelebrationTiming.sunburstLoop`), then still, so the view can pause again.
    func spinSunburst(at point: CGPoint? = nil) {
        guard let director else { return }
        sunburst.isHidden = false
        sunburst.position = point ?? topCenter
        sunburst.zRotation = 0
        let reduce = UIAccessibility.isReduceMotionEnabled
        let t = CelebrationTiming.self
        sunburst.alpha = 0
        let spin: SKAction = reduce
            ? .fadeIn(withDuration: 0.3)
            : .group([
                .fadeIn(withDuration: 0.3),
                .sequence([.scale(to: 0.3, duration: 0), .scale(to: 1, duration: 0.5).eased(.easeOut)]),
                .rotate(byAngle: -2 * .pi, duration: t.sunburstLoop).eased(.easeOut),
            ])
        let sunburst = sunburst
        Task { await director.run(spin, on: sunburst, decorative: true) }
    }

    /// Fades the sunburst out (the round-over zoom is leaving); the next redraw hides it too.
    func hideSunburst(duration: TimeInterval) {
        guard !sunburst.isHidden else { return }
        guard let director else {
            sunburst.isHidden = true
            return
        }
        let sunburst = sunburst
        Task { await director.run(.sequence([.fadeOut(withDuration: duration), .hide()]), on: sunburst, decorative: true) }
    }

    // MARK: building

    private var crownRest: CGPoint { CGPoint(x: 0, y: headSize * 0.62) }

    private func makeHead(cat: Int, seat: Seat) -> SKNode {
        let size = headSize
        let node = SKNode()
        let ring = SKSpriteNode(texture: TableArt.table(ArtName.ring), size: CGSize(width: size + 4, height: size + 4))
        ring.color = UIColor(SeatInfo.ringColor(seat))
        ring.colorBlendFactor = 0.85
        let face = SKSpriteNode(texture: TableArt.cat(cat, .idle), size: CGSize(width: size, height: size))
        face.zPosition = 1
        let crown = SKSpriteNode(texture: TableArt.table(ArtName.crown), size: CGSize(width: 22 * size / 26, height: 17 * size / 26))
        crown.position = crownRest
        crown.zPosition = 2
        crown.isHidden = true
        node.addChild(ring)
        node.addChild(face)
        node.addChild(crown)
        faces[seat] = face
        crowns[seat] = crown
        cats[seat] = cat
        return node
    }

    private var tabBuiltFor: CGRect?

    /// The open tower's backing panel, in tower space: a little past the tower's sides (its
    /// shelf badges stick out right) and ends, running off the left edge. The top leaves room
    /// for a (crowned) head on the top cushion.
    private static func panelRect(_ layout: TableLayout) -> CGRect {
        let f = layout.towerFrame
        return CGRect(x: f.minX - 16, y: f.minY - 6, width: f.width + 16 + 12, height: f.height + 6 + 18)
    }

    private func build(_ layout: TableLayout) {
        builtFor = layout.towerFrame
        tabBuiltFor = layout.towerTab
        buildTab(layout)
        let panelFrame = Self.panelRect(layout)
        panel.texture = Self.panelTexture(panelFrame.size)
        panel.size = panelFrame.size
        panel.position = CGPoint(x: panelFrame.midX, y: panelFrame.midY)
        structure.removeAllChildren()
        if headSize != layout.towerHeadSize {
            // New head size (the window resized): every head is made again at it.
            headSize = layout.towerHeadSize
            heads.removeAllChildren()
            headNodes.removeAll()
            headKeys.removeAll()
            faces.removeAll()
            crowns.removeAll()
        }
        let frame = layout.towerFrame
        let w = frame.width
        let base = SKSpriteNode(texture: TableArt.table(ArtName.towerBase), size: CGSize(width: w, height: w * 34 / 44))
        base.position = CGPoint(x: frame.midX, y: frame.minY + base.size.height / 2 - 4)
        base.zPosition = 0
        structure.addChild(base)
        for i in 0..<TableLayout.shelfCount {
            let c = layout.shelf(i)
            let shelf = SKSpriteNode(texture: TableArt.table(ArtName.towerShelf), size: CGSize(width: w, height: w * 30 / 44))
            shelf.position = CGPoint(x: c.x, y: c.y - 6)
            shelf.zPosition = 0.1 + CGFloat(i) * 0.1
            structure.addChild(shelf)
            let k = w / TableLayout.towerWidth  // a wider (roomy) tower gets bigger badges
            let badge = SKSpriteNode(texture: TableArt.table(ArtName.shelfBadge), size: CGSize(width: 18 * k, height: 18 * k))
            badge.position = CGPoint(x: frame.maxX - 4 * k, y: c.y - 8 * k)
            badge.zPosition = 2
            let digits = CardFaceFactory.shared.numeral(String(i + 1), size: (10 * k).rounded(), outline: 2)
            let number = SKSpriteNode(texture: digits, size: digits.size())
            number.position = CGPoint(x: 0, y: -1)
            number.zPosition = 0.01
            badge.addChild(number)
            structure.addChild(badge)
        }
        let top = SKSpriteNode(texture: TableArt.table(ArtName.towerTop), size: CGSize(width: w, height: w * 40 / 44))
        let topShelf = layout.shelf(TableLayout.shelfCount - 1)
        let step = frame.height / CGFloat(TableLayout.shelfCount)
        top.position = CGPoint(x: frame.midX, y: min(topShelf.y + step * 0.75, frame.maxY - top.size.height / 2 + 6))
        top.zPosition = 1.5
        structure.addChild(top)
        topCenter = top.position
        let burst = min(260, layout.size.width * 0.7)
        sunburst.size = CGSize(width: burst, height: burst)
    }

    /// The tab: a squat tower (the base with the top cushion sat right on it) on a round chip,
    /// and the shown hand's phase on a gold phase chip at its top right.
    private func buildTab(_ layout: TableLayout) {
        let side = layout.towerTab.width
        tabChip.texture = Self.chipTexture(side)
        tabChip.size = CGSize(width: side + 8, height: side + 8)
        tabChip.position = CGPoint(x: 0, y: -1)
        tabChip.removeAllChildren()
        let w = side * 0.78
        let base = SKSpriteNode(texture: TableArt.table(ArtName.towerBase), size: CGSize(width: w, height: w * 34 / 44))
        base.position = CGPoint(x: 0, y: -side * 0.22)
        base.zPosition = 1
        let top = SKSpriteNode(texture: TableArt.table(ArtName.towerTop), size: CGSize(width: w, height: w * 40 / 44))
        top.position = CGPoint(x: 0, y: base.position.y + side * 0.34)
        top.zPosition = 2
        tabChip.addChild(base)
        tabChip.addChild(top)
        tabSide = side
        tabChipHeight = max((side * 0.46).rounded(), 20)
        tabBadge.texture = nil  // drawn again at this size
        let phase = tabPhase
        tabPhase = nil
        showPhase(phase)
    }

    /// A dark round chip with a teal ring and an ink outline, a hard shadow under it.
    private static func chipTexture(_ side: CGFloat) -> SKTexture {
        let d = side + 8
        let image = UIGraphicsImageRenderer(size: CGSize(width: d, height: d)).image { _ in
            let circle = CGRect(x: 4, y: 2, width: side, height: side)
            UIColor(Palette.ink).withAlphaComponent(0.55).setFill()
            UIBezierPath(ovalIn: circle.offsetBy(dx: 0, dy: 3)).fill()
            UIColor(Palette.ink).setFill()
            UIBezierPath(ovalIn: circle).fill()
            UIColor(Palette.teal).setFill()
            UIBezierPath(ovalIn: circle.insetBy(dx: 2, dy: 2)).fill()
            UIColor(Palette.night).setFill()
            UIBezierPath(ovalIn: circle.insetBy(dx: 6, dy: 6)).fill()
        }
        return SKTexture(image: image)
    }

    /// The open tower's backing: a dark rounded panel with an ink outline and a violet rim.
    private static func panelTexture(_ size: CGSize) -> SKTexture {
        guard size.width > 0, size.height > 0 else { return SKTexture() }
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            let r = CGRect(origin: .zero, size: size)
            UIColor(Palette.ink).setFill()
            UIBezierPath(roundedRect: r, cornerRadius: 18).fill()
            UIColor(Palette.violet).setFill()
            UIBezierPath(roundedRect: r.insetBy(dx: 3, dy: 3), cornerRadius: 15).fill()
            UIColor(Palette.night).withAlphaComponent(0.96).setFill()
            UIBezierPath(roundedRect: r.insetBy(dx: 6, dy: 6), cornerRadius: 12).fill()
        }
        return SKTexture(image: image)
    }
}
