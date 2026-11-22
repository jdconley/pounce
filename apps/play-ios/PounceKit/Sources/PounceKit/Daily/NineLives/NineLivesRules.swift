import Foundation

/// Nine Lives' visible rules, matching the server's `apps/play-api/src/daily/nine-lives/grid.ts`
/// vector for vector (`fixtures/daily/nine-lives/rules.json`). Rules only: the puzzle maker, the
/// solver and the solution stay on the server. Cells are 0...80 in reading order, 0 is empty.

/// A move, in the server's exact wire shape: `{ "k": "set", "i": 4, "d": 7 }`, `{ "k": "clear", "i": 4 }`.
public enum NineLivesMove: Sendable, Equatable, Hashable, Codable {
    case set(cell: Int, digit: Int)
    case clear(cell: Int)

    public var cell: Int {
        switch self {
        case .set(let cell, _), .clear(let cell): cell
        }
    }

    private enum Key: String, CodingKey { case k, i, d }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        let cell = try c.decode(Int.self, forKey: .i)
        switch try c.decode(String.self, forKey: .k) {
        case "set": self = .set(cell: cell, digit: try c.decode(Int.self, forKey: .d))
        case "clear": self = .clear(cell: cell)
        case let k: throw DecodingError.dataCorruptedError(forKey: .k, in: c, debugDescription: "unknown move \(k)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        switch self {
        case .set(let cell, let digit):
            try c.encode("set", forKey: .k)
            try c.encode(cell, forKey: .i)
            try c.encode(digit, forKey: .d)
        case .clear(let cell):
            try c.encode("clear", forKey: .k)
            try c.encode(cell, forKey: .i)
        }
    }
}

/// What the run's start answer carries as `puzzle`: the givens and nothing else.
public struct NineLivesPuzzle: Sendable, Equatable, Codable {
    public let givens: [Int]
    public init(givens: [Int]) { self.givens = givens }
}

/// The run's board as the server keeps it (`publicState`): every cell, and the cells hints filled.
public struct NineLivesState: Sendable, Equatable, Codable {
    public let cells: [Int]
    public let hinted: [Int]
    public init(cells: [Int], hinted: [Int]) {
        self.cells = cells
        self.hinted = hinted
    }
}

/// Why a move is refused, as the server's `Applied.reason`.
public enum NineLivesRefusal: String, Sendable, Equatable {
    /// A given, or a cell a hint filled.
    case illegal
    /// The grid is already solved.
    case over
}

public struct NineLivesBoard: Sendable, Equatable {
    public static let cellCount = 81

    public let givens: [Int]
    public private(set) var cells: [Int]
    /// Cells a hint filled, ascending. Locked like givens.
    public private(set) var hinted: [Int]

    public init(givens: [Int]) {
        precondition(givens.count == Self.cellCount, "a grid has 81 cells")
        self.givens = givens
        cells = givens
        hinted = []
    }

    /// A run picked up from the server: its puzzle and its board.
    public init(puzzle: NineLivesPuzzle, state: NineLivesState) {
        self.init(givens: puzzle.givens)
        cells = state.cells
        hinted = state.hinted
    }

    public var state: NineLivesState { NineLivesState(cells: cells, hinted: hinted) }

    private static let peerTable: [[Int]] = (0..<cellCount).map { i in
        let r = i / 9, c = i % 9, br = r / 3 * 3, bc = c / 3 * 3
        var set = Set<Int>()
        for k in 0..<9 {
            set.insert(r * 9 + k)
            set.insert(k * 9 + c)
            set.insert((br + k / 3) * 9 + bc + k % 3)
        }
        set.remove(i)
        return set.sorted()
    }

    /// The 20 cells sharing a row, column or box with `cell`.
    public static func peers(of cell: Int) -> [Int] { peerTable[cell] }

    public func isGiven(_ cell: Int) -> Bool { givens[cell] != 0 }
    public func isLocked(_ cell: Int) -> Bool { givens[cell] != 0 || hinted.contains(cell) }

    /// Cells whose digit repeats in one of their units, ascending. Givens count too.
    public var clashes: [Int] { Self.clashes(in: cells) }

    /// The clash scan, which runs on the main actor on every tap. It reads each cell once and, for a
    /// cell with a digit, its 20 peers until one matches: at most 81 times 21 reads, whatever the
    /// board. Generic so a test can count the reads (`NineLivesRulesTests.clashesAreCheap`).
    static func clashes<Cells: RandomAccessCollection>(in cells: Cells) -> [Int] where Cells.Index == Int, Cells.Element == Int {
        (0..<cellCount).filter { i in
            let d = cells[i]
            return d != 0 && peerTable[i].contains { cells[$0] == d }
        }
    }

    public var isFull: Bool { !cells.contains(0) }

    /// Full with no clash. The puzzle has one solution, so this is solved; the server says so too.
    public var looksSolved: Bool { isFull && clashes.isEmpty }

    /// Cells that started empty and now hold a digit, over the cells that started empty.
    public var progress: Double {
        var open = 0, placed = 0
        for i in 0..<Self.cellCount where givens[i] == 0 {
            open += 1
            if cells[i] != 0 { placed += 1 }
        }
        return open == 0 ? 1 : Double(placed) / Double(open)
    }

    /// How many cells hold `digit`.
    public func count(of digit: Int) -> Int { cells.reduce(0) { $0 + ($1 == digit ? 1 : 0) } }

    /// Plays `move`; nil when it was legal. A clash is legal: the board shows it.
    @discardableResult
    public mutating func apply(_ move: NineLivesMove) -> NineLivesRefusal? {
        if looksSolved { return .over }
        if isLocked(move.cell) { return .illegal }
        switch move {
        case .set(let cell, let digit): cells[cell] = digit
        case .clear(let cell): cells[cell] = 0
        }
        return nil
    }

    /// The server's hint filled `cell` with `digit`; that cell is locked from now on.
    public mutating func applyReveal(cell: Int, digit: Int) {
        cells[cell] = digit
        if !hinted.contains(cell) {
            hinted.append(cell)
            hinted.sort()
        }
    }
}
