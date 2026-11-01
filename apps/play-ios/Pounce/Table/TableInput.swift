import PounceKit
import SpriteKit
import UIKit

/// Where the current touch started and whether it became a drag.
struct TableInputState {
    enum Source: Equatable {
        case none, menu, sort, layDown, other
        case hand(CardID)
        case tray(CardID, Int)
        case pile(DrawSource)
    }

    var source: Source = .none
    var start: CGPoint = .zero
    var dragging = false
    var dragNode: CardNode?
    /// Card center minus finger, so the card doesn't jump under the finger.
    var grab: CGVector = .zero

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
            node.position = CGPoint(x: p.x + input.grab.dx, y: p.y + input.grab.dy)
        }
    }

    func inputEnded(_ p: CGPoint) {
        let state = input
        input = TableInputState()
        if state.dragging {
            state.dragNode?.removeFromParent()
            dragCard = nil
            drop(state.source, at: p)
        } else if hypot(p.x - state.start.x, p.y - state.start.y) <= TableInputState.dragThreshold * 2 {
            tap(state.source, at: p)
        }
    }

    func inputCancelled() {
        input.dragNode?.removeFromParent()
        let wasDragging = input.dragging
        input = TableInputState()
        dragCard = nil
        if wasDragging { refresh() }
    }

    private func source(at p: CGPoint) -> TableInputState.Source {
        if !menuHidden, menuFrame.contains(p) { return .menu }
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
        case .tray(let card, _):
            guard !store.actionInFlight, let f = trays.frame(of: card) else { return false }
            from = CGPoint(x: f.midX, y: f.midY)
            node = CardNode(card: card, size: layout.cardSize)
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
        node.setScale(1.08)
        node.zPosition = 0
        layer(.drag).addChild(node)
        input.dragNode = node
        Haptics.shared.tick()
        switch input.source {
        case .hand(let card), .tray(let card, _):
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

    // MARK: drops

    private func drop(_ source: TableInputState.Source, at p: CGPoint) {
        // One action in flight at a time: game drops are ignored (no nope, nothing sent);
        // only reordering the hand still works.
        if store.actionInFlight {
            if case .hand(let card) = source, let layout, p.y < layout.traysFrame.minY {
                reorder(card, toX: p.x)
            } else {
                refresh()
            }
            return
        }
        switch source {
        case .hand(let card):
            dropHandCard(card, at: p)
        case .tray(let card, let tray):
            dropTrayCard(card, from: tray, at: p)
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

    private func dropHandCard(_ card: CardID, at p: CGPoint) {
        if discard.hitFrame.insetBy(dx: -12, dy: -12).contains(p) { return chooseDiscard(card) }
        if let seat = opponentSeat(at: p) { return aim(card, at: seat) }
        if !trays.isHidden, let tray = trays.tray(at: p) {
            if !tryTray(card, tray) { nope(card: card) }
            return
        }
        if let target = laidZone.group(at: p) {
            if !tryHit(card, target) { nope(card: card) }
            return
        }
        if let layout, p.y < layout.traysFrame.minY {
            reorder(card, toX: p.x)
            return
        }
        refresh()  // dropped on nothing: back to its place
    }

    private func dropTrayCard(_ card: CardID, from tray: Int, at p: CGPoint) {
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
        returnFromTray(card, toX: (layout.map { p.y < $0.traysFrame.minY } ?? false) ? p.x : nil)
    }

    // MARK: taps

    private func tap(_ source: TableInputState.Source, at p: CGPoint) {
        if store.actionInFlight {
            // Only local taps while an action is in flight.
            switch source {
            case .menu: onMenu()
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
            } else {
                returnFromTray(card, toX: nil)
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

    /// The second tap of tap-tap: a cat, a tray or a laid group for the selected card.
    private func tapTarget(at p: CGPoint) {
        guard let held = liftedCard else { return }
        if let seat = opponentSeat(at: p) { return aim(held, at: seat) }
        if !trays.isHidden, let tray = trays.tray(at: p) {
            if !tryTray(held, tray) { nope(card: held) }
            return
        }
        if let target = laidZone.group(at: p) {
            if !tryHit(held, target) { nope(card: held) }
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

    @discardableResult func tryHit(_ card: CardID, _ target: HitTarget) -> Bool {
        guard let seat = actingSeat, let model, model.hitTargets(card: card, seat: seat).contains(target),
              store.act(seat: seat, .hit(card: card, target: target)) else { return false }
        lastAct = .card(card)
        Haptics.shared.drop()
        let frames = laidZone.groupFrames(seat: target.seat)
        let f = frames[safe: target.group] ?? .zero
        provisionalMove(card: card, to: CGPoint(x: f.maxX, y: f.midY), scale: 0.6)
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

    /// Takes a card out of its tray, optionally dropping it into the hand at `x`.
    func returnFromTray(_ card: CardID, toX x: CGFloat?) {
        trayState.remove(card)
        if let x { reorderInPlace(card, toX: x) }
        refresh()
    }

    private func reorder(_ card: CardID, toX x: CGFloat) {
        reorderInPlace(card, toX: x)
        refresh()
    }

    private func reorderInPlace(_ card: CardID, toX x: CGFloat) {
        guard let seat = bottomSeat else { return }
        handOrders[seat]?.move(card, before: hand.card(before: x))
    }

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
            actions.append(customAction(String(localized: "Add to group \(target.group + 1), \(name)", comment: "VoiceOver action: hit a laid group")) { [weak self] in
                self?.tryHit(card, target) ?? false
            })
        }
        return actions
    }

    /// "Back to hand", and for a Yarn in a run, move it left or right.
    func trayCardActions(_ card: CardID, tray: Int, index: Int) -> [UIAccessibilityCustomAction] {
        var actions = [customAction(String(localized: "Back to hand", comment: "VoiceOver action: take a card out of its tray")) { [weak self] in
            self?.returnFromTray(card, toX: nil)
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
