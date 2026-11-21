import Foundation

/// Cat Nap's rules on the client: the quilt, the marks a player makes, and the rules a board can
/// visibly break. A copy of the server's `apps/play-api/src/daily/cat-nap/rules.ts`, held to it by
/// the golden vectors (`fixtures/daily/cat-nap/vectors.json`, `CatNapRulesTests`). No puzzle maker
/// and no solver here: the server makes the quilt and knows the solution.
///
/// The puzzle: an N by N quilt of N patches. One sleeping cat in every row, every column and every
/// patch, and no two cats touch, not even at a corner.

/// The quilt: its size and each cell's patch (0..<n), row by row. What the server's start answer
/// carries as `puzzle`.
public struct NapQuilt: Codable, Sendable, Equatable {
    public let n: Int
    public let patches: [Int]

    public init(n: Int, patches: [Int]) {
        self.n = n
        self.patches = patches
    }

    public var size: Int { n * n }
    public func row(_ cell: Int) -> Int { cell / n }
    public func col(_ cell: Int) -> Int { cell % n }
}

/// A board: each cell's mark (0 empty, 1 "no cat here", 2 a cat), and the cats a hint placed,
/// which are locked. The server's `publicState`.
public struct NapState: Codable, Sendable, Equatable {
    public static let empty: UInt8 = 0, noCat: UInt8 = 1, cat: UInt8 = 2

    public var cells: [UInt8]
    public var hinted: [Int]

    public init(cells: [UInt8], hinted: [Int]) {
        self.cells = cells
        self.hinted = hinted
    }

    public static func empty(_ quilt: NapQuilt) -> NapState {
        NapState(cells: Array(repeating: empty, count: quilt.size), hinted: [])
    }

    public var cats: [Int] { cells.indices.filter { cells[$0] == Self.cat } }
}

/// What a move does to its cells.
public enum NapTo: String, Codable, Sendable {
    case x, cat, clear

    var mark: UInt8 {
        switch self {
        case .x: NapState.noCat
        case .cat: NapState.cat
        case .clear: NapState.empty
        }
    }
}

/// Mark cells "no cat", put a cat on one, or clear them: `{ "k": "mark", "cells": [...], "to": ... }`.
public struct NapMove: Codable, Sendable, Equatable {
    public static let maxCells = 81

    public let cells: [Int]
    public let to: NapTo

    public init(cells: [Int], to: NapTo) {
        self.cells = cells
        self.to = to
    }

    private enum Keys: String, CodingKey { case k, cells, to }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        guard try c.decode(String.self, forKey: .k) == "mark" else {
            throw DecodingError.dataCorruptedError(forKey: .k, in: c, debugDescription: "not a mark")
        }
        cells = try c.decode([Int].self, forKey: .cells)
        to = try c.decode(NapTo.self, forKey: .to)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode("mark", forKey: .k)
        try c.encode(cells, forKey: .cells)
        try c.encode(to, forKey: .to)
    }

    /// The move as JSON (`JSONSerialization` types).
    public var json: [String: Any] { ["k": "mark", "cells": cells, "to": to.rawValue] }

    /// The server's `parseNapMove`: exactly `k`, `cells` and `to`; 1 to 81 distinct non-negative
    /// whole numbers; a cat on exactly one cell. Anything else is nil.
    public init?(json: Any) {
        guard let o = json as? [String: Any], o.count == 3, o["k"] as? String == "mark",
              let toRaw = o["to"] as? String, let to = NapTo(rawValue: toRaw),
              let list = o["cells"] as? [Any], (1...Self.maxCells).contains(list.count)
        else { return nil }
        var cells: [Int] = []
        for item in list {
            guard let number = item as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            let value = number.doubleValue
            guard value >= 0, value == value.rounded(), value < Double(Int.max) else { return nil }
            cells.append(Int(value))
        }
        guard Set(cells).count == cells.count, to != .cat || cells.count == 1 else { return nil }
        self.init(cells: cells, to: to)
    }
}

/// The visible rules a board breaks: rows, columns and patches holding two or more cats, the cats
/// touching another, and every cat in any of those (all ascending).
public struct NapClashes: Sendable, Equatable {
    public var rows: [Int], cols: [Int], patches: [Int], touching: [Int], cells: [Int]

    public init(rows: [Int], cols: [Int], patches: [Int], touching: [Int], cells: [Int]) {
        self.rows = rows
        self.cols = cols
        self.patches = patches
        self.touching = touching
        self.cells = cells
    }

    public static let none = NapClashes(rows: [], cols: [], patches: [], touching: [], cells: [])
}

/// What the board shows from the rules: the clashes, whether every cat is in, and the progress.
public struct NapCheck: Sendable, Equatable {
    public var clashes: NapClashes
    public var complete: Bool
    public var placed: Int

    public init(clashes: NapClashes, complete: Bool, placed: Int) {
        self.clashes = clashes
        self.complete = complete
        self.placed = placed
    }

    public static let none = NapCheck(clashes: .none, complete: false, placed: 0)
}

