import PounceKit
import SpriteKit
import UIKit

/// Where the current touch started and whether it became a drag.
struct TableInputState {
    enum Source: Equatable {
        case none, menu, sort, layDown, tower, other
        case hand(CardID)
        case tray(CardID, Int)
        case pile(DrawSource)

        var isTray: Bool {
            if case .tray = self { return true }
            return false
        }
    }

    var source: Source = .none
    var start: CGPoint = .zero
    var dragging = false
    var dragNode: CardNode?
    /// Card center minus finger, so the card doesn't jump under the finger.
    var grab: CGVector = .zero
    /// The dragged card is lifted clear of the laid group it would hit.
    var lifted = false

    /// A finger that moves further than this is dragging, not tapping.
    static let dragThreshold: CGFloat = 10
}

/// The bottom seat's trays belong to one seat and round.
struct TrayKey: Equatable {
    let seat: Seat
    let round: Int
}

/// What the in-flight action was, so a rejection nopes the right node.
enum LastAct: Equatable {
    case card(CardID)
    case draw(DrawSource)
    case layDown
}

/// Legal targets lit for the current step and held card (spec §5.7, §9.1 Glow).
struct Glows: Equatable {
    var piles: Set<DrawSource> = []
    /// The discard pile takes the held card.
    var discard = false
    /// Seats a held Cucumber can be aimed at.
    var cats: Set<Seat> = []
    var groups: Set<HitTarget> = []
    var trays = false
    var enlarge = false
    var layDown = false
}

/// Table interactions (spec §5.7–5.8, §13): draw, discard, aim a Cucumber, lay down through
/// the trays and hit, each by drag or by tap-tap (select a card, then tap a target), plus
/// VoiceOver custom actions. The server stays the authority: client checks only decide what
/// glows and what gets sent. At most one action is in flight; while it is, only local moves
/// (select, reorder, sort) respond.
extension TableScene {
    // MARK: gating

    /// The seat this phone may act for right now: its turn, its hand showing, nothing in flight
    /// and no event still animating (the drawn table is about to change).
    var actingSeat: Seat? {
        guard !animating, let model, let bottom = bottomSeat, bottom == shownRevealed, model.isMyTurn,
              model.currentSeat == bottom, !store.actionInFlight, store.phase == .playing else { return nil }
        return bottom
    }

    /// The hand card being dragged or selected.
    private var heldHandCard: CardID? {
        if input.dragging, case .hand(let card) = input.source { return card }
        return liftedCard
    }

    func computeGlows() -> Glows {
        var g = Glows()
        guard let model, let seat = actingSeat else { return g }
        g.piles = model.drawSources(for: seat)
        guard model.canPlay(seat) else { return g }
        g.trays = !trayState.requirements.isEmpty
        g.layDown = trayState.allValid
        if let card = heldHandCard {
            let aims = model.skipTargets(for: seat)
            if Card(id: card) == .cucumber, !aims.isEmpty {
                g.cats = Set(aims)
            } else {
                g.discard = true
            }
            g.groups = Set(model.hitTargets(card: card, seat: seat))
            g.enlarge = !g.groups.isEmpty
        }
        return g
    }

    // MARK: touches

    func inputBegan(_ p: CGPoint) {
        input = TableInputState()
        input.start = p
        input.source = source(at: p)
    }

    func inputMoved(_ p: CGPoint) {
        guard input.source != .none else { return }
        if !input.dragging {
            guard hypot(p.x - input.start.x, p.y - input.start.y) > TableInputState.dragThreshold,
                  beginDrag() else { return }
        }
        if let node = input.dragNode {
            let free = CGPoint(x: p.x + input.grab.dx, y: p.y + input.grab.dy)
            let lift = aimHit(finger: p)
            place(node, at: lift ?? free, scale: lift == nil ? Self.dragScale : Self.liftScale, settle: (lift != nil) != input.lifted)
            input.lifted = lift != nil
            followDrag(node, finger: p)
        }
    }

