import PounceKit
import SpriteKit

/// What the first-game coach needs from the table as drawn: the face-up hand's facts (for
/// `Coach`) and where the things a tip points at are, in scene space (origin bottom-left).
struct TableCoach: Equatable {
    var context: CoachContext
    var person: Person
    /// An event is animating or an action is in flight: the table is about to change.
    var busy: Bool
    var anchors: Anchors

    struct Anchors: Equatable {
        /// The folded tower's tab.
        var tower: CGRect
        var deck: CGRect
        var discard: CGRect
        var trays: CGRect
        var layDown: CGRect?
        /// Every laid group on the table.
        var laid: CGRect?
        var hand: CGRect
        var yarn: CGRect?
        var cucumber: CGRect?
        /// The cats in the top bar, with their name pills.
        var cats: CGRect?
        /// The open tower.
        var openTower: CGRect?
        /// A strip down the screen's left edge, where the swipe home starts.
        var edge: CGRect = .zero
    }
}

extension TableScene {
    /// The coach's view of the table for the hand shown face up, or nil when none is.
    func coachSnapshot() -> TableCoach? {
        guard let model, let game = model.game, let layout, let bottom = bottomSeat, bottom == shownRevealed,
              let person = model.room.seats[safe: bottom]?.person, !hand.cards.isEmpty else { return nil }
        let faces = hand.cards.compactMap(\.card)
        let myTurn = model.isMyTurn && model.currentSeat == bottom && game.status == .playing
        let phase = model.trays(for: bottom)
        let canHit = phase.isEmpty && faces.contains { !model.hitTargets(card: $0, seat: bottom).isEmpty }
        let layDownShown = !trays.isHidden && !trays.layDownButton.isHidden
        func cardFrame(_ match: (Card) -> Bool) -> CGRect? {
            hand.cards.indices.first { hand.cards[$0].card.map { match(Card(id: $0)) } ?? false }
                .flatMap { hand.frame(at: $0) }
        }
        let laidFrames = laidZone.laidSeats.flatMap { laidZone.groupFrames(seat: $0) }
        let handFrame = hand.cards.indices.compactMap { hand.frame(at: $0) }.reduce(CGRect.null) { $0.union($1) }
        let context = CoachContext(
            person: person.id, epoch: store.turnEpoch, myTurn: myTurn, step: game.step, phase: phase,
            layDownReady: layDownShown, canHit: canHit,
            hasYarn: faces.contains { Card(id: $0) == .yarn },
            hasCucumber: faces.contains { Card(id: $0) == .cucumber },
            handCount: game.hands[bottom]?.count ?? faces.count,
            others: !opponents.order.isEmpty, towerOpen: tower.isOpen)
        let cats = opponents.order.compactMap { opponents.frame(of: $0) }.reduce(CGRect.null) { $0.union($1) }
        let zone = layout.laidZone
        let anchors = TableCoach.Anchors(
            tower: layout.towerTab, deck: deck.hitFrame, discard: discard.hitFrame,
            trays: layout.traysFrame, layDown: layDownShown ? layDownFrame : nil,
            laid: laidFrames.isEmpty ? nil : laidFrames.reduce(CGRect.null) { $0.union($1) },
            hand: handFrame,
            yarn: cardFrame { $0 == .yarn }, cucumber: cardFrame { $0 == .cucumber },
            cats: cats.isNull ? nil : CGRect(x: cats.minX, y: cats.minY - 36, width: cats.width, height: cats.height + 38),
            openTower: tower.isOpen ? TowerNode.openFrame(layout) : nil,
            edge: CGRect(x: 0, y: zone.midY - 70, width: 26, height: 140))
        return TableCoach(
            context: context, person: person, busy: animating || store.actionInFlight || discardHold != nil, anchors: anchors)
    }
}

/// A discard waiting on the pile, for the Undo pill the shell draws under it.
struct UndoOffer: Equatable {
    let serial: Int
    /// The discard pile, in scene space.
    let pile: CGRect
    /// How long Undo is offered, at normal speed.
    let seconds: Double
}
