/// A piece id in 0-105 in the tile game. Ids are the only piece representation on the wire.
public typealias TileID = Int

/// The four kinds of toy (tile game spec §3.2), in the server's order.
public enum TileSuit: String, Codable, CaseIterable, Sendable {
    case fish, mouse, feather, bell

    /// 0-3, the server's order.
    public var index: Int { TileSuit.allCases.firstIndex(of: self) ?? 0 }
}

/// Port of `apps/play-api/src/tiles/pieces.ts`.
///
/// Ids 0-103 are numbers: suit = id / 26, value = id % 13 + 1, so each number appears twice per
/// suit (ids `n` and `n + 13` within a suit are twins). 104 and 105 are Yarn (wild).
public enum Tile: Equatable, Hashable, Sendable {
    case number(value: Int, suit: TileSuit)
    case yarn

    /// The pieces in a game.
    public static let count = 106
    /// The highest number on a piece. Runs stop here: nothing follows 13.
    public static let maxValue = 13
    /// What a Yarn left on a rack costs at the end of the game.
    public static let yarnPenalty = 30
    static let perSuit = 2 * maxValue
    static let numberTiles = TileSuit.allCases.count * perSuit

    /// Decodes a valid id (0..<106). Traps on an out-of-range id; use ``decode(_:)`` for untrusted ids.
    public init(id: TileID) {
        guard let tile = Tile.decode(id) else { preconditionFailure("invalid piece id: \(id)") }
        self = tile
    }

    /// Non-trapping decode: nil for ids outside 0..<106.
    public static func decode(_ id: TileID) -> Tile? {
        guard isTileID(id) else { return nil }
        if id >= numberTiles { return .yarn }
        return .number(value: id % maxValue + 1, suit: TileSuit.allCases[id / perSuit])
    }

    /// True for an id that names one of the 106 pieces.
    public static func isTileID(_ id: TileID) -> Bool { id >= 0 && id < count }

    public static func isYarn(_ id: TileID) -> Bool { id >= numberTiles && id < count }

    /// The id of a number piece: `copy` 0 or 1 picks one of the two twins.
    public static func id(_ value: Int, _ suit: TileSuit, copy: Int = 0) -> TileID {
        suit.index * perSuit + (copy == 0 ? 0 : maxValue) + value - 1
    }

    /// The two Yarn.
    public static let yarnIDs: [TileID] = [numberTiles, numberTiles + 1]

    /// The number on a piece; nil for a Yarn (and for an id that names nothing).
    public static func value(_ id: TileID) -> Int? {
        if case .number(let value, _)? = decode(id) { return value }
        return nil
    }

    /// The piece's suit; nil for a Yarn (and for an id that names nothing).
    public static func suit(_ id: TileID) -> TileSuit? {
        if case .number(_, let suit)? = decode(id) { return suit }
        return nil
    }

    /// What a piece costs when it is left on a rack: its number, or 30 for a Yarn.
    public static func rackPoints(_ id: TileID) -> Int {
        switch Tile(id: id) {
        case .yarn: yarnPenalty
        case .number(let value, _): value
        }
    }

    /// A rack's total at the end of the game.
    public static func rackTotal(_ rack: [TileID]) -> Int {
        rack.reduce(0) { $0 + rackPoints($1) }
    }
}