    func inputEnded(_ p: CGPoint) {
        let state = input
        input = TableInputState()
        if state.dragging {
            let landing = Landing(gap: dragGap, from: state.dragNode.map { hand.convert($0.position, from: layer(.drag)) })
            dragGap = nil
            state.dragNode?.removeFromParent()
            dragCard = nil
            drop(state.source, at: p, landing: landing)
            if provisionalCard == nil { showHitPreview(nil) }  // no hit went out: close any gap
        } else if hypot(p.x - state.start.x, p.y - state.start.y) <= TableInputState.dragThreshold * 2 {
            tap(state.source, at: p)
        }
    }

    func inputCancelled() {
        input.dragNode?.removeFromParent()
        let wasDragging = input.dragging
        input = TableInputState()
        dragGap = nil
        dragCard = nil
        showHitPreview(nil)
        if wasDragging { refresh() }
    }

    private func source(at p: CGPoint) -> TableInputState.Source {
        if !menuHidden, menuFrame.contains(p) { return .menu }
        if towerFrame.contains(p), layout.map({ p.y > $0.traysFrame.maxY }) ?? false { return .tower }
        if !trays.isHidden, !trays.layDownButton.isHidden, layDownFrame.contains(p) { return .layDown }
        if let card = hand.card(at: p) { return .hand(card) }
        if !trays.isHidden, let hit = trays.card(at: p) { return .tray(hit.card, hit.tray) }
        if !sortButton.isHidden, sortFrame.contains(p) { return .sort }
        if deck.hitFrame.contains(p) { return .pile(.deck) }
        if discard.hitFrame.contains(p) { return .pile(.discard) }
        return .other
    }

    /// Turns the touch into a drag when its source can move; false keeps it a tap.
    private func beginDrag() -> Bool {
        guard let layout else { return false }
        let node: CardNode
        let from: CGPoint
        switch input.source {
        case .hand(let card):
            guard let n = hand.node(for: card) else { return false }
            from = layer(.hand).convert(n.position, from: hand)
            node = CardNode(card: card, size: layout.cardSize)
            node.isPrivate = true  // my hand's face: `hideHand()` turns it down mid-drag
        case .tray(let card, _):
            guard !store.actionInFlight, let f = trays.frame(of: card) else { return false }
            from = CGPoint(x: f.midX, y: f.midY)
            node = CardNode(card: card, size: layout.cardSize)
            node.isPrivate = true
        case .pile(let source):
            guard let seat = actingSeat, model?.drawSources(for: seat).contains(source) == true else { return false }
            from = source == .deck ? deck.position : discard.position
            node = CardNode(card: source == .deck ? nil : model?.game?.discardTop, size: layout.cardSize)
        default:
            return false
        }
        input.dragging = true
        input.grab = CGVector(dx: from.x - input.start.x, dy: from.y - input.start.y)
        node.position = from
        node.setScale(Self.dragScale)
        node.zPosition = 0
        layer(.drag).addChild(node)
        input.dragNode = node
        Haptics.shared.tick()
        switch input.source {
        case .hand(let card), .tray(let card, _):
            // A hand card leaves its own slot open, so nothing moves until the finger does.
            if case .hand = input.source { dragGap = hand.cards.firstIndex { $0.card == card } }
            selectionForDrag(card)
        default:
            refresh()
        }
        return true
    }

    /// The dragged card leaves the fan (or tray) and the targets for it light up.
    private func selectionForDrag(_ card: CardID) {
        if liftedCard != card { liftedCard = nil }
        dragCard = card
    }

    /// Live reorder: while a hand card (or one coming back from a tray) is over the hand area,
    /// the fan holds open the slot it would land in, sliding the others apart as that slot
    /// changes, with a light tick each time. Outside the hand area the fan closes up.
    private func followDrag(_ node: CardNode, finger p: CGPoint) {
        guard let layout, case .faces = hand.content else { return }
        switch input.source {
        case .hand, .tray: break
        default: return
        }
        let next: Int? = isOverHand(p, layout)
            ? layout.handSlot(x: hand.convert(node.position, from: layer(.drag)).x, count: hand.cards.count + 1, current: dragGap)
            : nil
        guard next != dragGap else { return }
        dragGap = next
        if next != nil {
            Haptics.shared.tick()
            #if DEBUG
            dragProbe.changes += 1
            #endif
        }
        let moves = hand.slide(gap: next, layout: layout)
        guard !moves.isEmpty else { return }
        let director = director
        director.cancelActions(under: hand)  // a slide still running gives way to the new one
        Task { await director.runAll(moves) }
    }