public enum CatNapRules {
    /// The board after a move, or nil when it is illegal: a cell off the quilt, or a hinted cat.
    public static func apply(_ quilt: NapQuilt, _ state: NapState, _ move: NapMove) -> NapState? {
        guard move.cells.allSatisfy({ $0 < quilt.size && !state.hinted.contains($0) }) else { return nil }
        var next = state
        for cell in move.cells { next.cells[cell] = move.to.mark }
        return next
    }

    static func touches(_ quilt: NapQuilt, _ a: Int, _ b: Int) -> Bool {
        a != b && abs(quilt.row(a) - quilt.row(b)) <= 1 && abs(quilt.col(a) - quilt.col(b)) <= 1
    }

    /// Whether cats at `a` and `b` break a rule together: same row, column or patch, or touching.
    public static func conflict(_ quilt: NapQuilt, _ a: Int, _ b: Int) -> Bool {
        guard a != b else { return false }
        return quilt.row(a) == quilt.row(b) || quilt.col(a) == quilt.col(b)
            || quilt.patches[a] == quilt.patches[b] || touches(quilt, a, b)
    }

    public static func clashes(_ quilt: NapQuilt, _ state: NapState) -> NapClashes {
        let cats = state.cats
        func crowded(_ key: (Int) -> Int) -> [Int] {
            var count: [Int: Int] = [:]
            for c in cats { count[key(c), default: 0] += 1 }
            return count.filter { $0.value > 1 }.map(\.key).sorted()
        }
        let rows = crowded(quilt.row), cols = crowded(quilt.col), patches = crowded { quilt.patches[$0] }
        let touching = cats.filter { a in cats.contains { touches(quilt, a, $0) } }
        let cells = cats.filter {
            rows.contains(quilt.row($0)) || cols.contains(quilt.col($0)) || patches.contains(quilt.patches[$0])
                || touching.contains($0)
        }
        return NapClashes(rows: rows, cols: cols, patches: patches, touching: touching, cells: cells)
    }

    /// Every visible rule check on a board, off the caller's actor: marking over a 9 by 9 quilt
    /// checks here, so the main thread only draws (docs/main-thread.md).
    @concurrent
    public static func check(_ quilt: NapQuilt, _ state: NapState) async -> NapCheck {
        let c = clashes(quilt, state)
        let cats = state.cats
        return NapCheck(
            clashes: c, complete: cats.count == quilt.n && c.cells.isEmpty,
            placed: min(quilt.n, cats.filter { !c.cells.contains($0) }.count))
    }

    /// N cats and no broken rule. With one solution, that is the solution.
    public static func complete(_ quilt: NapQuilt, _ state: NapState) -> Bool {
        state.cats.count == quilt.n && clashes(quilt, state).cells.isEmpty
    }

    /// Cats not in any clash, at most n: progress that gives nothing away.
    public static func placed(_ quilt: NapQuilt, _ state: NapState) -> Int {
        let bad = clashes(quilt, state).cells
        return min(quilt.n, state.cats.filter { !bad.contains($0) }.count)
    }

    /// A hint's cat (the server names the cell): locked at `cell`, and every unlocked cat that
    /// clashes with it cleared.
    public static func applyHint(_ quilt: NapQuilt, _ state: NapState, cell: Int) -> NapState {
        var next = state
        for i in next.cells.indices
        where next.cells[i] == NapState.cat && conflict(quilt, cell, i) && !state.hinted.contains(i) {
            next.cells[i] = NapState.empty
        }
        next.cells[cell] = NapState.cat
        if !next.hinted.contains(cell) { next.hinted = (next.hinted + [cell]).sorted() }
        return next
    }

    /// A tap's move: empty → no cat → cat → empty. Nil on a hinted cat.
    public static func tapMove(_ state: NapState, cell: Int) -> NapMove? {
        guard !state.hinted.contains(cell) else { return nil }
        let to: NapTo = switch state.cells[cell] {
        case NapState.empty: .x
        case NapState.noCat: .cat
        default: .clear
        }
        return NapMove(cells: [cell], to: to)
    }

    /// What a drag from `start` paints: "no cat" from an empty cell, clearing from a "no cat" cell.
    public static func dragPaint(_ state: NapState, start: Int) -> NapTo? {
        guard !state.hinted.contains(start) else { return nil }
        return switch state.cells[start] {
        case NapState.empty: .x
        case NapState.noCat: .clear
        default: nil
        }
    }

    /// A drag's move: the cells it passed that its paint changes, in the order passed, each once.
    /// Painting "no cat" takes empty cells; clearing takes "no cat" cells. Cats are never touched.
    public static func dragMove(_ state: NapState, paint: NapTo, passed: [Int]) -> NapMove? {
        let want = paint == .x ? NapState.empty : NapState.noCat
        var seen = Set<Int>()
        let cells = passed.filter { seen.insert($0).inserted && state.cells[$0] == want && !state.hinted.contains($0) }
        return cells.isEmpty ? nil : NapMove(cells: cells, to: paint)
    }
}

/// What a hint reveals: the cell of its cat (the server's `module.ts`). Moves reveal nothing.
public struct NapReveal: Codable, Sendable, Equatable {
    public let cell: Int

    public init(cell: Int) { self.cell = cell }
}
