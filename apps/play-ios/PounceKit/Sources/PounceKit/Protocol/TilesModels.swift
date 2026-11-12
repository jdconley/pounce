import Foundation

/// The tile game's id on the wire (`RoomView.gameId`). It never changes, whatever the game is
/// called on screen.
public enum GameID {
    public static let catTower = "cat-tower"
    public static let tiles = "tiles"
}

public enum TilesStatus: String, Codable, Sendable { case playing, gameOver }

/// How a tile game ended: someone emptied their rack, nobody could move, or everyone else left.
public enum TilesEndReason: String, Codable, Sendable { case out, blocked, forfeit }

/// What this device may see of a tile game (tile game spec §8). `racks` holds only the seats
/// this device controls; on the wire it is a JSON object keyed by seat number as a string. The
/// pool's order, the set-aside pieces and every other rack never leave the server.
public struct TilesView: Codable, Equatable, Sendable {
    public var status: TilesStatus
    public var turn: Seat
    /// Completed turns so far (plays, draws and passes): tells one turn from the next.
    public var turns: Int
    /// The sets on the rug, each in display order.
    public var table: [[TileID]]
    public var poolCount: Int
    public var rackCounts: [Int]
    public var racks: [Seat: [TileID]]
    /// Seats that have made their opening play and may now rearrange the rug.
    public var opened: [Bool]
    /// Seats that passed since the last piece was played (only once the pool is empty).
    public var passed: [Bool]
    /// Seats that forfeited: out of the game, last place.
    public var forfeited: [Bool]
    public var winners: [Seat]
    /// All zero until the game is over.
    public var scores: [Int]
    /// Only on a finished game. A reason this build doesn't know decodes as nil.
    public var endReason: TilesEndReason?

    public var seatCount: Int { rackCounts.count }

    /// True when `seat` forfeited.
    public func isOut(_ seat: Seat) -> Bool { forfeited.indices.contains(seat) && forfeited[seat] }

    public func hasOpened(_ seat: Seat) -> Bool { opened.indices.contains(seat) && opened[seat] }

    public func hasPassed(_ seat: Seat) -> Bool { passed.indices.contains(seat) && passed[seat] }

    public init(
        status: TilesStatus = .playing, turn: Seat, turns: Int, table: [[TileID]], poolCount: Int,
        rackCounts: [Int], racks: [Seat: [TileID]], opened: [Bool], passed: [Bool]? = nil,
        forfeited: [Bool]? = nil, winners: [Seat] = [], scores: [Int]? = nil, endReason: TilesEndReason? = nil
    ) {
        let none = Array(repeating: false, count: rackCounts.count)
        self.status = status
        self.turn = turn
        self.turns = turns
        self.table = table
        self.poolCount = poolCount
        self.rackCounts = rackCounts
        self.racks = racks
        self.opened = opened
        self.passed = passed ?? none
        self.forfeited = forfeited ?? none
        self.winners = winners
        self.scores = scores ?? Array(repeating: 0, count: rackCounts.count)
        self.endReason = endReason
    }

    private enum CodingKeys: String, CodingKey {
        case status, turn, turns, table, poolCount, rackCounts, racks, opened, passed, forfeited
        case winners, scores, endReason
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decode(TilesStatus.self, forKey: .status)
        turn = try c.decode(Seat.self, forKey: .turn)
        turns = try c.decode(Int.self, forKey: .turns)
        table = try c.decode([[TileID]].self, forKey: .table)
        poolCount = try c.decode(Int.self, forKey: .poolCount)
        rackCounts = try c.decode([Int].self, forKey: .rackCounts)
        racks = try c.decode(StringKeyedSeats.self, forKey: .racks).hands
        opened = try c.decode([Bool].self, forKey: .opened)
        passed = try c.decode([Bool].self, forKey: .passed)
        forfeited = try c.decode([Bool].self, forKey: .forfeited)
        winners = try c.decode([Seat].self, forKey: .winners)
        scores = try c.decode([Int].self, forKey: .scores)
        endReason = (try? c.decodeIfPresent(String.self, forKey: .endReason)).flatMap(TilesEndReason.init(rawValue:))
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(status, forKey: .status)
        try c.encode(turn, forKey: .turn)
        try c.encode(turns, forKey: .turns)
        try c.encode(table, forKey: .table)
        try c.encode(poolCount, forKey: .poolCount)
        try c.encode(rackCounts, forKey: .rackCounts)
        try c.encode(StringKeyedSeats(hands: racks), forKey: .racks)
        try c.encode(opened, forKey: .opened)
        try c.encode(passed, forKey: .passed)
        try c.encode(forfeited, forKey: .forfeited)
        try c.encode(winners, forKey: .winners)
        try c.encode(scores, forKey: .scores)
        try c.encodeIfPresent(endReason, forKey: .endReason)
    }
}