    /// A dragged card at full size, and lifted over a laid group (small enough to leave the
    /// group's gap in view).
    static let dragScale: CGFloat = 1.08
    static let liftScale: CGFloat = 0.8
    /// How long the dragged card takes to lift clear of a laid group or come back down.
    static let liftDuration: TimeInterval = 0.12

    /// Moves the dragged card: straight to `point`, or eased there while it lifts, lands or is
    /// still settling (the scene's speed is the Pace).
    private func place(_ node: CardNode, at point: CGPoint, scale: CGFloat, settle: Bool) {
        guard settle || node.action(forKey: "lift") != nil else {
            node.position = point
            return
        }
        let d = Self.liftDuration
        node.run(.group([.move(to: point, duration: d), .scale(to: scale, duration: d)]).eased(.easeOut), withKey: "lift")
    }

    /// Live hit preview: while a hand card is over a laid group, that group shows where the
    /// card would land, or that it can't take it, with a light tick each time the group or the
    /// end changes. Returns where the card floats meanwhile (above the group, clear of the gap),
    /// or nil away from the laid groups.
    private func aimHit(finger p: CGPoint) -> CGPoint? {
        guard case .hand(let card) = input.source, let layout else { return nil }
        let aim = laidDrop(at: p).map { d in
            HitPreview(target: d.target, card: card,
                       plan: actingSeat.flatMap { model?.hitPlan(card: card, seat: $0, target: d.target, toward: d.toward) })
        }
        let old = laidZone.preview
        showHitPreview(aim)
        guard let aim, let f = laidZone.shownFrame(of: aim.target) else { return nil }
        if aim.target != old?.target || aim.plan?.index != old?.plan?.index || (aim.plan == nil) != (old?.plan == nil) {
            Haptics.shared.tick()
            #if DEBUG
            hitProbe.aims += 1
            #endif
        }
        let h = layout.cardSize.height * Self.liftScale
        return CGPoint(x: p.x, y: min(f.maxY + 10 + h / 2, size.height - h / 2))
    }

    /// Shows `preview` in the laid zone, sliding its groups open or closed.
    func showHitPreview(_ preview: HitPreview?) {
        let moves = laidZone.setPreview(preview)
        guard !moves.isEmpty else { return }
        let director = director
        director.cancelActions(under: laidZone)  // a slide still running gives way to the new one
        Task { await director.runAll(moves) }
    }

    /// The laid group (and its end) a hand card let go at `p` would hit: nothing where the
    /// discard pile, a cat or a tray takes the drop first.
    private func laidDrop(at p: CGPoint) -> (target: HitTarget, toward: HitSide)? {
        if discard.hitFrame.insetBy(dx: -12, dy: -12).contains(p) || opponentSeat(at: p) != nil { return nil }
        if !trays.isHidden, trays.tray(at: p) != nil { return nil }
        return laidZone.drop(at: p)
    }

    /// A drop here reorders the hand (the fan and the strip just above it, below the trays).
    private func isOverHand(_ p: CGPoint, _ layout: TableLayout) -> Bool {
        p.y < layout.traysFrame.minY
    }

    // MARK: drops

    /// Where a dragged card was let go: the fan slot held open for it (nil outside the hand
    /// area) and its center in hand space, for the glide into that slot.
    struct Landing {
        var gap: Int?
        var from: CGPoint?
    }

    private func drop(_ source: TableInputState.Source, at p: CGPoint, landing: Landing) {
        // One action in flight at a time: game drops are ignored (no nope, nothing sent);
        // only reordering the hand still works.
        if store.actionInFlight {
            if case .hand(let card) = source, let layout, isOverHand(p, layout) {
                reorder(card, landing)
            } else {
                refresh()
            }
            return
        }
        switch source {
        case .hand(let card):
            dropHandCard(card, at: p, landing: landing)
        case .tray(let card, let tray):
            dropTrayCard(card, from: tray, at: p, landing: landing)
        case .pile(let pile):
            guard let layout else { return refresh() }
            // Anywhere over the hand or the trays counts as "to the hand".
            if p.y < layout.traysFrame.maxY + 12 {
                if !tryDraw(pile) { nope(pile: pile) }
            } else {
                refresh()
            }
        default:
            refresh()
        }
    }

