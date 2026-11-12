/// What a set on the rug is, and what it is worth. `points` adds up the number every piece
/// stands for, so a Yarn counts as the piece it replaces.
public enum TileSetReading: Equatable, Sendable {
    case run(suit: TileSuit, start: Int, end: Int, points: Int)
    case group(value: Int, points: Int)

    public var points: Int {
        switch self {
        case .run(_, _, _, let points), .group(_, let points): points
        }
    }

    public var isRun: Bool {
        if case .run = self { return true }
        return false
    }
}

/// Why a play is refused: the server's `TilesError` codes a play can come back with, in the
/// order they are checked.
public enum TilesPlayError: String, Error, Equatable, Sendable, CaseIterable {
    /// The submitted table holds something that is not a piece id.
    case badPiece = "bad_piece"
    /// A piece appears on the submitted table more than once.
    case duplicatePiece = "duplicate_piece"
    /// A piece that was on the table is not on the submitted table.
    case missingPiece = "missing_piece"
    /// A new piece on the submitted table is not on the player's rack.
    case notYourPiece = "not_your_piece"
    /// The submitted table adds nothing from the rack.
    case nothingPlayed = "nothing_played"
    /// A set on the submitted table is not a run or a group.
    case badSet = "bad_set"
    /// Before opening: a set that was on the table was changed.
    case tableTouched = "table_touched"
    /// Before opening: the new sets are worth less than 30.
    case openingTooLow = "opening_too_low"
}

/// What a legal play does: the rack pieces it puts down, and what its new sets are worth.
public struct TilesPlay: Equatable, Sendable {
    public var placed: [TileID]
    public var points: Int
}

/// What one piece of a set stands for: its own number and suit, or for a Yarn the piece it
/// replaces. `suit` is nil for a Yarn in a group that is missing more than one suit.
public struct TileStanding: Equatable, Sendable {
    public var value: Int
    public var suit: TileSuit?

    public init(value: Int, suit: TileSuit?) {
        self.value = value
        self.suit = suit
    }
}

/// Port of `apps/play-api/src/tiles/sets.ts` and `checkPlay` from `engine.ts`: reading sets and
/// checking a whole play, so the app knows before the server does (tile game spec §5.1). The
/// shared vectors (`apps/play-api/fixtures/tiles-sets.json`) keep the two in step.
public enum TilesRules {
    /// The pieces each seat is dealt.
    public static let rackSize = 14
    /// What a first play's new sets must add up to.
    public static let openingPoints = 30
    static let minSet = 3
    static let maxGroup = 4

    /// Reads `tiles` as a set, or returns nil when they are not one.
    ///
    /// A run is three or more pieces of one suit whose numbers climb by one, in the order given:
    /// the piece at index `i` stands for `start + i`, which is how a Yarn says which number it is.
    /// 1 is only ever low and nothing follows 13.
    ///
    /// A group is three or four pieces of one number, every suit different. Order does not
    /// matter, and a Yarn stands for that number in a suit not yet there.
    ///
    /// One number piece with two Yarn can be both (5, Yarn, Yarn is a run 5-6-7 and a group of
    /// 5s). It is read as whichever is worth more, and as a run when they are worth the same.
    public static func readSet(_ tiles: [TileID]) -> TileSetReading? {
        guard tiles.count >= minSet, tiles.count <= Tile.maxValue else { return nil }
        guard tiles.allSatisfy(Tile.isTileID), Set(tiles).count == tiles.count else { return nil }
        let decoded = tiles.map(Tile.init(id:))
        let run = readRun(decoded)
        let group = readGroup(decoded)
        guard let run, let group else { return run ?? group }
        return group.points > run.points ? group : run
    }

    // Both readers lean on `readSet`'s checks: there are only two Yarn, so three or more
    // different pieces always include a number piece.