/// A tile game event as broadcast by the server (discriminator key `kind`). It shares names
/// with Cat Tower's events (`drew`, `turn`, `forfeited`, `gameOver`) but not their payloads,
/// which is why it travels under its own room event kind (`RoomEvent.tiles`).
public enum TilesEvent: Codable, Equatable, Sendable {
    /// `tile` is present only for the seat that drew.
    case drew(seat: Seat, tile: TileID?, poolCount: Int)
    /// `table` is the whole rug after the play; `placed` are the pieces that came from the
    /// rack; `opened` marks a seat's opening play.
    case played(seat: Seat, table: [[TileID]], placed: [TileID], opened: Bool)
    case passed(seat: Seat)
    case turn(seat: Seat)
    case forfeited(seat: Seat)
    /// `left` is each seat's rack total as the game ended (0 for a seat that forfeited).
    case gameOver(winners: [Seat], reason: TilesEndReason, scores: [Int], left: [Int])

    private enum CodingKeys: String, CodingKey {
        case kind, seat, tile, poolCount, table, placed, opened, winners, reason, scores, left
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        switch kind {
        case "drew":
            self = .drew(seat: try c.decode(Seat.self, forKey: .seat),
                         tile: try c.decodeIfPresent(TileID.self, forKey: .tile),
                         poolCount: try c.decode(Int.self, forKey: .poolCount))
        case "played":
            self = .played(seat: try c.decode(Seat.self, forKey: .seat),
                           table: try c.decode([[TileID]].self, forKey: .table),
                           placed: try c.decode([TileID].self, forKey: .placed),
                           opened: try c.decode(Bool.self, forKey: .opened))
        case "passed":
            self = .passed(seat: try c.decode(Seat.self, forKey: .seat))
        case "turn":
            self = .turn(seat: try c.decode(Seat.self, forKey: .seat))
        case "forfeited":
            self = .forfeited(seat: try c.decode(Seat.self, forKey: .seat))
        case "gameOver":
            self = .gameOver(winners: try c.decode([Seat].self, forKey: .winners),
                             reason: try c.decode(TilesEndReason.self, forKey: .reason),
                             scores: try c.decode([Int].self, forKey: .scores),
                             left: try c.decode([Int].self, forKey: .left))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: c, debugDescription: "unknown tiles event kind: \(kind)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .drew(let seat, let tile, let poolCount):
            try c.encode("drew", forKey: .kind)
            try c.encode(seat, forKey: .seat)
            try c.encodeIfPresent(tile, forKey: .tile)
            try c.encode(poolCount, forKey: .poolCount)
        case .played(let seat, let table, let placed, let opened):
            try c.encode("played", forKey: .kind)
            try c.encode(seat, forKey: .seat)
            try c.encode(table, forKey: .table)
            try c.encode(placed, forKey: .placed)
            try c.encode(opened, forKey: .opened)
        case .passed(let seat):
            try c.encode("passed", forKey: .kind)
            try c.encode(seat, forKey: .seat)
        case .turn(let seat):
            try c.encode("turn", forKey: .kind)
            try c.encode(seat, forKey: .seat)
        case .forfeited(let seat):
            try c.encode("forfeited", forKey: .kind)
            try c.encode(seat, forKey: .seat)
        case .gameOver(let winners, let reason, let scores, let left):
            try c.encode("gameOver", forKey: .kind)
            try c.encode(winners, forKey: .winners)
            try c.encode(reason, forKey: .reason)
            try c.encode(scores, forKey: .scores)
            try c.encode(left, forKey: .left)
        }
    }
}

/// A turn in the tile game (discriminator key `type`): one submission (tile game spec §4.3).
public enum TilesAction: Encodable, Equatable, Sendable {
    /// Take one piece from the toy box. This is the whole turn.
    case draw
    /// Put pieces down: `table` is the whole rug as it should stand after the turn.
    case play(table: [[TileID]])
    /// Do nothing. Only once the toy box is empty.
    case pass
    /// Leave the game for good, on anyone's turn, until it is over.
    case forfeit

    private enum CodingKeys: String, CodingKey { case type, table }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .draw:
            try c.encode("draw", forKey: .type)
        case .play(let table):
            try c.encode("play", forKey: .type)
            try c.encode(table, forKey: .table)
        case .pass:
            try c.encode("pass", forKey: .type)
        case .forfeit:
            try c.encode("forfeit", forKey: .type)
        }
    }
}