    private func dropHandCard(_ card: CardID, at p: CGPoint, landing: Landing) {
        if discard.hitFrame.insetBy(dx: -12, dy: -12).contains(p) { return chooseDiscard(card) }
        if let seat = opponentSeat(at: p) { return aim(card, at: seat) }
        if !trays.isHidden, let tray = trays.tray(at: p) {
            if !tryTray(card, tray) { nope(card: card) }
            return
        }
        if let aim = laidDrop(at: p) {
            if !tryHit(card, aim.target, toward: aim.toward) { nope(card: card) }
            return
        }
        if let layout, isOverHand(p, layout) {
            reorder(card, landing)
            return
        }
        refresh()  // dropped on nothing: back to its place
    }

    private func dropTrayCard(_ card: CardID, from tray: Int, at p: CGPoint, landing: Landing) {
        if !trays.isHidden, let target = trays.tray(at: p) {
            if target == tray {
                if Card(id: card) == .yarn, trayState.requirements[safe: tray]?.kind == .run {
                    let index = trays.slotIndex(tray: tray, x: p.x, count: trayState.slots[tray].count)
                    trayState.moveYarn(card, inTray: tray, toIndex: index)
                }
                refresh()
            } else if !tryTray(card, target) {
                refresh()
                nope(card: card)
            }
            return
        }
        guard let layout, isOverHand(p, layout), let gap = landing.gap else { return returnFromTray(card, toSlot: nil) }
        returnFromTray(card, toSlot: gap)
        settle(card, from: landing.from)
    }

    // MARK: taps

    private func tap(_ source: TableInputState.Source, at p: CGPoint) {
        if trayYarn != nil, !source.isTray {
            trayYarn = nil  // a picked-up Yarn goes back down on any other tap
            refresh()
        }
        if actingSeat == nil, liftedCard == nil {
            switch source {
            case .none, .other, .pile: onTableTap()
            default: break
            }
        }
        if store.actionInFlight {
            // Only local taps while an action is in flight.
            switch source {
            case .menu: onMenu()
            case .tower: showScoreboard()
            case .sort: cycleSort()
            case .hand(let card): liftedCard = liftedCard == card ? nil : card
            default: break
            }
            return
        }
        switch source {
        case .none:
            break
        case .menu:
            onMenu()
        case .tower:
            showScoreboard()
        case .sort:
            cycleSort()
        case .layDown:
            if !tryLayDown() { nope(node: trays.layDownButton) }
        case .hand(let card):
            liftedCard = liftedCard == card ? nil : card
            Haptics.shared.tick()
        case .tray(let card, let tray):
            if let held = liftedCard {
                if !tryTray(held, tray) { nope(card: held) }
            } else if let pick = trayYarn {
                tapWithYarn(pick, on: card, in: tray)
            } else if trayState.canMoveYarn(card, inTray: tray) {
                // Tap path for placing a Yarn (spec §13): pick it up, then tap its new slot.
                trayYarn = (card, tray)
                Haptics.shared.tick()
                refresh()
            } else {
                returnFromTray(card, toSlot: nil)
            }
        case .pile(let pile):
            if let seat = actingSeat, model?.drawSources(for: seat).contains(pile) == true {
                _ = tryDraw(pile)
            } else if let held = liftedCard {
                if pile == .discard { chooseDiscard(held) } else { nope(card: held) }
            }
        case .other:
            tapTarget(at: p)
        }
    }

    /// A tap on a tray card while a Yarn is picked up: another slot of its tray moves the Yarn
    /// there (`TrayState.moveYarn`); the Yarn itself goes back to the hand; another tray drops
    /// the pick.
    private func tapWithYarn(_ pick: (card: CardID, tray: Int), on card: CardID, in tray: Int) {
        trayYarn = nil
        if card == pick.card {
            returnFromTray(card, toSlot: nil)
            return
        }
        guard tray == pick.tray, let index = trayState.slots[tray].firstIndex(of: card) else { return refresh() }
        let before = trayState
        trayState.moveYarn(pick.card, inTray: tray, toIndex: index)
        refresh()
        if trayState == before {
            nope(node: nil)  // no run puts the Yarn there
        } else {
            Haptics.shared.tick()
        }
    }

