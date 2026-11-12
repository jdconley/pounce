/// What the tile game's table shows, derived from a `RoomView` playing it. Client-side only;
/// the server stays the authority. The turn being composed is a `TilesDraft`, which this model
/// makes (and keeps across snapshots that didn't change the turn).
public struct TilesTableModel: Equatable, Sendable {
    public let room: RoomView
    public let view: TilesView

    /// Nil for a room that isn't playing the tile game (its lobby, or another game).
    public init?(room: RoomView) {
        guard let view = room.tiles else { return nil }
        self.room = room
        self.view = view
    }

    public var seatCount: Int { view.seatCount }

    /// Seats this device controls.
    public var mySeats: [Seat] { room.seats.indices.filter { room.seats[$0].yours } }

    public var isMultiSeat: Bool { mySeats.count > 1 }

    /// This device's seats still in the game.
    public var myActiveSeats: [Seat] { mySeats.filter { !view.isOut($0) } }

    public var isLive: Bool { room.status == .playing && view.status == .playing }

    public var currentSeat: Seat? { isLive ? view.turn : nil }

    public var isMyTurn: Bool { currentSeat.map(mySeats.contains) ?? false }

    /// The seat drawn at the bottom: the revealed one, else this phone's only seat, else (on a
    /// shared phone with nothing revealed) none, so no rack is drawn at all.
    public func bottomSeat(revealed: Seat?) -> Seat? {
        if let revealed, mySeats.contains(revealed) { return revealed }
        return mySeats.count == 1 ? mySeats.first : nil
    }

    /// The seats along the top bar: the others in turn order after `bottom`, or every seat when
    /// nothing is drawn at the bottom.
    public func barSeats(bottom: Seat?) -> [Seat] {
        guard let bottom, bottom >= 0, bottom < seatCount else { return Array(0..<seatCount) }
        return (1..<max(seatCount, 1)).map { (bottom + $0) % seatCount }
    }

    /// The rack of a seat this device controls; nil for any other.
    public func rack(_ seat: Seat) -> [TileID]? { view.racks[seat] }

    public func rackCount(_ seat: Seat) -> Int {
        view.rackCounts.indices.contains(seat) ? view.rackCounts[seat] : 0
    }

    /// What a seat's ring in the top bar wears (tile game spec §5.2).
    public struct SeatMarks: Equatable, Sendable {
        public var bot: Bool
        /// Still to make its opening play: a closed toy box.
        public var notOpened: Bool
        /// Passed since the last piece was played.
        public var passed: Bool
        public var forfeited: Bool
        public var onTheMove: Bool
        public var count: Int
    }

    public func marks(_ seat: Seat) -> SeatMarks {
        SeatMarks(
            bot: room.seats.indices.contains(seat) && room.seats[seat].kind == .bot,
            notOpened: !view.hasOpened(seat) && !view.isOut(seat),
            passed: view.hasPassed(seat),
            forfeited: view.isOut(seat),
            onTheMove: currentSeat == seat,
            count: rackCount(seat))
    }

    /// True when `seat` may compose a turn on this device now: its move, its rack here.
    public func canCompose(_ seat: Seat) -> Bool {
        currentSeat == seat && mySeats.contains(seat) && view.racks[seat] != nil
    }

    /// The draft for `seat`'s turn: `keeping` when it was made for this very rug, rack and
    /// opening (a snapshot that changed nothing about the turn), else `saved` under the same
    /// test (the app came back mid-build), else a fresh one. Nil when `seat` can't compose.
    public func draft(for seat: Seat, keeping: TilesDraft? = nil, saved: TilesDraft? = nil) -> TilesDraft? {
        guard canCompose(seat), let rack = view.racks[seat] else { return nil }
        let opened = view.hasOpened(seat)
        for candidate in [keeping, saved] {
            if let candidate, candidate.matches(table: view.table, rack: rack, opened: opened) { return candidate }
        }
        return TilesDraft(table: view.table, rack: rack, opened: opened, poolHasPieces: view.poolCount > 0)
    }

    /// The seat a forfeit from this phone's menu applies to: the rack that is up (`shown`), else
    /// the seat whose turn it is, else this phone's first seat still in.
    public func forfeitSeat(shown: Seat?) -> Seat? {
        guard isLive else { return nil }
        let active = myActiveSeats
        if let shown, active.contains(shown) { return shown }
        if active.contains(view.turn) { return view.turn }
        return active.first
    }

    /// What a forfeit by `seat` does: with one other seat in, the game ends and that seat wins;
    /// with more, `seat` is out and the rest play on.
    public func forfeitOutcome(_ seat: Seat) -> ForfeitOutcome {
        let others = (0..<seatCount).filter { $0 != seat && !view.isOut($0) }
        if others.count == 1, let winner = others.first { return .ends(winner: winner) }
        return .out
    }

    /// Every seat this device holds forfeited while the others play on.
    public var isOutForMe: Bool { room.status == .playing && !mySeats.isEmpty && myActiveSeats.isEmpty }

    /// The finished game's places, best first: winners, then by score (higher is better), with
    /// seats that forfeited last. Empty until the game is over.
    public var standings: [Seat] {
        guard view.status == .gameOver else { return [] }
        return (0..<seatCount).sorted { a, b in
            let ka = [view.isOut(a) ? 1 : 0, view.winners.contains(a) ? 0 : 1, -(view.scores.indices.contains(a) ? view.scores[a] : 0), a]
            let kb = [view.isOut(b) ? 1 : 0, view.winners.contains(b) ? 0 : 1, -(view.scores.indices.contains(b) ? view.scores[b] : 0), b]
            return ka.lexicographicallyPrecedes(kb)
        }
    }
}

/// What changed on the rug since this phone last looked (tile game spec §5.7): the pieces
/// placed since the seat's last turn and who placed each, from the `played` events, to play
/// back in turn order. With no events to hand (a cold start) `since(_:now:)` compares against
/// the last rug seen and marks the new pieces with nobody's colour.
public struct TilesRecap: Equatable, Sendable, Codable {
    public struct Step: Equatable, Sendable, Codable {
        /// The seat that placed them; nil when only a comparison says they are new.
        public var seat: Seat?
        public var placed: [TileID]
    }

    /// One step per play, oldest first.
    public private(set) var steps: [Step] = []

    public init() {}

    public var isEmpty: Bool { steps.isEmpty }

    /// Every piece in the recap with the seat that placed it.
    public var owners: [TileID: Seat?] {
        var owners: [TileID: Seat?] = [:]
        for step in steps { for tile in step.placed { owners[tile] = step.seat } }
        return owners
    }

    /// Notes a play by another seat. A play by one of `mine` starts the recap over: everything
    /// before it has been seen.
    public mutating func note(_ event: TilesEvent, mine: [Seat]) {
        guard case .played(let seat, _, let placed, _) = event else { return }
        if mine.contains(seat) {
            steps = []
        } else {
            steps.append(Step(seat: seat, placed: placed))
        }
    }

    /// The seat has looked: nothing is new any more.
    public mutating func clear() { steps = [] }

    /// A recap from two rugs alone: the pieces on `now` that weren't on `before`.
    public static func since(_ before: [[TileID]], now: [[TileID]]) -> TilesRecap {
        let old = Set(before.joined())
        let new = now.joined().filter { !old.contains($0) }
        var recap = TilesRecap()
        if !new.isEmpty { recap.steps = [Step(seat: nil, placed: new)] }
        return recap
    }
}
