#if DEBUG
import Foundation
// DEBUG only: demo and test data never ships in a Release build.

/// Hand-made tile game rooms for the app's DEBUG `-demo tiles…` screens and its tests. Every
/// one is a table the server could have sent: each piece id appears once, every set on the rug
/// is a row or a match, and the rug, the racks and the toy box add up to the 106 pieces.
extension DemoFixtures {
    /// A number piece's id: `copy` 0 or 1 picks one of the two twins.
    public static func tile(_ value: Int, _ suit: TileSuit, _ copy: Int = 0) -> TileID {
        Tile.id(value, suit, copy: copy)
    }

    /// A tile game room: `me` holds `rack`; the other seats hold `others` pieces each, in seat
    /// order after mine; the toy box holds the rest. The last seat is a House Cat at four seats.
    public static func tilesRoom(
        seats: Int, me: Seat = 0, turn: Seat? = nil, turns: Int, table: [[TileID]], rack: [TileID],
        others: [Int], opened: [Bool], passed: [Bool]? = nil
    ) -> RoomView {
        let n = min(max(seats, 2), 4)
        var counts = Array(repeating: 0, count: n)
        var next = others.makeIterator()
        for seat in 0..<n { counts[seat] = seat == me ? rack.count : (next.next() ?? TilesRules.rackSize) }
        let down = table.reduce(0) { $0 + $1.count }
        let view = TilesView(
            turn: turn ?? me, turns: turns, table: table, poolCount: Tile.count - down - counts.reduce(0, +),
            rackCounts: counts, racks: [me: rack], opened: opened, passed: passed)
        let seatViews: [SeatView] = (0..<n).map { i in
            if n == 4, i == n - 1, i != me { return SeatView(kind: .bot) }
            return SeatView(
                kind: .human, person: Person(id: "demo-\(i)", name: names[i], cat: cats[i]),
                yours: i == me, presence: .awake)
        }
        return RoomView(
            code: code, name: demoName, status: .playing, youAreHost: me == 0, seats: seatViews,
            look: .standard, gameId: GameID.tiles, tiles: view)
    }

    /// Early in a four-seat game, my move, before my opening. Leo has opened with a row and a
    /// match. My stash holds fish 10-11-12 (33, enough to open on its own), three 5s, a Yarn and
    /// loose pieces. `opened` is the same table after my opening instead: the fish row is mine
    /// on the rug and the rest of the stash is free to go anywhere.
    public static func tilesEarly(opened: Bool = false) -> RoomView {
        var table: [[TileID]] = [
            [tile(10, .mouse), tile(11, .mouse), tile(12, .mouse)],
            [tile(9, .fish), tile(9, .mouse), tile(9, .bell)],
        ]
        var rack: [TileID] = [
            tile(10, .fish), tile(5, .mouse), tile(2, .mouse), tile(11, .fish), tile(8, .bell), tile(5, .fish),
            tile(13, .feather), Tile.yarnIDs[0], tile(12, .fish), tile(3, .bell), tile(5, .feather),
            tile(1, .fish), tile(7, .mouse), tile(12, .bell),
        ]
        if opened {
            let row = [tile(10, .fish), tile(11, .fish), tile(12, .fish)]
            table.append(row)
            rack.removeAll(where: row.contains)
        }
        return tilesRoom(
            seats: 4, turns: opened ? 9 : 5, table: table, rack: rack, others: [9, 15, 14],
            opened: [opened, true, false, false])
    }

    /// The middle of a four-seat game, my move, already opened: nine sets on the rug and nine
    /// pieces in my stash. Fish 7 goes on the fish row, mouse 13 on the mouse row, feather 11 on
    /// the feather row, and bell 7 can take the Yarn's place in the bell row.
    public static func tilesMid() -> RoomView {
        tilesRoom(
            seats: 4, turns: 31, table: tilesMidTable, rack: tilesMidRack, others: [6, 11, 8],
            opened: [true, true, true, false])
    }

    static let tilesMidTable: [[TileID]] = [
        [tile(3, .fish), tile(4, .fish), tile(5, .fish), tile(6, .fish)],
        [tile(9, .fish), tile(9, .mouse), tile(9, .bell)],
        [tile(10, .mouse), tile(11, .mouse), tile(12, .mouse)],
        [tile(1, .feather), tile(2, .feather), tile(3, .feather), tile(4, .feather), tile(5, .feather)],
        [tile(2, .mouse), tile(2, .feather, 1), tile(2, .bell)],
        [tile(5, .bell), tile(6, .bell), Tile.yarnIDs[0], tile(8, .bell)],
        [tile(12, .fish), tile(12, .feather), tile(12, .bell)],
        [tile(4, .mouse, 1), tile(5, .mouse, 1), tile(6, .mouse, 1)],
        [tile(8, .feather), tile(9, .feather), tile(10, .feather)],
    ]