    /// The tower tap: the scoreboard for the table as drawn.
    private func showScoreboard() {
        guard let model else { return }
        onTower(model)
    }

    /// The second tap of tap-tap: a cat, a tray or a laid group for the selected card.
    private func tapTarget(at p: CGPoint) {
        guard let held = liftedCard else { return }
        if let seat = opponentSeat(at: p) { return aim(held, at: seat) }
        if !trays.isHidden, let tray = trays.tray(at: p) {
            if !tryTray(held, tray) { nope(card: held) }
            return
        }
        if let aim = laidZone.drop(at: p) {
            if !tryHit(held, aim.target, toward: aim.toward) { nope(card: held) }
            return
        }
        liftedCard = nil
    }

    private func opponentSeat(at p: CGPoint) -> Seat? {
        opponents.order.first { opponents.frame(of: $0)?.insetBy(dx: -6, dy: -6).contains(p) == true }
    }

    // MARK: moves

    /// Draws from `source` when it glows.
    @discardableResult func tryDraw(_ source: DrawSource) -> Bool {
        guard let seat = actingSeat, let model, model.drawSources(for: seat).contains(source),
              store.act(seat: seat, .draw(source)) else { return false }
        lastAct = .draw(source)
        liftedCard = nil
        Haptics.shared.tick()
        refresh()
        return true
    }

    /// A card was dropped on (or tapped onto) the discard pile. A Cucumber with seats to aim
    /// at stays selected so the cats glow; it is sent only once a cat is picked.
    private func chooseDiscard(_ card: CardID) {
        guard let seat = actingSeat, let model, model.canPlay(seat) else { return nope(card: card) }
        if Card(id: card) == .cucumber, !model.skipTargets(for: seat).isEmpty {
            if liftedCard == card { refresh() } else { liftedCard = card }
            Haptics.shared.tick()
            return
        }
        if !tryDiscard(card, target: nil) { nope(card: card) }
    }

    private func aim(_ card: CardID, at seat: Seat) {
        guard Card(id: card) == .cucumber, tryDiscard(card, target: seat) else { return nope(card: card) }
    }

    /// Sends the discard. A Cucumber needs a legal target whenever one exists; with none it
    /// goes out plain (`TableModel.discardAction`).
    @discardableResult func tryDiscard(_ card: CardID, target: Seat?) -> Bool {
        guard let seat = actingSeat, let model, model.canPlay(seat) else { return false }
        if Card(id: card) == .cucumber {
            let aims = model.skipTargets(for: seat)
            if !aims.isEmpty {
                guard let target, aims.contains(target) else { return false }
            }
        }
        guard store.act(seat: seat, model.discardAction(card: card, target: target)) else { return false }
        lastAct = .card(card)
        Haptics.shared.drop()
        provisionalMove(card: card, to: discard.position)
        return true
    }

    @discardableResult func tryTray(_ card: CardID, _ tray: Int) -> Bool {
        guard let seat = actingSeat, model?.canPlay(seat) == true, !trays.isHidden,
              trayState.requirements.indices.contains(tray), trayState.tray(of: card) != tray,
              !trayState.isFull(tray) else { return false }
        trayState.add(card, to: tray)
        if liftedCard == card { liftedCard = nil }
        Haptics.shared.tick()
        refresh()
        return true
    }

