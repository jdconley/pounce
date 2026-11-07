import PounceKit
import SpriteKit
import UIKit

/// What a celebration left on the table: the dimming veil and the tower zoom. The zoom stays
/// for the finished game (the game-over table is the tower top in the spotlight); everything
/// else is put back by the step that set it, or by the next reconcile of a game in progress.
struct CelebrationState {
    var veil: SKSpriteNode?
    /// The tower layer is raised above the veil and zoomed.
    var focused = false
    /// `onGameOver` was called for this table.
    var announced = false
}

/// The table's big moments (spec §5.10, §9.1): the versus intro before the first deal, round
/// over (my leftovers flip, points pop off every cat, the cats who finished their phase leap
/// up the tower) and game over (crowned winners on the top shelf, sunburst, confetti). Each
/// runs on the scene's timeline like any game event: the `.reconcile` that follows waits for
/// it, then snaps to the snapshot. Timings come from `CelebrationTiming`, whose tests keep the
/// round-over sequence under the server's 6 s gap before the next deal.
///
/// Reduce Motion (spec §13): leaps and slides become short fades, no shake, confetti halved.
extension TableScene {
    private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }
    private var fxLayer: SKNode { layer(.fx) }

    // MARK: versus intro

    /// Before the first deal (the server sends no events for it): every cat slides in on a
    /// diagonal slash of its seat color, 1.2 s, then the deal.
    func playVersusIntro() async {
        guard let model, let game = model.game else { return }
        let seats = Array(game.phase.indices)
        let n = max(seats.count, 1)
        let reduce = reduceMotion
        let fx = fxLayer
        Sound.shared.play(ArtName.Sound.sfxWhoosh)
        let veil = makeVeil(in: fx, alpha: 0.6)
        hand.isHidden = true
        laidZone.isHidden = true

        let usable = size.height * 0.62
        let gap: CGFloat = 12
        let band = min(118, (usable - gap * CGFloat(n - 1)) / CGFloat(n))
        let topY = size.height / 2 + (CGFloat(n) * band + CGFloat(n - 1) * gap) / 2 - band / 2
        let tilt: CGFloat = 0.16
        let total = CelebrationTiming.versusIntro
        let out = 0.25
        var items: [(SKAction, SKNode)] = [(.sequence([
            .fadeAlpha(to: 0.6, duration: 0.15), .wait(forDuration: total - 0.15 - out), .fadeOut(withDuration: out),
        ]), veil)]
        veil.alpha = 0
        var nodes: [SKNode] = [veil]
        for (i, seat) in seats.enumerated() {
            let fromLeft = i.isMultiple(of: 2)
            let side: CGFloat = fromLeft ? -1 : 1
            let y = topY - CGFloat(i) * (band + gap)
            let slash = slashNode(color: UIColor(SeatInfo.ringColor(seat)), width: size.width * 1.6, height: band)
            slash.zRotation = tilt
            slash.zPosition = 1 + CGFloat(i) * 0.1
            let home = CGPoint(x: size.width / 2, y: y)
            slash.position = reduce ? home : CGPoint(x: home.x + side * size.width * 1.7, y: y)
            fx.addChild(slash)
            let cat = catBadge(seat: seat, model: model, height: band)
            cat.zPosition = 1.05 + CGFloat(i) * 0.1
            let spot = CGPoint(x: size.width * (fromLeft ? 0.3 : 0.7), y: y + band * 0.04)
            cat.position = reduce ? spot : CGPoint(x: spot.x + side * size.width, y: spot.y)
            fx.addChild(cat)
            nodes += [slash, cat]

            let delay = Double(i) * 0.06
            let slideIn = 0.28
            let catIn = slideIn + 0.08
            let landed = delay + catIn + CelebrationTiming.squash
            let hold = max(total - out - landed, 0.05)
            let away = SKAction.group([
                .moveBy(x: -side * size.width * 1.8, y: 0, duration: out).eased(.easeIn),
                .fadeOut(withDuration: out),
            ])
            if reduce {
                slash.alpha = 0
                cat.alpha = 0
                let fade = SKAction.sequence([
                    .wait(forDuration: delay), .fadeIn(withDuration: 0.2),
                    .wait(forDuration: total - delay - 0.2 - out), .fadeOut(withDuration: out),
                ])
                items += [(fade, slash), (fade, cat)]
            } else {
                items.append((.sequence([
                    .wait(forDuration: delay), .move(to: home, duration: slideIn).eased(.easeOut),
                    .wait(forDuration: catIn - slideIn + CelebrationTiming.squash + hold), away,
                ]), slash))
                items.append((.sequence([
                    .wait(forDuration: delay), .move(to: spot, duration: catIn).eased(.easeOut),
                    .run { Sound.shared.play(ArtName.Sound.sfxPop, volume: 0.7) },
                    Effects.squash(), .wait(forDuration: hold), away,
                ]), cat))
            }
        }
        await director.runAll(items, decorative: true)
        nodes.forEach { $0.removeFromParent() }
        hand.isHidden = false
        laidZone.isHidden = false
        await animateDeal(dealer: game.dealer)
    }

    /// A diagonal band of `color` with a thick ink outline (two plain color sprites, no shapes).
    private func slashNode(color: UIColor, width: CGFloat, height: CGFloat) -> SKNode {
        let node = SKNode()
        let ink = SKSpriteNode(color: UIColor(Palette.ink), size: CGSize(width: width, height: height + 10))
        let fill = SKSpriteNode(color: color, size: CGSize(width: width, height: height))
        let shine = SKSpriteNode(color: UIColor.white.withAlphaComponent(0.22), size: CGSize(width: width, height: height * 0.22))
        shine.position = CGPoint(x: 0, y: height * 0.3)
        fill.zPosition = 0.01
        shine.zPosition = 0.02
        [ink, fill, shine].forEach(node.addChild)
        return node
    }

    /// A seat's cat (awake pose) with its name, or the bot badge, for the versus intro.
    private func catBadge(seat: Seat, model: TableModel, height: CGFloat) -> SKNode {
        let node = SKNode()
        let view = model.room.seats[safe: seat]
        let d = height * 1.12
        let cat = SKSpriteNode(texture: TableArt.cat(SeatInfo.catIndex(view), .awake), size: CGSize(width: d, height: d))
        node.addChild(cat)
        if view?.kind == .bot {
            let badge = SKSpriteNode(texture: TableArt.image(ArtName.badgeBot), size: CGSize(width: d * 0.34, height: d * 0.34))
            badge.position = CGPoint(x: d * 0.36, y: d * 0.3)
            badge.zPosition = 0.02
            node.addChild(badge)
        } else if let name = view?.person?.name, !name.isEmpty {
            let fromLeft = seat.isMultiple(of: 2)
            let text = CardFaceFactory.shared.numeral(name, size: min(30, height * 0.3), outline: 4)
            let label = SKSpriteNode(texture: text, size: text.size())
            let dx = d * 0.5 + text.size().width / 2 + 4
            label.position = CGPoint(x: fromLeft ? dx : -dx, y: -height * 0.08)
            label.zPosition = 0.02
            node.addChild(label)
        }
        return node
    }

    // MARK: round over

    /// Round over (≤ 5 s, `CelebrationTiming.roundOver`): my leftover cards flip and bounce,
    /// points pop off each cat in seat order (only `points[]`: other seats' leftovers are never
    /// shown), then the table dims, the tower zooms in and each advanced cat does the Shelf
    /// leap, staggered. A `gameOver` right behind keeps the zoom for the finale.
    func playRoundOver(wentOut: Seat?, points: [Int], advanced: [Seat]) async {
        guard let game = model?.game else { return }
        let t = CelebrationTiming.self
        let finale = store.room?.game?.status == .gameOver
        flipLeftovers()

        // Points pop, seat order, staggered.
        let stagger = t.pointsStagger(seats: points.count)
        var pops: [(SKAction, SKNode)] = []
        var squashes: [(SKAction, SKNode)] = []
        for (seat, value) in points.enumerated() {
            let node = pointsNode(value, wentOut: seat == wentOut)
            node.position = pointsSpot(seat)
            node.zPosition = 8
            node.setScale(0)
            fxLayer.addChild(node)
            let at = Double(seat) * stagger
            let appear: SKAction = reduceMotion
                ? .sequence([.fadeOut(withDuration: 0), .scale(to: 1, duration: 0), .fadeIn(withDuration: t.pop)])
                : Effects.pop()
            let spot = node.position
            let fx = fxLayer
            let director = director
            let land = SKAction.run {
                Sound.shared.play(ArtName.Sound.sfxPop, volume: 0.8)
                if seat == wentOut { Effects.burst(.sparkle, at: spot, in: fx, director: director) }
            }
            let tail = SKAction.group([
                .moveBy(x: 0, y: reduceMotion ? 0 : 44, duration: t.pointsTail).eased(.easeOut),
                .sequence([.wait(forDuration: t.pointsTail * 0.45), .fadeOut(withDuration: t.pointsTail * 0.55)]),
            ])
            pops.append((.sequence([.wait(forDuration: at), land, appear, tail, .removeFromParent()]), node))
            if !reduceMotion, seat != bottomSeat, let cat = opponents.node(for: seat) {
                squashes.append((.sequence([.wait(forDuration: at), Effects.squash()]), cat))
            }
        }
        runInBackground(pops, decorative: true)
        runInBackground(squashes, decorative: false)  // a snap resets the cats' scale
        let popped = Double(max(points.count - 1, 0)) * stagger + t.pop
        guard !advanced.isEmpty else {
            await pause(popped + t.pointsTail)
            return
        }
        await pause(popped + t.beforeLeaps)

        // Shelf leaps, on the zoomed tower.
        let moves = advanced.compactMap { seat -> (Seat, Int, Int)? in
            guard let from = game.phase[safe: seat] else { return nil }
            return (seat, min(from, TableLayout.shelfCount), min(from + 1, TableLayout.shelfCount))
        }
        let low = moves.map(\.1).min() ?? 0
        let high = moves.map(\.2).max() ?? 0
        await focusTower(on: tower.focusRect(low: low, high: high))
        // The sunburst behind the shelf they climb to, as at game over (one turn, then still).
        tower.spinSunburst(at: tower.spot(shelf: high, index: 0, of: 1))
        let leapGap = t.leapStagger(leapers: moves.count)
        let tower = tower
        let leaps = moves.enumerated().map { i, move in
            Task { @MainActor in
                await self.pause(Double(i) * leapGap)
                await tower.leap(seat: move.0, from: move.1, to: move.2)
            }
        }
        for leap in leaps { await leap.value }
        if !finale { await unfocusTower() }
    }

    /// My leftover cards flip over and the hand bounces up, undimmed (only a hand already
    /// face up: a hidden hand on a pass-and-play phone stays hidden).
    private func flipLeftovers() {
        guard bottomSeat != nil, bottomSeat == shownRevealed, !hand.cards.isEmpty else { return }
        var items: [(SKAction, SKNode)] = []
        for (i, card) in hand.cards.enumerated() {
            let flip: SKAction = reduceMotion
                ? .sequence([.fadeAlpha(to: 0.4, duration: 0.1), .fadeAlpha(to: 1, duration: 0.15)])
                : .sequence([
                    .wait(forDuration: Double(i) * 0.03),
                    .scaleX(to: 0, duration: 0.1).eased(.easeIn),
                    .scaleX(to: 1.12, duration: 0.12).eased(.easeOut),
                    .scale(to: 1, duration: 0.08),
                ])
            items.append((flip, card))
        }
        items.append((.fadeAlpha(to: 1, duration: 0.2), hand))
        Sound.shared.play(ArtName.Sound.sfxFlip)
        runInBackground(items, decorative: false)
    }

    /// "+N" in chunky outlined numerals (a sparkly "0" for the seat that went out).
    private func pointsNode(_ value: Int, wentOut: Bool) -> SKSpriteNode {
        let text = value > 0 ? "+\(value)" : "0"
        let fill = UIColor(wentOut || value == 0 ? Palette.teal : Palette.orange)
        let texture = CardFaceFactory.shared.numeral(text, size: 34, fill: fill, outline: 4)
        return SKSpriteNode(texture: texture, size: texture.size())
    }

    /// Just above a seat's cat in the bar, or above the middle of my hand.
    private func pointsSpot(_ seat: Seat) -> CGPoint {
        if seat != bottomSeat, let cat = opponents.node(for: seat) {
            let p = fxLayer.convert(cat.position, from: opponents)
            return CGPoint(x: p.x, y: p.y + cat.diameter * 0.2)
        }
        if let layout, let mid = layout.hand(count: 1, lifted: nil).first {
            let p = fxLayer.convert(mid.position, from: hand)
            return CGPoint(x: p.x, y: p.y + layout.cardSize.height * 0.9)
        }
        return CGPoint(x: size.width / 2, y: size.height * 0.25)
    }

    // MARK: game over

    /// Game over: the tower top in the spotlight, the winners crowned there in the celebrate
    /// pose, the sunburst turning once (4 s, then still), confetti, yarn, stars and fur, and
    /// the fanfare; then `onGameOver` brings up the game-over overlay.
    func playGameOver(winners: [Seat]) async {
        let t = CelebrationTiming.self
        let top = TableLayout.shelfCount
        await focusTower(on: tower.focusRect(low: top - 2, high: top))
        Sound.shared.play(ArtName.Sound.sfxFanfare)
        Haptics.shared.celebrate()
        tower.spinSunburst()
        let crowned = Task { @MainActor in await self.tower.crown(winners) }
        let center = fxLayer.convert(tower.spot(shelf: top, index: 0, of: 1), from: tower)
        let kinds: [BurstKind] = reduceMotion ? [.confetti, .stars] : [.confetti, .stars, .yarn, .confetti, .fur, .confetti]
        for (i, kind) in kinds.enumerated() {
            await pause(i == 0 ? 0.2 : 0.45)
            let dx = CGFloat([0, -60, 60, -30, 40, 0][i % 6])
            let dy = CGFloat([30, 70, 50, 110, 90, 140][i % 6])
            Effects.burst(kind, at: CGPoint(x: center.x + dx, y: center.y + dy), in: fxLayer, director: director)
        }
        await crowned.value
        let elapsed = 0.2 + 0.45 * Double(kinds.count - 1)
        await pause(max(t.sunburstLoop - elapsed, 0))
        announceGameOver(winners)
    }

    /// Calls `onGameOver` once per table.
    func announceGameOver(_ winners: [Seat]) {
        guard !celebration.announced else { return }
        celebration.announced = true
        onGameOver(winners)
    }

    /// After a snap: a finished room shows the game-over overlay (a table opened after the
    /// game ended gets no events); a room still playing drops any leftover spotlight.
    func settleCelebration() {
        guard let model else { return }
        if model.room.status == .over || model.game?.status == .gameOver {
            if !animating { announceGameOver(model.game?.winners ?? []) }
        } else if celebration.focused, !animating {
            endFocus()
            foldTower(animated: false)
        }
    }

    // MARK: spotlight

    /// Dims the table and zooms the tower so `rect` (tower space) fills the middle-left. The
    /// folded tower springs open as the zoom starts.
    private func focusTower(on rect: CGRect) async {
        let t = CelebrationTiming.self
        let towerLayer = layer(.tower)
        let scale = min(2.4, max(1.4, size.height * 0.84 / max(rect.height, 1)))
        let target = CGPoint(x: size.width * 0.36, y: size.height * 0.5)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let position = CGPoint(x: target.x - center.x * scale, y: target.y - center.y * scale)
        openTower()
        celebration.focused = true
        towerLayer.zPosition = Layer.drag.rawValue + 4
        let veil = celebration.veil ?? makeVeil(in: self, alpha: 0)
        veil.zPosition = Layer.drag.rawValue + 2
        celebration.veil = veil
        let zoom: SKAction = reduceMotion
            ? .sequence([
                .fadeOut(withDuration: t.zoomIn / 2),
                .group([.scale(to: scale, duration: 0), .move(to: position, duration: 0)]),
                .fadeIn(withDuration: t.zoomIn / 2),
            ])
            : .group([.scale(to: scale, duration: t.zoomIn), .move(to: position, duration: t.zoomIn)]).eased(.easeInEaseOut)
        // Landed flyers (a card just discarded, say) sit in the fx layer above the veil: they
        // fade with the table and the next reconcile replaces them.
        // Dark enough that the table (melds, badges, piles) drops away behind the tower.
        var items: [(SKAction, SKNode)] = [
            (zoom, towerLayer), (.fadeAlpha(to: Self.veilAlpha, duration: t.zoomIn), veil),
            (.fadeOut(withDuration: t.zoomIn), tower.panel),  // the spotlight is the tower's backing
        ]
        for node in transients { items.append((.fadeOut(withDuration: t.zoomIn), node)) }
        await director.runAll(items, decorative: true)
        await tower.settled()
    }

    /// How dark the spotlight veil gets over the table.
    static let veilAlpha: CGFloat = 0.82

    private func unfocusTower() async {
        let t = CelebrationTiming.self
        let towerLayer = layer(.tower)
        var items: [(SKAction, SKNode)] = [
            (.group([.scale(to: 1, duration: t.zoomOut), .move(to: .zero, duration: t.zoomOut)]).eased(.easeInEaseOut), towerLayer),
            (.fadeIn(withDuration: t.zoomOut), tower.panel),
        ]
        if let veil = celebration.veil { items.append((.fadeOut(withDuration: t.zoomOut), veil)) }
        tower.hideSunburst(duration: t.zoomOut)
        await director.runAll(items, decorative: true)
        endFocus()
        foldTower()  // back down to its tab once the climb is seen
        await tower.settled()
    }

    /// Puts the tower layer back at once.
    private func endFocus() {
        let towerLayer = layer(.tower)
        towerLayer.setScale(1)
        towerLayer.position = .zero
        towerLayer.alpha = 1
        towerLayer.zPosition = Layer.tower.rawValue
        director.cancelActions(on: tower.panel)
        tower.panel.alpha = 1
        celebration.veil?.removeFromParent()
        celebration.veil = nil
        celebration.focused = false
        director.wake()
    }

    // MARK: helpers

    /// A full-screen night-violet sprite (a plain color sprite, not a shape).
    private func makeVeil(in parent: SKNode, alpha: CGFloat) -> SKSpriteNode {
        let veil = SKSpriteNode(color: UIColor(Palette.night), size: CGSize(width: size.width * 3, height: size.height * 3))
        veil.position = CGPoint(x: size.width / 2, y: size.height / 2)
        veil.alpha = alpha
        veil.zPosition = 0
        parent.addChild(veil)
        return veil
    }

    /// Waits `seconds` of rendered time (an action, so it pauses with the scene's speed and
    /// keeps the view awake).
    func pause(_ seconds: TimeInterval) async {
        guard seconds > 0 else { return }
        let node = SKNode()
        fxLayer.addChild(node)
        await director.run(.wait(forDuration: seconds), on: node, decorative: true)
        node.removeFromParent()
    }

    private func runInBackground(_ items: [(SKAction, SKNode)], decorative: Bool) {
        guard !items.isEmpty else { return }
        let director = director
        Task { await director.runAll(items, decorative: decorative) }
    }
}
