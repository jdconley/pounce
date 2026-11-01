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