    static let tilesMidRack: [TileID] = [
        tile(7, .fish), tile(11, .bell), tile(13, .mouse), tile(1, .mouse), tile(7, .bell),
        tile(9, .fish, 1), tile(11, .feather), tile(2, .bell, 1), tile(13, .fish),
    ]

    /// `tilesMid()` on Kiki's move (seat 2), for watching another seat play.
    public static func tilesOther() -> RoomView {
        var room = tilesMid()
        room.tiles?.turn = 2
        return room
    }

    /// Late in a three-seat game: 25 sets (80 pieces) on the rug and 22 pieces in my stash.
    /// Sixteen rows from the first copy of every piece, nine matches from the second (one with
    /// a Yarn as its fourth piece). The stash holds the other Yarn and plenty that fits.
    public static func tilesLate() -> RoomView {
        var table: [[TileID]] = []
        for suit in TileSuit.allCases {
            for values in [[1, 2, 3], [4, 5, 6, 7], [8, 9, 10], [11, 12, 13]] {
                table.append(values.map { tile($0, suit) })
            }
        }
        var left: [TileID] = []
        for value in 1...9 {
            let out = TileSuit.allCases[(value - 1) % 4]
            var match = TileSuit.allCases.filter { $0 != out }.map { tile(value, $0, 1) }
            if value == 4 { match.append(Tile.yarnIDs[0]) }
            table.append(match)
            left.append(tile(value, out, 1))
        }
        // Rows and matches take turns down the rug, as a real table's would.
        let rows = Array(table[..<16]), matches = Array(table[16...])
        table = []
        for i in 0..<16 {
            table.append(rows[i])
            if i < matches.count { table.append(matches[i]) }
        }
        for value in 10...13 { for suit in TileSuit.allCases { left.append(tile(value, suit, 1)) } }
        // 25 second copies are off the rug: 21 are mine with the Yarn, the rest are the others'.
        let rack = Array(left.prefix(4)) + Array(left.suffix(16)) + [Tile.yarnIDs[1]] + [left[4]]
        return tilesRoom(
            seats: 3, turns: 96, table: table, rack: rack, others: [2, 1], opened: [true, true, true])
    }

    /// A row of all thirteen on the rug (the widest thing the rug ever draws) among shorter
    /// sets, my move, opened.
    public static func tilesLong() -> RoomView {
        let table: [[TileID]] = [
            (1...13).map { tile($0, .feather) },
            [tile(9, .fish), tile(9, .mouse), tile(9, .bell)],
            [tile(3, .fish), tile(4, .fish), tile(5, .fish), tile(6, .fish)],
            [tile(13, .fish), tile(13, .mouse), tile(13, .bell), Tile.yarnIDs[1]],
        ]
        return tilesRoom(
            seats: 2, turns: 40, table: table, rack: [tile(7, .fish), tile(2, .bell), tile(13, .feather, 1)],
            others: [5], opened: [true, true])
    }

    /// A two-seat game with the toy box empty and nothing I can add: the turn button is Pass.
    public static func tilesPass() -> RoomView {
        var room = tilesLate()
        room.seats.removeLast()
        guard var view = room.tiles else { return room }
        // The third seat's piece and the toy box go to the other seat's rack.
        let spare = view.rackCounts[2] + view.poolCount
        view.rackCounts = [view.rackCounts[0], view.rackCounts[1] + spare]
        view.poolCount = 0
        view.opened = [true, true]
        view.passed = [false, true]
        view.forfeited = [false, false]
        view.scores = [0, 0]
        room.tiles = view
        return room
    }

    /// Pass and play: seats 0 and 2 are on this phone and it is seat 0's move, so the curtain
    /// is over the stash while the rug stays in view.
    public static func tilesCurtain() -> RoomView {
        var room = tilesMid()
        room.seats[2].yours = true
        let second: [TileID] = [
            tile(1, .bell), tile(3, .mouse), tile(6, .feather), tile(7, .feather), tile(10, .bell),
            tile(10, .fish, 1), tile(11, .fish, 1), tile(13, .bell), tile(8, .fish), tile(8, .mouse), tile(4, .bell),
        ]
        room.tiles?.racks[2] = second
        room.tiles?.rackCounts[2] = second.count
        return room
    }