    private static func readRun(_ decoded: [Tile]) -> TileSetReading? {
        guard let at = decoded.firstIndex(where: { $0 != .yarn }),
              case .number(let anchorValue, let anchorSuit) = decoded[at] else { return nil }
        let start = anchorValue - at
        let end = start + decoded.count - 1
        guard start >= 1, end <= Tile.maxValue else { return nil }
        for (i, tile) in decoded.enumerated() {
            if case .number(let value, let suit) = tile, suit != anchorSuit || value != start + i { return nil }
        }
        return .run(suit: anchorSuit, start: start, end: end, points: (start + end) * decoded.count / 2)
    }

    private static func readGroup(_ decoded: [Tile]) -> TileSetReading? {
        guard decoded.count <= maxGroup else { return nil }
        var value: Int?
        var suits: Set<TileSuit> = []
        for tile in decoded {
            guard case .number(let v, let suit) = tile else { continue }
            if let value, value != v { return nil }
            value = v
            guard suits.insert(suit).inserted else { return nil }
        }
        guard let value else { return nil }
        return .group(value: value, points: value * decoded.count)
    }

    /// What every piece of a valid set stands for, in order; nil when `tiles` is not a set.
    /// In a group one Yarn with exactly one suit missing stands for that suit; otherwise a
    /// Yarn's suit is open.
    public static func standings(_ tiles: [TileID]) -> [TileStanding]? {
        guard let reading = readSet(tiles) else { return nil }
        switch reading {
        case .run(let suit, let start, _, _):
            return tiles.indices.map { TileStanding(value: start + $0, suit: suit) }
        case .group(let value, _):
            let present = Set(tiles.compactMap(Tile.suit))
            let missing = TileSuit.allCases.filter { !present.contains($0) }
            let yarn = tiles.filter(Tile.isYarn).count
            return tiles.map { id in
                if let suit = Tile.suit(id) { return TileStanding(value: value, suit: suit) }
                return TileStanding(value: value, suit: yarn == 1 && missing.count == 1 ? missing[0] : nil)
            }
        }
    }

    /// True when two sets hold the same pieces in the same order.
    public static func sameSet(_ a: [TileID], _ b: [TileID]) -> Bool { a == b }

    /// Checks a submitted table against the table as it stands and the player's rack. Pure, and
    /// the same checks in the same order as the server's `checkPlay`.
    ///
    /// In order: the shape, then where every piece came from (nothing invented, nothing taken
    /// off the table, nothing from anywhere but this rack, something from this rack), then that
    /// every set is a run or a group, then the opening. Until a seat has opened, every set
    /// already on the table must still be there piece for piece, and the sets it adds must be
    /// worth 30 or more.
    public static func checkPlay(
        before: [[TileID]], rack: [TileID], opened: Bool, submitted: [[TileID]]
    ) -> Result<TilesPlay, TilesPlayError> {
        var seen: Set<TileID> = []
        var duplicate = false
        for set in submitted {
            for id in set {
                guard Tile.isTileID(id) else { return .failure(.badPiece) }
                if !seen.insert(id).inserted { duplicate = true }
            }
        }
        if duplicate { return .failure(.duplicatePiece) }

        let onTable = Set(before.joined())
        for id in onTable where !seen.contains(id) { return .failure(.missingPiece) }
        let placed = submitted.joined().filter { !onTable.contains($0) }
        let mine = Set(rack)
        if placed.contains(where: { !mine.contains($0) }) { return .failure(.notYourPiece) }
        if placed.isEmpty { return .failure(.nothingPlayed) }

        // The sets this play adds are the ones that were not on the table as they are.
        let old = Set(before)
        var points = 0
        var kept = 0
        for set in submitted {
            guard let reading = readSet(set) else { return .failure(.badSet) }
            if old.contains(set) { kept += 1 } else { points += reading.points }
        }
        if !opened {
            if kept != before.count { return .failure(.tableTouched) }
            if points < openingPoints { return .failure(.openingTooLow) }
        }
        return .success(TilesPlay(placed: placed, points: points))
    }
}
