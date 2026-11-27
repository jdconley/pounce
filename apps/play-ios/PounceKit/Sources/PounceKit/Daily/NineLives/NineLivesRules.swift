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

/// Which rules a run plays, fixed at its first start (docs/daily-protocol.md, "## Nine Lives").
public enum NineLivesRules: String, Sendable, Equatable, Codable {
    /// No `rules` at start (every app before 2026-11-26): no check against the solution, clashes,
    /// unlimited hints at 30 seconds each.
    case first
    /// `{ "rules": "lives" }`: a wrong number costs one of three lives, right numbers lock, three
    /// free hints.
    case lives

    public static let lifeCount = 3
    public static let hintCount = 3
}

/// A wrong number, as the server lists it: cell `i`, digit `d`.
public struct NineLivesWrong: Sendable, Equatable, Hashable, Codable {
    public let i: Int
    public let d: Int
    public init(i: Int, d: Int) {
        self.i = i
        self.d = d
    }
}

/// The run's board as the server keeps it (`publicState`): every cell, and the cells hints filled.
/// Under the lives rules also what is left (`lives`, `hintsLeft`), every wrong number entered, and
/// the solution once the run ended out of lives. Every field past `cells` decodes leniently.
public struct NineLivesState: Sendable, Equatable, Codable {
    public let cells: [Int]
    public let hinted: [Int]
    public let rules: NineLivesRules
    public let lives: Int
    public let hintsLeft: Int
    public let wrong: [NineLivesWrong]
    public let solution: [Int]?

    public init(
        cells: [Int], hinted: [Int], rules: NineLivesRules = .first, lives: Int = NineLivesRules.lifeCount,
        hintsLeft: Int = NineLivesRules.hintCount, wrong: [NineLivesWrong] = [], solution: [Int]? = nil
    ) {
        self.cells = cells
        self.hinted = hinted
        self.rules = rules
        self.lives = lives
        self.hintsLeft = hintsLeft
        self.wrong = wrong
        self.solution = solution
    }

    private enum Key: String, CodingKey { case cells, hinted, rules, lives, hintsLeft, wrong, solution }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        cells = try c.decode([Int].self, forKey: .cells)
        hinted = (try? c.decodeIfPresent([Int].self, forKey: .hinted)) ?? []
        // An unknown rules name is a newer server's: play it as lives, the rules that check.
        let name = (try? c.decodeIfPresent(String.self, forKey: .rules)) ?? nil
        rules = name.map { NineLivesRules(rawValue: $0) ?? .lives } ?? .first
        lives = ((try? c.decodeIfPresent(Int.self, forKey: .lives)) ?? nil).map { min(max($0, 0), NineLivesRules.lifeCount) }
            ?? NineLivesRules.lifeCount
        hintsLeft = ((try? c.decodeIfPresent(Int.self, forKey: .hintsLeft)) ?? nil).map { max($0, 0) } ?? NineLivesRules.hintCount
        // One odd entry drops itself, not the list.
        let raw = ((try? c.decodeIfPresent([DailyJSON].self, forKey: .wrong)) ?? nil) ?? []
        wrong = raw.compactMap { try? $0.decoded(as: NineLivesWrong.self) }
        let solution = (try? c.decodeIfPresent([Int].self, forKey: .solution)) ?? nil
        self.solution = solution?.count == NineLivesBoard.cellCount ? solution : nil
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        try c.encode(cells, forKey: .cells)
        try c.encode(hinted, forKey: .hinted)
        guard rules == .lives else { return }
        try c.encode(rules, forKey: .rules)
        try c.encode(lives, forKey: .lives)
        try c.encode(hintsLeft, forKey: .hintsLeft)
        try c.encode(wrong, forKey: .wrong)
        try c.encodeIfPresent(solution, forKey: .solution)
    }
}

/// What the server reveals for Nine Lives. A hint is `{ i, d }`; under the lives rules a wrong set
/// is `{ k: "wrong", i, d, lives }`, and the one that leaves no lives also carries
/// `"solution": [81]`. A kind this app doesn't know decodes as `.other` and is skipped.
public enum NineLivesReveal: Sendable, Equatable, Decodable {
    case hint(cell: Int, digit: Int)
    /// `lives`: what is left after it. `solution`: only on the one that leaves none.
    case wrong(cell: Int, digit: Int, lives: Int, solution: [Int]?)
    case other

    private enum Key: String, CodingKey { case k, i, d, lives, solution }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        let k = (try? c.decodeIfPresent(String.self, forKey: .k)) ?? nil
        let i = (try? c.decodeIfPresent(Int.self, forKey: .i)) ?? nil
        let d = (try? c.decodeIfPresent(Int.self, forKey: .d)) ?? nil
        switch k {
        case nil:
            if let i, let d { self = .hint(cell: i, digit: d) } else { self = .other }
        case "wrong":
            guard let i, let d else { self = .other; return }
            let lives = ((try? c.decodeIfPresent(Int.self, forKey: .lives)) ?? nil) ?? 0
            let solution = (try? c.decodeIfPresent([Int].self, forKey: .solution)) ?? nil
            self = .wrong(
                cell: i, digit: d, lives: min(max(lives, 0), NineLivesRules.lifeCount),
                solution: solution?.count == NineLivesBoard.cellCount ? solution : nil)
        default:
            self = .other
        }
    }
}