    /// The end of `tilesMid()`: Leo (seat 1) went out. Everyone is charged what they were left
    /// with and Leo collects it.
    public static func tilesOver() -> RoomView {
        var room = tilesMid()
        room.status = .over
        guard var view = room.tiles else { return room }
        let left = [Tile.rackTotal(tilesMidRack), 0, 41, 27]
        view.status = .gameOver
        view.turn = 1
        view.turns += 3
        view.rackCounts[1] = 0
        view.poolCount += 6
        view.winners = [1]
        view.scores = [-left[0], left[0] + left[2] + left[3], -left[2], -left[3]]
        view.endReason = .out
        room.tiles = view
        return room
    }

    /// The events that end `tilesMid()` as `tilesOver()` shows it.
    public static func tilesOverEvents() -> [TilesEvent] {
        guard let view = tilesOver().tiles else { return [] }
        return [.gameOver(winners: view.winners, reason: .out, scores: view.scores, left: [Tile.rackTotal(tilesMidRack), 0, 41, 27])]
    }
}

/// A whole tile game on the device, for the DEBUG local play mode and the demos' fake server:
/// the engine's turns (`apps/play-api/src/tiles/engine.ts`), every rack and the toy box. The
/// rules it applies are `TilesRules.checkPlay`'s, so what the app's draft calls playable is
/// what this accepts. Its House Cat is greedy and simpler than the server's: it opens once its
/// rack's sets are worth 30, then lays down every set it holds and fits single pieces on the
/// ends of sets.
public struct TilesLocalGame: Equatable, Sendable {
    public private(set) var racks: [[TileID]]
    /// The last element is the next piece drawn.
    public private(set) var pool: [TileID]
    public private(set) var table: [[TileID]]
    public private(set) var opened: [Bool]
    public private(set) var passed: [Bool]
    public private(set) var forfeited: [Bool]
    public private(set) var turn: Seat
    public private(set) var turns = 0
    public private(set) var status = TilesStatus.playing
    public private(set) var winners: [Seat] = []
    public private(set) var scores: [Int]
    public private(set) var endReason: TilesEndReason?

    public var seats: Int { racks.count }

    /// A refused action, with the server's error code for it.
    public struct Refused: Error, Equatable, Sendable {
        public let code: ErrorCode
    }

    /// A new game: the 106 pieces shuffled by `seed`, 14 to each seat, and a first seat.
    public init(seats: Int, seed: UInt64) {
        var rng = SplitMix(state: seed)
        var all = Array(0..<Tile.count)
        all.shuffle(using: &rng)
        let n = min(max(seats, 2), 4)
        racks = (0..<n).map { Array(all[($0 * TilesRules.rackSize)..<(($0 + 1) * TilesRules.rackSize)]) }
        pool = Array(all[(n * TilesRules.rackSize)...])
        table = []
        opened = Array(repeating: false, count: n)
        passed = opened
        forfeited = opened
        scores = Array(repeating: 0, count: n)
        turn = Int(rng.next() % UInt64(n))
    }

    /// A game picked up from what one device sees: the racks it can't see and the toy box are
    /// dealt from the pieces the view doesn't show, shuffled by `seed`.
    public init(view: TilesView, seed: UInt64) {
        var rng = SplitMix(state: seed)
        let shown = Set(view.table.joined()).union(view.racks.values.joined())
        var hidden = (0..<Tile.count).filter { !shown.contains($0) }
        hidden.shuffle(using: &rng)
        racks = view.rackCounts.enumerated().map { seat, count in
            if let rack = view.racks[seat] { return rack }
            let take = min(count, hidden.count)
            defer { hidden.removeFirst(take) }
            return Array(hidden.prefix(take))
        }
        pool = Array(hidden.prefix(view.poolCount))
        table = view.table
        opened = view.opened
        passed = view.passed
        forfeited = view.forfeited
        turn = view.turn
        turns = view.turns
        status = view.status
        winners = view.winners
        scores = view.scores
        endReason = view.endReason
    }

    /// What a device controlling `controlled` may see.
    public func view(for controlled: [Seat]) -> TilesView {
        var mine: [Seat: [TileID]] = [:]
        for seat in controlled where racks.indices.contains(seat) { mine[seat] = racks[seat] }
        return TilesView(
            status: status, turn: turn, turns: turns, table: table, poolCount: pool.count,
            rackCounts: racks.map(\.count), racks: mine, opened: opened, passed: passed,
            forfeited: forfeited, winners: winners, scores: scores, endReason: endReason)
    }

    /// `event` as a device controlling `controlled` gets it: a drawn piece is the drawer's alone.
    public static func event(_ event: TilesEvent, for controlled: [Seat]) -> TilesEvent {
        if case .drew(let seat, _, let poolCount) = event, !controlled.contains(seat) {
            return .drew(seat: seat, tile: nil, poolCount: poolCount)
        }
        return event
    }

