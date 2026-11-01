import PounceKit
import SpriteKit
import UIKit

/// Game events played on the table (spec §9.1), one at a time on the scene's timeline. Each
/// animates over the table as it was before the event and returns when its motion is done;
/// the `.reconcile` that follows (the action's snapshot) then snaps every node to the truth.
/// Moving cards are temporary flyers in the `fx` layer, so a reconcile never cancels them;
/// where one lands it stays (`transients`) until that reconcile replaces it. Motion on the
/// table's own nodes is decorative (it touches only what reconcile never sets, and ends where
/// it started) or relative, so a snap mid-way loses nothing. Decorative tails (a cat's leap,
/// a ring pulse, a badge fading) run on in the background instead of holding the timeline,
/// so a busy table keeps up with the server's pace (a bot acts every 1.2 s).
///
/// Reduce Motion (spec §13): arcs become 0.15 s fades, no shake or leaps, bursts halved.
extension TableScene {
    private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }
    private var fx: SKNode { layer(.fx) }

    func animate(_ event: GameEvent) async {
        switch event {
        case .drew(let seat, let from, let card):
            await animateDraw(seat: seat, from: from, card: card)
        case .discarded(let seat, let card, let skipTarget):
            await animateDiscard(seat: seat, card: card, skipTarget: skipTarget)
        case .skipped(let seat):
            await animateSkipped(seat)
        case .laidDown(let seat, let groups):
            await animateLayDown(seat: seat, groups: groups)
        case .hit(let seat, let card, let target, let group):
            await animateHit(seat: seat, card: card, target: target, group: group)
        case .turn(let seat):
            await animateTurn(seat)
        case .reshuffled:
            await animateReshuffle()
        case .roundStarted(_, let dealer):
            await animateDeal(dealer: dealer)
        case .roundOver(let wentOut, let points, let advanced, _, _):
            await playRoundOver(wentOut: wentOut, points: points, advanced: advanced)
        case .gameOver(let winners):
            await playGameOver(winners: winners)
        }
    }

    // MARK: draw

    /// Mine from the deck: the card lifts and flips face up (sparkle on a Yarn, a groan wobble
    /// on a Cucumber), then joins the hand. Otherwise the card (a back from the deck, the
    /// face from the discard) slides to the seat: the end of the hand, or into its cat.
    private func animateDraw(seat: Seat, from source: DrawSource, card: CardID?) async {
        guard let layout, let game = model?.game else { return }
        let fromDeck = source == .deck
        let start = point(of: fromDeck ? deck : discard)
        let face: CardID? = fromDeck ? nil : (card ?? game.discardTop)
        if !fromDeck { discard.top?.alpha = 0 }  // the pile shows what's under it until the snap
        let node = flyer(face, at: start, z: 1)

        guard seat == bottomSeat else {
            Sound.shared.play(ArtName.Sound.sfxFlip, volume: 0.4)
            await director.run(.sequence([
                Effects.fly(from: start, to: seatPoint(seat), duration: 0.34, lift: 30, scale: 0.32),
                .fadeOut(withDuration: 0.08),
            ]), on: node)
            node.removeFromParent()
            return
        }

        let land = handLanding(layout)
        let faceUp = seat == shownRevealed
        if faceUp, fromDeck, let card {
            Sound.shared.play(ArtName.Sound.sfxFlip)
            node.isPrivate = true
            let flip = SKAction.sequence([
                .scaleX(to: 0, duration: 0.15).eased(.easeIn),
                .run { [weak self, weak node] in
                    // Only face up while that hand is still the one shown.
                    if let node, self?.shownRevealed == seat { node.setCard(card) }
                },
                .scaleX(to: 1.12, duration: 0.15).eased(.easeOut),
            ])
            let lift: SKAction = reduceMotion
                ? .scaleY(to: 1.12, duration: 0.3)
                : .group([.moveBy(x: 0, y: 34, duration: 0.3).eased(.easeOut), .scaleY(to: 1.12, duration: 0.3)])
            await director.run(.group([flip, lift]), on: node)
            switch Card(id: card) {
            case .yarn:
                Sound.shared.play(ArtName.Sound.sfxSparkle)
                Effects.burst(.sparkle, at: node.position, in: fx, director: director)
            case .cucumber:
                Sound.shared.play(ArtName.Sound.sfxScream, volume: 0.35)
                if !reduceMotion { await director.run(wobble(), on: node) }
            case .number:
                break
            }
            await director.run(
                Effects.fly(from: node.position, to: land.position, duration: 0.22, lift: 12, rotation: land.rotation),
                on: node)
        } else {
            Sound.shared.play(ArtName.Sound.sfxFlip, volume: 0.6)
            await director.run(
                Effects.fly(from: start, to: land.position, duration: 0.32, lift: 30, rotation: land.rotation),
                on: node)
            if !faceUp { node.setCard(nil) }
        }
        transients.append(node)
    }

    /// A groan: three quick tilts that end upright.
    private func wobble() -> SKAction {
        let a: CGFloat = 0.2
        return .sequence([
            .rotate(byAngle: a, duration: 0.035), .rotate(byAngle: -2 * a, duration: 0.05),
            .rotate(byAngle: 2 * a, duration: 0.05), .rotate(byAngle: -2 * a, duration: 0.05),
            .rotate(byAngle: a, duration: 0.035),
        ])
    }

    // MARK: discard (Bat) and Cucumber terror

    /// Bat: the card arcs onto the discard pile with a spin, a paw swipes through, the pile
    /// squashes. A Cucumber aimed at a seat first flies to that cat for the terror.
    private func animateDiscard(seat: Seat, card: CardID, skipTarget: Seat?) async {
        let node: CardNode
        var owned = false  // the provisional node belongs to the scene until the reconcile
        if card == provisionalCard, let p = provisionalNode {
            node = p
            node.isPrivate = false  // accepted: the card is on the table now
            owned = true
        } else if seat == bottomSeat, let h = hand.node(for: card) {
            node = flyer(card, at: fx.convert(h.position, from: hand), rotation: h.zRotation, z: 1)
            h.alpha = 0
        } else {
            node = flyer(card, at: seatPoint(seat), scale: 0.4, z: 1)
        }
        if let target = skipTarget {
            let spot = local(seatPoint(target), for: node)
            await director.run(
                Effects.fly(from: node.position, to: spot, duration: 0.26, lift: 50, spins: 1, scale: 0.7), on: node)
            background(terror(target, at: seatPoint(target)))  // the cucumber bounces off to the pile
        }
        await bat(node)
        if !owned { transients.append(node) }
    }

    private func bat(_ node: CardNode) async {
        let pile = point(of: discard)
        let landing = local(pile, for: node)
        Sound.shared.play(ArtName.Sound.sfxBat)
        let flight: SKAction
        if hypot(node.position.x - landing.x, node.position.y - landing.y) < 6 {
            // Already on the pile (my own discard, shown there while in flight): a hop and spin.
            flight = reduceMotion
                ? .wait(forDuration: 0.15)
                : .group([
                    .sequence([.moveBy(x: 0, y: 26, duration: 0.13).eased(.easeOut), .moveBy(x: 0, y: -26, duration: 0.13).eased(.easeIn)]),
                    .sequence([.rotate(byAngle: -2 * .pi, duration: 0.22), .rotate(toAngle: 0, duration: 0.04, shortestUnitArc: true)]),
                    .scale(to: 1, duration: 0.26),
                ])
        } else {
            flight = Effects.fly(from: node.position, to: landing, duration: 0.3, lift: 44, spins: -1, scale: 1)
        }
        if !reduceMotion {
            let (swipe, paw) = pawSwipe(at: pile, delay: flight.duration * 0.5)
            background([(swipe, paw)]) { paw.removeFromParent() }
        }
        await director.run(flight, on: node)
        Haptics.shared.drop()
        // Landing squashes run on: the card's is decorative (a flyer), the pile's is not (a
        // reconcile snapping the pile cancels it and resets its scale).
        background([(Effects.squash(), node)])
        background([(Effects.squash(), discard)], decorative: false)
    }

    /// The paw sprite swipes in over the pile and back out.
    private func pawSwipe(at pile: CGPoint, delay: TimeInterval) -> (SKAction, SKNode) {
        let w = (layout?.cardSize.width ?? CardFaceFactory.cardSize.width) * 1.3
        let paw = SKSpriteNode(texture: TableArt.table(ArtName.pawSwipe), size: CGSize(width: w, height: w))
        paw.position = CGPoint(x: pile.x + w * 1.4, y: pile.y + w * 0.35)
        paw.alpha = 0
        paw.zPosition = 4
        fx.addChild(paw)
        return (.sequence([
            .wait(forDuration: delay),
            .group([
                .fadeIn(withDuration: 0.06),
                .move(to: CGPoint(x: pile.x + w * 0.25, y: pile.y + w * 0.1), duration: 0.1).eased(.easeOut),
                .rotate(byAngle: 0.45, duration: 0.1),
            ]),
            .group([
                .move(to: CGPoint(x: pile.x + w * 1.5, y: pile.y + w * 0.45), duration: 0.14).eased(.easeIn),
                .fadeOut(withDuration: 0.14),
            ]),
        ]), paw)
    }

    /// Cucumber terror on `seat` (its cat, or the hand for the bottom seat): terrified leap,
    /// fur puff, a 4 pt screen shake for 0.2 s, a scream and a thump. Returns the decorative
    /// motion to run.
    private func terror(_ seat: Seat, at spot: CGPoint) -> [(SKAction, SKNode)] {
        Sound.shared.play(ArtName.Sound.sfxScream)
        Haptics.shared.thump()
        Effects.burst(.fur, at: spot, in: fx, director: director)
        var items: [(SKAction, SKNode)] = []
        if seat != bottomSeat, let cat = opponents.node(for: seat) {
            items.append(cat.terror(reduceMotion: reduceMotion))
        } else if !reduceMotion {
            items.append((hop(height: 24), hand))
        } else {
            items.append((.wait(forDuration: 0.3), hand))
        }
        if !reduceMotion {
            for l in [Layer.background, .rug, .piles, .laidZone, .tower, .opponents, .trays, .hand] {
                let n = layer(l)
                items.append((Effects.shake(n, amplitude: 4, duration: 0.2), n))
            }
        }
        return items
    }

    /// Runs motion without holding the timeline; `then` runs once it is done. Decorative by
    /// default; a non-decorative tail is cancelled by the next snap of its node.
    private func background(
        _ items: [(SKAction, SKNode)], decorative: Bool = true, then cleanup: (() -> Void)? = nil
    ) {
        guard !items.isEmpty else { return }
        let director = director
        Task {
            await director.runAll(items, decorative: decorative)
            cleanup?()
        }
    }

    /// Up and back down, ending exactly where it started.
    private func hop(height: CGFloat) -> SKAction {
        .sequence([
            .moveBy(x: 0, y: height, duration: 0.13).eased(.easeOut),
            .moveBy(x: 0, y: -height, duration: 0.15).eased(.easeIn),
            .moveBy(x: 0, y: height * 0.4, duration: 0.09).eased(.easeOut),
            .moveBy(x: 0, y: -height * 0.4, duration: 0.09).eased(.easeIn),
            .move(to: .zero, duration: 0),
        ])
    }

    // MARK: skipped

    /// The skipped seat's skip badge pops and floats away.
    private func animateSkipped(_ seat: Seat) async {
        var spot = seatPoint(seat)
        var size = CGSize(width: 34, height: 34)
        if seat != bottomSeat, let cat = opponents.node(for: seat) {
            spot = fx.convert(cat.skipBadgePoint, from: opponents)
            size = CGSize(width: cat.skipBadgeSize.width * 1.5, height: cat.skipBadgeSize.height * 1.5)
            cat.hideSkipBadge()
        } else {
            spot.y += 70
        }
        let badge = SKSpriteNode(texture: TableArt.image(ArtName.badgeSkip), size: size)
        badge.position = spot
        badge.zPosition = 4
        fx.addChild(badge)
        Sound.shared.play(ArtName.Sound.sfxThud, volume: 0.7)
        let appear: SKAction
        if reduceMotion {
            badge.alpha = 0
            appear = .fadeIn(withDuration: 0.12)
        } else {
            appear = Effects.pop()
        }
        await director.run(.sequence([appear, .wait(forDuration: 0.12)]), on: badge)
        let away: SKAction = reduceMotion
            ? .sequence([.wait(forDuration: 0.2), .fadeOut(withDuration: 0.2)])
            : .sequence([
                .wait(forDuration: 0.16),
                .group([.fadeOut(withDuration: 0.25), .moveBy(x: 0, y: 18, duration: 0.25), .scale(to: 1.3, duration: 0.25)]),
            ])
        background([(away, badge)]) { badge.removeFromParent() }
    }

    // MARK: lay down and hit

    /// The cards fly one by one (40 ms apart) from the trays / hand / cat to where the row
    /// will draw them, each landing with a squash, a few stars and a pop.
    private func animateLayDown(seat: Seat, groups: [Group]) async {
        guard let layout, let game = model?.game else { return }
        let cards = groups.flatMap(\.cards)
        let targets = laidZone.landing(groups: groups, seat: seat, total: game.laid.count, layout: layout)
            .flatMap { $0 }.map { fx.convert($0, from: laidZone.parent ?? self) }
        let endScale = laidZone.miniScale(layout: layout)
        let mine = seat == bottomSeat

        // Starting points first (tray frames are gone once those cards hide).
        var starts: [(point: CGPoint, scale: CGFloat, rotation: CGFloat)] = []
        for card in cards {
            if mine, let f = trays.frame(of: card) {
                starts.append((fx.convert(CGPoint(x: f.midX, y: f.midY), from: trays.parent ?? self), f.width / layout.cardSize.width, 0))
            } else if mine, let h = hand.node(for: card) {
                starts.append((fx.convert(h.position, from: hand), 1, h.zRotation))
                h.alpha = 0
            } else if mine {
                starts.append((handLanding(layout).position, 1, 0))
            } else {
                starts.append((seatPoint(seat), 0.35, 0))
            }
        }
        if mine, !trays.isHidden { trays.show(trayState, hidden: Set(cards), targets: false) }

        let director = director
        let fx = self.fx
        var items: [(SKAction, SKNode)] = []
        var nodes: [CardNode] = []
        for (i, card) in cards.enumerated() where i < targets.count {
            let s = starts[i]
            let node = flyer(card, at: s.point, scale: s.scale, rotation: s.rotation, z: 0.5 + CGFloat(i) * 0.01)
            let land = SKAction.run { [weak node] in
                guard let node else { return }
                Sound.shared.play(ArtName.Sound.sfxPop, volume: 0.8)
                Effects.burst(.stars, at: node.position, in: fx, director: director)
            }
            items.append((.sequence([
                .wait(forDuration: Double(i) * 0.04),
                Effects.fly(from: s.point, to: targets[i], duration: 0.3, lift: 36, scale: endScale),
                land, Effects.squash(),
            ]), node))
            nodes.append(node)
        }
        await director.runAll(items)
        Haptics.shared.success()
        transients += nodes
    }

    /// The card arcs onto its place in the group, which bumps.
    private func animateHit(seat: Seat, card: CardID, target: HitTarget, group: Group) async {
        guard let layout else { return }
        let node: CardNode
        var owned = false
        if card == provisionalCard, let p = provisionalNode {
            node = p
            node.isPrivate = false  // accepted: the card is on the table now
            owned = true
        } else if seat == bottomSeat, let h = hand.node(for: card) {
            node = flyer(card, at: fx.convert(h.position, from: hand), rotation: h.zRotation, z: 1)
            h.alpha = 0
        } else {
            node = flyer(card, at: seatPoint(seat), scale: 0.4, z: 1)
        }
        let zoneSpace = laidZone.parent ?? self
        let end: CGPoint
        if let p = laidZone.landing(hit: card, seat: target.seat, index: target.group, group: group) {
            end = fx.convert(p, from: zoneSpace)
        } else if let f = laidZone.groupFrames(seat: target.seat)[safe: target.group] {
            end = fx.convert(CGPoint(x: f.maxX, y: f.midY), from: zoneSpace)
        } else {
            end = point(of: discard)
        }
        await director.run(
            Effects.fly(from: node.position, to: local(end, for: node), duration: 0.3, lift: 40,
                        scale: laidZone.miniScale(layout: layout)),
            on: node)
        Sound.shared.play(ArtName.Sound.sfxPop)
        Haptics.shared.drop()
        Effects.burst(.stars, at: end, in: fx, director: director)
        var items: [(SKAction, SKNode)] = [(Effects.squash(), node)]
        for (i, n) in laidZone.groupNodes(seat: target.seat, index: target.group).enumerated() {
            items.append((.sequence([
                .wait(forDuration: Double(i) * 0.02),
                .scale(to: 1.18, duration: 0.08).eased(.easeOut),
                .scale(to: 1, duration: 0.1).eased(.easeIn),
            ]), n))
        }
        background(items)
        if !owned { transients.append(node) }
    }

    // MARK: turn

    /// Turn handoff: the outgoing ring shrinks, the incoming one pops and pulses. On my turn
    /// the hand bounces up and the piles flare (the local seat has no ring).
    private func animateTurn(_ seat: Seat) async {
        guard let model else { return }
        if let old = model.game?.turn, old != seat, let cat = opponents.node(for: old) {
            await director.runAll(cat.turnOut(reduceMotion: reduceMotion), decorative: true)
        }
        var items: [(SKAction, SKNode)] = []
        if seat != bottomSeat, let cat = opponents.node(for: seat), cat.setActive(true) {
            items += cat.turnPulse(reduceMotion: reduceMotion)
        }
        if seat == bottomSeat || model.mySeats.contains(seat) {
            Sound.shared.play(ArtName.Sound.sfxTick)
            items.append(deck.flare())
            if let top = model.game?.discardTop, Card(id: top) != .cucumber { items.append(discard.flare()) }
            if !reduceMotion { items.append((hop(height: 22), hand)) }
        }
        background(items)
    }

    // MARK: reshuffle and deal

    /// The discard riffles into the deck with a whoosh.
    private func animateReshuffle() async {
        let from = point(of: discard)
        let to = point(of: deck)
        Sound.shared.play(ArtName.Sound.sfxWhoosh)
        var items: [(SKAction, SKNode)] = []
        var nodes: [CardNode] = []
        for i in 0..<(reduceMotion ? 3 : 5) {
            let side: CGFloat = i.isMultiple(of: 2) ? -1 : 1
            let start = CGPoint(x: from.x + side * 3, y: from.y + CGFloat(i))
            let node = flyer(nil, at: start, rotation: side * 0.08, z: 0.2 + CGFloat(i) * 0.01)
            items.append((.sequence([
                .wait(forDuration: Double(i) * 0.035),
                Effects.fly(from: start, to: to, duration: 0.24, lift: 22 + CGFloat(i % 3) * 8, rotation: 0),
            ]), node))
            nodes.append(node)
        }
        await director.runAll(items)
        nodes.forEach { $0.removeFromParent() }
        background([(Effects.squash(), deck)], decorative: false)
    }

    /// A new round is dealt: cards from the deck to each seat in turn from the dealer's left,
    /// 25 ms apart; the bottom seat's land in its fan.
    func animateDeal(dealer: Seat) async {
        guard let layout, let game = model?.game else { return }
        let seats = max(game.handCounts.count, 1)
        let perSeat = 10
        let order = (1...seats).map { (dealer + $0) % seats }
        let start = point(of: deck)
        let slots = layout.hand(count: perSeat, lifted: nil).map { (fx.convert($0.position, from: hand), $0.rotation) }
        hand.isHidden = true
        laidZone.isHidden = true
        Sound.shared.play(ArtName.Sound.sfxWhoosh)

        var items: [(SKAction, SKNode)] = []
        var landed: [CardNode] = []
        var gone: [CardNode] = []
        var i = 0
        for round in 0..<perSeat {
            for seat in order {
                let node = flyer(nil, at: start, z: 0.3 + CGFloat(i) * 0.001)
                let sound: SKAction = i.isMultiple(of: 4)
                    ? .run { Sound.shared.play(ArtName.Sound.sfxFlip, volume: 0.35) } : .wait(forDuration: 0)
                let lead = SKAction.sequence([.wait(forDuration: Double(i) * 0.025), sound])
                if seat == bottomSeat {
                    let (p, r) = slots[round]
                    items.append((.sequence([lead, Effects.fly(from: start, to: p, duration: 0.26, lift: 30, rotation: r)]), node))
                    landed.append(node)
                } else {
                    items.append((.sequence([
                        lead, Effects.fly(from: start, to: seatPoint(seat), duration: 0.26, lift: 24, scale: 0.3),
                        .fadeOut(withDuration: 0.06),
                    ]), node))
                    gone.append(node)
                }
                i += 1
            }
        }
        await director.runAll(items)
        gone.forEach { $0.removeFromParent() }
        transients += landed
    }

    // MARK: idle

    /// One idle flourish (spec §9.2): a random cat in the bar blinks.
    func idleFlourish() {
        guard view != nil, !animating, input.source == .none, !celebration.announced,
              let cat = opponents.order.compactMap({ opponents.node(for: $0) }).randomElement() else { return }
        let (action, node) = cat.blink()
        let director = director
        Task { await director.run(action, on: node, decorative: true) }
    }

    // MARK: geometry

    /// A temporary card in the fx layer.
    private func flyer(_ card: CardID?, at p: CGPoint, scale: CGFloat = 1, rotation: CGFloat = 0, z: CGFloat = 0) -> CardNode {
        let node = CardNode(card: card, size: layout?.cardSize ?? CardFaceFactory.cardSize)
        node.position = p
        node.setScale(scale)
        node.zRotation = rotation
        node.zPosition = z
        fx.addChild(node)
        return node
    }

    /// A node's position in fx space.
    private func point(of node: SKNode) -> CGPoint {
        fx.convert(node.position, from: node.parent ?? self)
    }

    /// An fx-space point in `node`'s parent space (the provisional card lives in `drag`).
    private func local(_ p: CGPoint, for node: SKNode) -> CGPoint {
        guard let parent = node.parent, parent !== fx else { return p }
        return parent.convert(p, from: fx)
    }

    /// A seat's spot in fx space: its cat in the bar, or the middle of the hand.
    private func seatPoint(_ seat: Seat) -> CGPoint {
        if seat != bottomSeat, let cat = opponents.node(for: seat) {
            return fx.convert(cat.position, from: opponents)
        }
        if let layout, let mid = layout.hand(count: 1, lifted: nil).first {
            return fx.convert(mid.position, from: hand)
        }
        return CGPoint(x: size.width / 2, y: size.height - 60)
    }

    /// Where a card joining the hand lands: the right end of the fan with one more card.
    private func handLanding(_ layout: TableLayout) -> CardPlacement {
        let placements = layout.hand(count: hand.cards.count + 1, lifted: nil)
        let p = placements[placements.count - 1]
        return CardPlacement(position: fx.convert(p.position, from: hand), rotation: p.rotation, z: p.z)
    }
}