/// Why a move is refused, as the server's `Applied.reason`.
public enum NineLivesRefusal: String, Sendable, Equatable {
    /// A given, or a cell a hint filled. Under the lives rules also a cell holding its answer, any
    /// `clear`, and a hint with none left.
    case illegal
    /// The grid is already solved.
    case over
}

public struct NineLivesBoard: Sendable, Equatable {
    public static let cellCount = 81

    public let givens: [Int]
    public let rules: NineLivesRules
    /// Under the first rules, any digit; under the lives rules, only right ones (and, on the phone,
    /// a set waiting for the server's answer).
    public private(set) var cells: [Int]
    /// Cells a hint filled, ascending. Locked like givens.
    public private(set) var hinted: [Int]
    /// The lives rules: lives left (3 to 0), hints left (3 to 0), every wrong number entered, and
    /// the solution once the run ended out of lives.
    public private(set) var lives = NineLivesRules.lifeCount
    public private(set) var hintsLeft = NineLivesRules.hintCount
    public private(set) var wrong: [NineLivesWrong] = []
    public private(set) var solution: [Int]?

    public init(givens: [Int], rules: NineLivesRules = .first) {
        precondition(givens.count == Self.cellCount, "a grid has 81 cells")
        self.givens = givens
        self.rules = rules
        cells = givens
        hinted = []
    }

    /// A run picked up from the server: its puzzle and its board.
    public init(puzzle: NineLivesPuzzle, state: NineLivesState) {
        self.init(givens: puzzle.givens, rules: state.rules)
        cells = state.cells
        hinted = state.hinted
        lives = state.lives
        hintsLeft = state.hintsLeft
        wrong = state.wrong
        solution = state.solution
    }

    public var state: NineLivesState {
        NineLivesState(cells: cells, hinted: hinted, rules: rules, lives: lives, hintsLeft: hintsLeft, wrong: wrong, solution: solution)
    }

    public var playsLives: Bool { rules == .lives }
    /// The lives rules, and none left: the run ended `missed`.
    public var isOutOfLives: Bool { playsLives && lives == 0 }
    /// A hint may be asked: always under the first rules, while some are left under lives.
    public var hintsAvailable: Bool { !playsLives || hintsLeft > 0 }
    /// Under the lives rules, this digit in this cell already cost a life: never send it again.
    public func costALife(_ cell: Int, _ digit: Int) -> Bool { wrong.contains(NineLivesWrong(i: cell, d: digit)) }

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
    /// A given or a hint's cell; under the lives rules, any cell holding a digit (a right one locks).
    public func isLocked(_ cell: Int) -> Bool {
        givens[cell] != 0 || hinted.contains(cell) || (playsLives && cells[cell] != 0)
    }

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

    /// Plays `move`; nil when it was legal. A clash is legal: the board shows it. Under the lives
    /// rules a set goes in as if right (the server's answer may take it out again, `applyWrong`),
    /// and `clear` is illegal.
    @discardableResult
    public mutating func apply(_ move: NineLivesMove) -> NineLivesRefusal? {
        if looksSolved || isOutOfLives { return .over }
        if isLocked(move.cell) { return .illegal }
        if playsLives, case .clear = move { return .illegal }
        switch move {
        case .set(let cell, let digit): cells[cell] = digit
        case .clear(let cell): cells[cell] = 0
        }
        return nil
    }

    /// The server's hint filled `cell` with `digit`; that cell is locked from now on. Under the
    /// lives rules it uses one of the hints left.
    public mutating func applyReveal(cell: Int, digit: Int) {
        cells[cell] = digit
        if !hinted.contains(cell) {
            hinted.append(cell)
            hinted.sort()
            if playsLives { hintsLeft = max(0, hintsLeft - 1) }
        }
    }

    /// The server said `digit` in `cell` is wrong, with `lives` left: it comes out of the cell, and
    /// is kept in `wrong`. Said twice (a resent batch), it counts once.
    public mutating func applyWrong(cell: Int, digit: Int, lives left: Int) {
        if cells[cell] == digit, givens[cell] == 0, !hinted.contains(cell) { cells[cell] = 0 }
        let w = NineLivesWrong(i: cell, d: digit)
        if !wrong.contains(w) { wrong.append(w) }
        lives = min(lives, max(0, left))
    }

    /// The run ended out of lives: the server's solution, to show.
    public mutating func applySolution(_ cells: [Int]) {
        guard cells.count == Self.cellCount else { return }
        solution = cells
    }

    /// A set the phone shows that the server hasn't answered, taken back (it was refused, or the
    /// run ended first).
    public mutating func takeBack(cell: Int) {
        guard givens[cell] == 0, !hinted.contains(cell) else { return }
        cells[cell] = 0
    }
}
