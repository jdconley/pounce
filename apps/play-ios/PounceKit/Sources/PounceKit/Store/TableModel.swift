/// What the table shows and which moves glow, derived from a `RoomView`.
/// Client-side only; the server stays the authority on legality.
public struct TableModel: Equatable, Sendable {
    public let room: RoomView

    public init(room: RoomView) {
        self.room = room
    }

    public var game: GameView? { room.game }

    /// Seats this device controls.
    public var mySeats: [Seat] {
        room.seats.indices.filter { room.seats[$0].yours }
    }

    public var isMultiSeat: Bool { mySeats.count > 1 }

    public var currentSeat: Seat? { game?.turn }

    private var isLive: Bool {
        room.status == .playing && game?.status == .playing
    }

    public var isMyTurn: Bool {
        guard isLive, let turn = game?.turn else { return false }
        return mySeats.contains(turn)
    }

    private var seatCount: Int {
        game?.handCounts.count ?? room.seats.count
    }

    /// The seats along the top bar: the others in turn order after `bottom`, or every seat
    /// when this phone holds none (nothing is drawn at the bottom).
    public func barSeats(bottom: Seat?) -> [Seat] {
        guard let bottom else { return Array(0..<seatCount) }
        return opponents(bottom: bottom)
    }

    /// Other seats in turn order, starting after `bottom`.
    public func opponents(bottom: Seat) -> [Seat] {
        let n = seatCount
        guard n > 1, bottom >= 0, bottom < n else { return [] }
        return (1..<n).map { (bottom + $0) % n }
    }

    private func isTurn(_ seat: Seat, step: TurnStep) -> Bool {
        guard isLive, let game else { return false }
        return game.turn == seat && game.step == step
    }

    /// Empty unless it is `seat`'s draw step. The discard can't be drawn when
    /// its top is a Cucumber (or the pile is empty).
    public func drawSources(for seat: Seat) -> Set<DrawSource> {
        guard isTurn(seat, step: .draw), let game else { return [] }
        var sources: Set<DrawSource> = [.deck]
        if let top = game.discardTop, Card.decode(top) != .cucumber {
            sources.insert(.discard)
        }
        return sources
    }

    public func canPlay(_ seat: Seat) -> Bool {
        isTurn(seat, step: .play)
    }

    /// The phase requirements `seat` still has to lay down; empty once laid or
    /// past the last phase.
    public func trays(for seat: Seat) -> [Requirement] {
        guard let game, game.phase.indices.contains(seat), game.laid.indices.contains(seat),
              game.laid[seat] == nil else { return [] }
        let phase = game.phase[seat]
        guard Rules.phases.indices.contains(phase) else { return [] }
        return Rules.phases[phase]
    }

    /// Laid groups (of any seat) that `card` could extend, once `seat` has laid.
    public func hitTargets(card: CardID, seat: Seat) -> [HitTarget] {
        guard canPlay(seat), let game, game.laid.indices.contains(seat), game.laid[seat] != nil else { return [] }
        var targets: [HitTarget] = []
        for (owner, groups) in game.laid.enumerated() {
            for (index, group) in (groups ?? []).enumerated() where Rules.canHit(group, card: card) != nil {
                targets.append(HitTarget(seat: owner, group: index))
            }
        }
        return targets
    }

    /// Where `card` lands when `seat` drops it toward the `toward` end of `target`. A natural
    /// goes where its value fits whichever end it was dropped on; a Yarn on a run takes the
    /// end it was dropped on, or the other end when that one can't take it (a run up to 12).
    /// The action carries `side` only when the server's default would put the card elsewhere,
    /// so it means the same to a server that predates `side`.
    public func hitPlan(card: CardID, seat: Seat, target: HitTarget, toward: HitSide) -> HitPlan? {
        guard hitTargets(card: card, seat: seat).contains(target) else { return nil }
        return plannedHit(card: card, target: target, toward: toward)
    }

    /// `hitPlan` for a `target` already known to be one of `hitTargets(card:seat:)` (`HitAims`
    /// checks that once per drag instead of once per touch move).
    func plannedHit(card: CardID, target: HitTarget, toward: HitSide) -> HitPlan? {
        guard let game, game.laid.indices.contains(target.seat), let groups = game.laid[target.seat],
              groups.indices.contains(target.group) else { return nil }
        let group = groups[target.group]
        let other: HitSide = toward == .start ? .end : .start
        guard case .run = group else {
            guard let extended = Rules.canHit(group, card: card), let index = extended.cards.lastIndex(of: card) else { return nil }
            let stands: Int? = if case .set(_, let value) = group, Card(id: card) == .yarn { value } else { nil }
            return HitPlan(target: target, group: extended, index: index, side: nil, stands: stands,
                           action: .hit(card: card, target: target))
        }
        for side in [toward, other] {
            guard let extended = Rules.canHit(group, card: card, side: side),
                  case .run(let cards, let start, let end) = extended else { continue }
            let byDefault = Rules.canHit(group, card: card) == extended
            return HitPlan(
                target: target, group: extended, index: side == .start ? 0 : cards.count - 1, side: side,
                stands: Card(id: card) == .yarn ? (side == .start ? start : end) : nil,
                action: .hit(card: card, target: target, side: byDefault ? nil : side))
        }
        return nil
    }

    /// Other seats not already pending a skip.
    public func skipTargets(for seat: Seat) -> [Seat] {
        guard let game else { return [] }
        return (0..<seatCount).filter { other in
            other != seat && !(game.pendingSkip.indices.contains(other) && game.pendingSkip[other])
        }
    }

    /// A Cucumber carries `target` only when it is a legal choice; with no
    /// legal target at all the discard goes out plain.
    public func discardAction(card: CardID, target: Seat?) -> Action {
        guard Card.decode(card) == .cucumber, let game else { return .discard(card: card, skipTarget: nil) }
        let legal = skipTargets(for: game.turn)
        if let target, legal.contains(target) {
            return .discard(card: card, skipTarget: target)
        }
        return .discard(card: card, skipTarget: nil)
    }

    /// Mirrors the server's `start`: lobby, I hold a seat, no open seats,
    /// at least two humans or bots (closed seats don't count).
    public var canStart: Bool {
        guard room.status == .lobby, !mySeats.isEmpty, firstOpenSeat == nil else { return false }
        let players = room.seats.filter { $0.kind == .human || $0.kind == .bot }.count
        return players >= 2
    }

    public var firstOpenSeat: Seat? { blockingSeats.first }

    /// Open seats that stop the host from starting; only meaningful in the lobby.
    public var blockingSeats: [Seat] {
        guard room.status == .lobby else { return [] }
        return room.seats.indices.filter { room.seats[$0].kind == .open }
    }
}

/// Where a hit puts its card: the extended group, the card's place in it, the end of a run it
/// goes on (nil for sets and coats), the number a Yarn stands for there (nil for naturals and
/// coats) and the action to send.
public struct HitPlan: Equatable, Sendable {
    public var target: HitTarget
    public var group: Group
    public var index: Int
    public var side: HitSide?
    public var stands: Int?
    public var action: Action
}