    /// Hits `target` with `card`, on the end of a run it was dropped toward (a natural goes
    /// where it fits). The card waits in the gap the group opens for it until the server answers.
    @discardableResult func tryHit(_ card: CardID, _ target: HitTarget, toward: HitSide) -> Bool {
        guard let seat = actingSeat, let model, let plan = model.hitPlan(card: card, seat: seat, target: target, toward: toward),
              store.act(seat: seat, plan.action) else { return false }
        lastAct = .card(card)
        Haptics.shared.drop()
        #if DEBUG
        if case .hit(_, _, let side) = plan.action { hitProbe.sent = "\(target.seat).\(target.group).\(side?.rawValue ?? "-")" }
        #endif
        showHitPreview(HitPreview(target: target, card: card, plan: plan, ghost: false))
        let spot = laidZone.landing(hit: card, seat: target.seat, index: target.group, group: plan.group)
        let f = laidZone.groupFrames(seat: target.seat)[safe: target.group] ?? .zero
        provisionalMove(card: card, to: spot ?? CGPoint(x: f.maxX, y: f.midY), scale: layout.map { laidZone.miniScale(layout: $0) } ?? 0.6)
        return true
    }

    @discardableResult func tryLayDown() -> Bool {
        guard let seat = actingSeat, model?.canPlay(seat) == true, trayState.allValid,
              store.act(seat: seat, .layDown(trayState.layGroups())) else { return false }
        lastAct = .layDown
        Haptics.shared.success()
        refresh()
        return true
    }

    /// Takes a card out of its tray, optionally dropping it into slot `slot` of the fan.
    func returnFromTray(_ card: CardID, toSlot slot: Int?) {
        trayState.remove(card)
        if let slot { reorderInPlace(card, toSlot: slot) }
        refresh()
    }

    /// A hand card let go over the hand: it takes the slot the fan held open for it and
    /// glides in.
    private func reorder(_ card: CardID, _ landing: Landing) {
        if let gap = landing.gap { reorderInPlace(card, toSlot: gap) }
        refresh()
        settle(card, from: landing.from)
    }

    private func reorderInPlace(_ card: CardID, toSlot slot: Int) {
        guard let seat = bottomSeat else { return }
        handOrders[seat]?.move(card, toSlot: slot, shown: hand.cards.compactMap(\.card))
        #if DEBUG
        dragProbe.landed = slot
        #endif
    }

    /// The dropped card glides from where it was let go into its slot; the rest of the fan is
    /// already in place.
    private func settle(_ card: CardID, from start: CGPoint?) {
        guard let start, let node = hand.node(for: card) else { return }
        let end = (position: node.position, rotation: node.zRotation, z: node.zPosition)
        node.position = start
        node.zRotation = 0
        node.setScale(1.08)
        node.zPosition = HandNode.liftedZ
        let glide = SKAction.group([
            .move(to: end.position, duration: Self.settleDuration),
            .rotate(toAngle: end.rotation, duration: Self.settleDuration, shortestUnitArc: true),
            .scale(to: 1, duration: Self.settleDuration),
        ])
        glide.timingMode = .easeOut
        let director = director
        Task { await director.run(.sequence([glide, .run { node.zPosition = end.z }]), on: node) }
    }

    /// The glide of a dropped card into its slot, at normal speed (scene speed is the Pace).
    static let settleDuration: TimeInterval = 0.16

    func cycleSort() {
        guard let seat = bottomSeat else { return }
        handOrders[seat]?.cycleSort()
        Haptics.shared.tick()
        refresh()
    }

    /// The server refused the in-flight action.
    func rejected() {
        let act = lastAct
        lastAct = nil
        if provisionalCard != nil {
            rollbackProvisional()
            return
        }
        switch act {
        case .layDown: nope(node: trays.layDownButton)
        case .draw(let pile): nope(pile: pile)
        case .card(let card): nope(card: card)
        case nil: nope(node: nil)
        }
    }

    // MARK: nope

    /// The Nope verb (spec §9.1) on a hand or tray card: three quick wiggles, a soft thud.
    func nope(card: CardID?) {
        nope(node: card.flatMap { hand.node(for: $0) })
    }

    private func nope(pile: DrawSource) {
        nope(node: pile == .deck ? deck : discard)
    }

    func nope(node: SKNode?) {
        Haptics.shared.drop()
        Sound.shared.play(ArtName.Sound.sfxNope)
        guard let node, !node.isHidden else { return }
        let action = Effects.nope()
        let director = director
        Task { await director.run(action, on: node) }
    }

    // MARK: VoiceOver custom actions

