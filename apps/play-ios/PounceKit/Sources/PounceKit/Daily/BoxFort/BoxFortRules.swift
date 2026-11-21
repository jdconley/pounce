import Foundation

/// Box Fort's rules on the client (Daily Dish spec §1 "Box Fort", §12). The server's TS rules
/// (`apps/play-api/src/daily/box-fort/rules.ts`) are the truth; these match them on every golden
/// vector in `apps/play-api/fixtures/daily/box-fort/`, so the score a player sees at once is the
/// one the server works out. There's no puzzle maker here: the server deals each set.
///
/// The rug is 8 by 8, row-major: 0 is an empty spot, 1 to 6 a box in a piece's tint, `clutter` a
/// box that was there at the start.

/// One box of a piece, from the top-left of its bounding box. JSON: `[row, col]`.
public struct BoxFortCell: Hashable, Sendable, Codable {
    public let row: Int
    public let col: Int

    public init(row: Int, col: Int) {
        self.row = row
        self.col = col
    }

    public init(from decoder: any Decoder) throws {
        var pair = try decoder.unkeyedContainer()
        row = try pair.decode(Int.self)
        col = try pair.decode(Int.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var pair = encoder.unkeyedContainer()
        try pair.encode(row)
        try pair.encode(col)
    }
}

/// A piece as the server deals it: its shape's id, its tint (1 to 6) and its boxes. Pieces never
/// rotate.
public struct BoxFortPiece: Hashable, Sendable, Codable {
    public let id: String
    public let tint: Int
    public let cells: [BoxFortCell]

    public init(id: String, tint: Int, cells: [BoxFortCell]) {
        self.id = id
        self.tint = tint
        self.cells = cells
    }

    /// Rows and columns the piece spans.
    public var size: BoxFortCell {
        BoxFortCell(row: (cells.map(\.row).max() ?? 0) + 1, col: (cells.map(\.col).max() ?? 0) + 1)
    }
}

/// What `start` returns as the puzzle: the rug, how many sets the day has, and the first set.
public struct BoxFortPublicPuzzle: Hashable, Sendable, Codable {
    public let rug: [Int]
    public let sets: Int
    public let pieces: [BoxFortPiece]

    public init(rug: [Int], sets: Int, pieces: [BoxFortPiece]) {
        self.rug = rug
        self.sets = sets
        self.pieces = pieces
    }
}

/// A set the server dealt after the one before it was placed.
public struct BoxFortReveal: Hashable, Sendable, Codable {
    public let set: Int
    public let pieces: [BoxFortPiece]

    public init(set: Int, pieces: [BoxFortPiece]) {
        self.set = set
        self.pieces = pieces
    }
}

/// The lines one placement cleared.
public struct BoxFortCleared: Hashable, Sendable, Codable {
    public let rows: [Int]
    public let cols: [Int]

    public static let none = BoxFortCleared(rows: [], cols: [])

    public init(rows: [Int], cols: [Int]) {
        self.rows = rows
        self.cols = cols
    }

    public var count: Int { rows.count + cols.count }
}

/// A run so far, as the server's `publicState` sends it.
public struct BoxFortState: Hashable, Sendable, Codable {
    public enum Over: String, Hashable, Sendable, Codable {
        /// The last set is placed.
        case full
        /// Nothing left in the current set fits.
        case stuck
    }

    public var rug: [Int]
    /// The current set, from 0.
    public var set: Int
    /// How many sets the day has.
    public var sets: Int
    /// The current set's three pieces.
    public var pieces: [BoxFortPiece]
    /// Which of them are on the rug.
    public var placed: [Bool]
    public var points: Int
    /// Clearing placements in a row, ending with the last one.
    public var combo: Int
    /// Lines cleared in the whole run.
    public var lines: Int
    public var over: Over?

    /// The slots still in the tray.
    public var left: [Int] { placed.indices.filter { !placed[$0] } }
}

/// One placement: the state after it, the points it earned (before any full fort) and the lines
/// it cleared. When `setDone`, the caller deals the next set with `BoxFortRules.deal`.
public struct BoxFortStep: Hashable, Sendable {
    public let state: BoxFortState
    public let gained: Int
    public let cleared: BoxFortCleared
    public let setDone: Bool
}

public enum BoxFortRules {
    public static let size = 8
    public static let clutter = 7
    public static let squarePoints = 1
    public static let fullFort = 200

    /// Lines cleared by one placement: 10, 30, 60, 100, …
    public static func lineBonus(_ lines: Int) -> Int { 10 * lines * (lines + 1) / 2 }

    /// The `combo`th clearing placement in a row: nothing for the first, then 15 more each time.
    public static func comboBonus(_ combo: Int) -> Int { combo > 1 ? 15 * (combo - 1) : 0 }