    private var active: [Seat] { (0..<seats).filter { !forfeited[$0] } }

    /// Applies one action as the server would. On a refusal nothing changes.
    public mutating func apply(seat: Seat, _ action: TilesAction) -> Result<[TilesEvent], Refused> {
        guard status == .playing else { return .failure(Refused(code: .gameOver)) }
        if case .forfeit = action { return forfeit(seat) }
        guard seat == turn else { return .failure(Refused(code: .notYourTurn)) }
        var events: [TilesEvent] = []
        switch action {
        case .draw:
            guard let drawn = pool.popLast() else { return .failure(Refused(code: .poolEmpty)) }
            racks[seat].append(drawn)
            events.append(.drew(seat: seat, tile: drawn, poolCount: pool.count))
        case .pass:
            guard pool.isEmpty else { return .failure(Refused(code: .poolNotEmpty)) }
            passed[seat] = true
            events.append(.passed(seat: seat))
        case .play(let submitted):
            switch TilesRules.checkPlay(before: table, rack: racks[seat], opened: opened[seat], submitted: submitted) {
            case .failure(let error):
                return .failure(Refused(code: ErrorCode(rawValue: error.rawValue)))
            case .success(let play):
                let placed = Set(play.placed)
                racks[seat].removeAll(where: placed.contains)
                table = submitted
                passed = Array(repeating: false, count: seats)
                events.append(.played(seat: seat, table: submitted, placed: play.placed, opened: !opened[seat]))
                opened[seat] = true
            }
        case .forfeit:
            break
        }
        turns += 1
        endTurn(&events)
        return .success(events)
    }

    private mutating func endTurn(_ events: inout [TilesEvent], stay: Bool = false) {
        let out = active.filter { racks[$0].isEmpty }
        if !out.isEmpty { return finish(out, .out, &events) }
        if active.allSatisfy({ passed[$0] }) {
            let totals = active.map { Tile.rackTotal(racks[$0]) }
            let least = totals.min() ?? 0
            return finish(active.enumerated().filter { totals[$0.offset] == least }.map(\.element), .blocked, &events)
        }
        if stay { return }
        var next = (turn + 1) % seats
        while forfeited[next] { next = (next + 1) % seats }
        turn = next
        events.append(.turn(seat: next))
    }

    private mutating func finish(_ won: [Seat], _ reason: TilesEndReason, _ events: inout [TilesEvent]) {
        let left = racks.map(Tile.rackTotal)
        if reason != .forfeit {
            let pot = active.filter { !won.contains($0) }.reduce(0) { $0 + left[$1] }
            for seat in active { scores[seat] = (won.contains(seat) ? pot : 0) - left[seat] }
        }
        status = .gameOver
        winners = won
        endReason = reason
        events.append(.gameOver(winners: won, reason: reason, scores: scores, left: left))
    }

    private mutating func forfeit(_ seat: Seat) -> Result<[TilesEvent], Refused> {
        guard racks.indices.contains(seat) else { return .failure(Refused(code: .badSeat)) }
        guard !forfeited[seat] else { return .failure(Refused(code: .forfeited)) }
        forfeited[seat] = true
        racks[seat] = []  // set aside for the rest of the game
        passed[seat] = false
        var events: [TilesEvent] = [.forfeited(seat: seat)]
        let left = active
        if left.count == 1 {
            finish(left, .forfeit, &events)
        } else {
            endTurn(&events, stay: turn != seat)
        }
        return .success(events)
    }

    /// The local House Cat's move for `seat`: always legal.
    public func botAction(_ seat: Seat) -> TilesAction {
        guard racks.indices.contains(seat) else { return .pass }
        var draft = TilesDraft(table: table, rack: racks[seat], opened: opened[seat], poolHasPieces: !pool.isEmpty)
        let sets = TilesHints.bestSets(draft.rack)
        if opened[seat] || TilesHints.points(sets) >= TilesRules.openingPoints {
            for set in sets { draft.move(set, to: .newSet()) }
        }
        if opened[seat] || draft.turnButton == .play {
            var placed = true
            while placed {
                placed = false
                search: for tile in draft.rack where !Tile.isYarn(tile) || draft.rack.count == 1 {
                    for set in draft.sets where !draft.isLocked(set.id) && TilesHints.fits([tile], in: set.tiles) {
                        guard case .success = draft.move([tile], to: .set(set.id)) else { continue }
                        placed = true
                        break search
                    }
                }
            }
        }
        if draft.turnButton == .play, let action = draft.action { return action }
        return pool.isEmpty ? .pass : .draw
    }
}

/// A small seeded generator (SplitMix64), so a demo game deals the same way every time.
struct SplitMix: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
#endif