    private func customAction(_ name: String, _ body: @escaping @MainActor () -> Bool) -> UIAccessibilityCustomAction {
        UIAccessibilityCustomAction(name: name) { _ in MainActor.assumeIsolated { body() } }
    }

    /// "Draw" on a pile that glows.
    func drawActions(_ source: DrawSource) -> [UIAccessibilityCustomAction] {
        guard glows.piles.contains(source) else { return [] }
        return [customAction(String(localized: "Draw", comment: "VoiceOver action: draw from this pile")) { [weak self] in
            self?.tryDraw(source) ?? false
        }]
    }

    /// "Discard" (or one aimed discard per seat for a Cucumber), "Put in tray N",
    /// "Add to group" for a hand card in the play step.
    func handCardActions(_ card: CardID) -> [UIAccessibilityCustomAction] {
        guard let model, let seat = actingSeat, model.canPlay(seat) else { return [] }
        var actions: [UIAccessibilityCustomAction] = []
        let aims = model.skipTargets(for: seat)
        if Card(id: card) == .cucumber, !aims.isEmpty {
            for target in aims {
                let name = SeatInfo.name(model.room.seats[safe: target])
                actions.append(customAction(String(localized: "Discard, skip \(name)", comment: "VoiceOver action: discard the Cucumber at a player")) { [weak self] in
                    self?.tryDiscard(card, target: target) ?? false
                })
            }
        } else {
            actions.append(customAction(String(localized: "Discard", comment: "VoiceOver action: discard this card")) { [weak self] in
                self?.tryDiscard(card, target: nil) ?? false
            })
        }
        if !trays.isHidden {
            for tray in trayState.requirements.indices where !trayState.isFull(tray) {
                actions.append(customAction(String(localized: "Put in tray \(tray + 1)", comment: "VoiceOver action: put the card in a lay-down tray")) { [weak self] in
                    self?.tryTray(card, tray) ?? false
                })
            }
        }
        for target in model.hitTargets(card: card, seat: seat) {
            let name = SeatInfo.name(model.room.seats[safe: target.seat])
            let low = model.hitPlan(card: card, seat: seat, target: target, toward: .start)
            let high = model.hitPlan(card: card, seat: seat, target: target, toward: .end)
            if let low, let high, low.side == .start, high.side == .end {
                // A Yarn that fits either end of a run: one action per end.
                actions.append(customAction(String(localized: "Add to the start of group \(target.group + 1), \(name)", comment: "VoiceOver action: hit the low end of a laid run")) { [weak self] in
                    self?.tryHit(card, target, toward: .start) ?? false
                })
                actions.append(customAction(String(localized: "Add to the end of group \(target.group + 1), \(name)", comment: "VoiceOver action: hit the high end of a laid run")) { [weak self] in
                    self?.tryHit(card, target, toward: .end) ?? false
                })
            } else {
                actions.append(customAction(String(localized: "Add to group \(target.group + 1), \(name)", comment: "VoiceOver action: hit a laid group")) { [weak self] in
                    self?.tryHit(card, target, toward: .end) ?? false
                })
            }
        }
        return actions
    }

    /// "Back to hand", and for a Yarn in a run, move it left or right.
    func trayCardActions(_ card: CardID, tray: Int, index: Int) -> [UIAccessibilityCustomAction] {
        var actions = [customAction(String(localized: "Back to hand", comment: "VoiceOver action: take a card out of its tray")) { [weak self] in
            self?.returnFromTray(card, toSlot: nil)
            return true
        }]
        if Card(id: card) == .yarn, trayState.requirements[safe: tray]?.kind == .run, trayState.isValid(tray) {
            for (name, delta) in [
                (String(localized: "Move left", comment: "VoiceOver action: move the Yarn one place lower in its run"), -1),
                (String(localized: "Move right", comment: "VoiceOver action: move the Yarn one place higher in its run"), 1),
            ] {
                actions.append(customAction(name) { [weak self] in
                    guard let self else { return false }
                    let before = self.trayState
                    self.trayState.moveYarn(card, inTray: tray, toIndex: index + delta)
                    self.refresh()
                    return self.trayState != before
                })
            }
        }
        return actions
    }
}