    public static func fits(_ rug: [Int], _ cells: [BoxFortCell], row: Int, col: Int) -> Bool {
        cells.allSatisfy { cell in
            let y = row + cell.row
            let x = col + cell.col
            return y >= 0 && y < size && x >= 0 && x < size && rug[y * size + x] == 0
        }
    }

    /// Whether any of `pieces` fits anywhere on `rug`. A few thousand checks at most; the app
    /// calls `anyFitsOffMain` or `step` off the main actor all the same.
    public static func anyFits(_ rug: [Int], _ pieces: [BoxFortPiece]) -> Bool {
        for piece in pieces {
            for row in 0..<size {
                for col in 0..<size where fits(rug, piece.cells, row: row, col: col) { return true }
            }
        }
        return false
    }

    /// `anyFits`, off the caller's actor.
    @concurrent
    public static func anyFitsOffMain(rug: [Int], pieces: [BoxFortPiece]) async -> Bool {
        anyFits(rug, pieces)
    }

    /// Puts `piece` down with its top-left at (`row`, `col`), then clears every full line at once.
    public static func place(_ rug: [Int], _ piece: BoxFortPiece, row: Int, col: Int) -> (rug: [Int], cleared: BoxFortCleared)? {
        guard fits(rug, piece.cells, row: row, col: col) else { return nil }
        var next = rug
        for cell in piece.cells { next[(row + cell.row) * size + col + cell.col] = piece.tint }
        let rows = (0..<size).filter { y in (0..<size).allSatisfy { next[y * size + $0] != 0 } }
        let cols = (0..<size).filter { x in (0..<size).allSatisfy { next[$0 * size + x] != 0 } }
        for y in rows { for x in 0..<size { next[y * size + x] = 0 } }
        for x in cols { for y in 0..<size { next[y * size + x] = 0 } }
        return (next, BoxFortCleared(rows: rows, cols: cols))
    }

    public static func start(_ puzzle: BoxFortPublicPuzzle) -> BoxFortState {
        BoxFortState(
            rug: puzzle.rug, set: 0, sets: puzzle.sets, pieces: puzzle.pieces, placed: [false, false, false],
            points: 0, combo: 0, lines: 0, over: nil)
    }

    /// Places the current set's piece in `slot`. Nil when the run is over, the slot is placed or
    /// not in the set, or the piece doesn't fit there. When it wasn't the set's last piece, the
    /// run is stuck if none of the pieces left fit.
    public static func step(_ s: BoxFortState, slot: Int, row: Int, col: Int) -> BoxFortStep? {
        guard s.over == nil, s.placed.indices.contains(slot), !s.placed[slot], slot < s.pieces.count else { return nil }
        let piece = s.pieces[slot]
        guard let out = place(s.rug, piece, row: row, col: col) else { return nil }
        let lines = out.cleared.count
        let combo = lines > 0 ? s.combo + 1 : 0
        let gained = piece.cells.count * squarePoints + lineBonus(lines) + comboBonus(combo)
        var next = s
        next.rug = out.rug
        next.placed[slot] = true
        next.points += gained
        next.combo = combo
        next.lines += lines
        let setDone = next.placed.allSatisfy { $0 }
        if !setDone && !anyFits(out.rug, next.left.map { s.pieces[$0] }) { next.over = .stuck }
        return BoxFortStep(state: next, gained: gained, cleared: out.cleared, setDone: setDone)
    }

    /// `step`, off the caller's actor.
    @concurrent
    public static func stepOffMain(_ s: BoxFortState, slot: Int, row: Int, col: Int) async -> BoxFortStep? {
        step(s, slot: slot, row: row, col: col)
    }

    /// After a set is placed: the next set (stuck if none of it fits), or the full fort when
    /// `next` is nil because that was the day's last set.
    public static func deal(_ s: BoxFortState, next: [BoxFortPiece]?) -> BoxFortState {
        var out = s
        guard let next else {
            out.points += fullFort
            out.over = .full
            return out
        }
        out.set += 1
        out.pieces = next
        out.placed = [false, false, false]
        out.over = anyFits(s.rug, next) ? nil : .stuck
        return out
    }

    /// `deal`, off the caller's actor (it looks for room for the new set).
    @concurrent
    public static func dealOffMain(_ s: BoxFortState, next: [BoxFortPiece]?) async -> BoxFortState {
        deal(s, next: next)
    }

    /// For each slot of the current set, whether its piece fits anywhere now. Placed slots count
    /// as fitting, so only the tray's stuck pieces dim.
    public static func fitsBySlot(_ s: BoxFortState) -> [Bool] {
        s.placed.indices.map { s.placed[$0] || $0 >= s.pieces.count || anyFits(s.rug, [s.pieces[$0]]) }
    }

    /// `fitsBySlot`, off the caller's actor.
    @concurrent
    public static func fitsBySlotOffMain(_ s: BoxFortState) async -> [Bool] {
        fitsBySlot(s)
    }
}
