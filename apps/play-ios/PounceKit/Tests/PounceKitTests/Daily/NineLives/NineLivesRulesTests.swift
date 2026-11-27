import Foundation
import Testing
@testable import PounceKit

/// `apps/play-api/fixtures/daily/nine-lives/rules.json`, written by the server's
/// `src/daily/nine-lives/vectors.ts`. The server's rules are the truth; these must match them.
struct NineLivesVectors: Decodable {
    struct Step: Decodable {
        let move: NineLivesMove?
        let hint: Reveal?
        let ok: Bool
        let reason: String?
        let cells: String
        let hinted: [Int]
        let clashes: [Int]
        let full: Bool
        let end: String?
        let progress: Double
    }

    struct Reveal: Decodable {
        let i: Int
        let d: Int
    }

    struct Case: Decodable, CustomTestStringConvertible {
        let name: String
        let givens: String
        let steps: [Step]
        var testDescription: String { name }
    }

    struct Wire: Decodable {
        let puzzle: NineLivesPuzzle
        let state: NineLivesState
        let moves: [NineLivesMove]
    }

    let wire: Wire
    let cases: [Case]

    static let url = Fixtures.url("daily/nine-lives/rules.json")

    static func load() throws -> NineLivesVectors {
        try JSONDecoder().decode(NineLivesVectors.self, from: Data(contentsOf: url))
    }

    static func digits(_ text: String) -> [Int] { text.map { Int(String($0))! } }
}

@Suite struct NineLivesRulesTests {
    @Test(arguments: try NineLivesVectors.load().cases)
    func vector(_ c: NineLivesVectors.Case) throws {
        var board = NineLivesBoard(givens: NineLivesVectors.digits(c.givens))
        var solved = false
        for (n, step) in c.steps.enumerated() {
            let label = Comment(rawValue: "\(c.name), step \(n)")
            if let move = step.move {
                let refusal = board.apply(move)
                #expect((refusal == nil) == step.ok, label)
                #expect(refusal?.rawValue == step.reason, label)
            } else if let reveal = step.hint {
                board.applyReveal(cell: reveal.i, digit: reveal.d)
            } else {
                // A hint the server refused (the grid was solved): nothing changes.
                #expect(!step.ok && board.looksSolved, label)
            }
            #expect(board.cells == NineLivesVectors.digits(step.cells), label)
            #expect(board.hinted == step.hinted, label)
            #expect(board.clashes == step.clashes, label)
            #expect(board.isFull == step.full, label)
            if step.end == "solved" { solved = true }
            // The server ends the run solved exactly when the board first looks solved.
            #expect(board.looksSolved == solved, label)
            #expect(board.progress == step.progress, label)
        }
    }

    @Test func wireShapes() throws {
        let v = try NineLivesVectors.load()
        let board = NineLivesBoard(puzzle: v.wire.puzzle, state: v.wire.state)
        #expect(board.cells == v.wire.state.cells)
        #expect(board.state == v.wire.state)
        // Moves encode to the server's exact shape.
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: NineLivesVectors.url)) as! [String: Any]
        let wire = raw["wire"] as! [String: Any]
        let expected = try (wire["moves"] as! [Any]).map {
            String(data: try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]), encoding: .utf8)!
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let mine = try v.wire.moves.map { String(data: try encoder.encode($0), encoding: .utf8)! }
        #expect(mine == expected)
    }

    @Test func peersAndLocks() {
        #expect((0..<81).allSatisfy { NineLivesBoard.peers(of: $0).count == 20 })
        var givens = [Int](repeating: 0, count: 81)
        givens[0] = 5
        var board = NineLivesBoard(givens: givens)
        #expect(board.isLocked(0))
        #expect(!board.isLocked(1))
        #expect(board.apply(.set(cell: 1, digit: 5)) == nil)
        #expect(board.count(of: 5) == 2)
        #expect(board.clashes == [0, 1])
        board.applyReveal(cell: 2, digit: 7)
        #expect(board.isLocked(2))
        #expect(board.apply(.clear(cell: 2)) == .illegal)
    }

    // MARK: the lives rules (docs/daily-protocol.md, "## Nine Lives")

    private static func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private static let cells81 = "[" + Array(repeating: "0", count: 81).joined(separator: ",") + "]"

    @Test func aFirstRulesStateHasNoLives() throws {
        let state = try Self.decode(NineLivesState.self, #"{"cells":\#(Self.cells81),"hinted":[]}"#)
        #expect(state.rules == .first && state.lives == 3 && state.hintsLeft == 3 && state.wrong.isEmpty && state.solution == nil)
        // And encodes as it came: the first rules' two fields only.
        let back = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as! [String: Any]
        #expect(Set(back.keys) == ["cells", "hinted"])
    }

    @Test func aLivesStateDecodesLeniently() throws {
        let state = try Self.decode(
            NineLivesState.self,
            #"{"cells":\#(Self.cells81),"hinted":[3],"rules":"lives","lives":1,"hintsLeft":2,"wrong":[{"i":4,"d":7},{"i":"x"},{"i":9,"d":2}],"later":true}"#)
        #expect(state.rules == .lives && state.lives == 1 && state.hintsLeft == 2)
        #expect(state.wrong == [NineLivesWrong(i: 4, d: 7), NineLivesWrong(i: 9, d: 2)])
        #expect(state.solution == nil)
        let solved = String(repeating: "1,", count: 80) + "1"
        let out = try Self.decode(
            NineLivesState.self, #"{"cells":\#(Self.cells81),"rules":"lives","lives":0,"hintsLeft":"x","solution":[\#(solved)]}"#)
        #expect(out.lives == 0 && out.hintsLeft == 3 && out.solution?.count == 81 && out.hinted.isEmpty)
        // Out of range counts are clamped; a short solution is no solution.
        let odd = try Self.decode(NineLivesState.self, #"{"cells":\#(Self.cells81),"rules":"lives","lives":9,"solution":[1,2]}"#)
        #expect(odd.lives == 3 && odd.solution == nil)
        // Rules a newer server names play as lives.
        #expect(try Self.decode(NineLivesState.self, #"{"cells":\#(Self.cells81),"rules":"more"}"#).rules == .lives)
        // Round trip.
        #expect(try Self.decode(NineLivesState.self, String(data: JSONEncoder().encode(state), encoding: .utf8)!) == state)
    }

    @Test func revealsDecode() throws {
        #expect(try Self.decode(NineLivesReveal.self, #"{"i":4,"d":7}"#) == .hint(cell: 4, digit: 7))
        #expect(try Self.decode(NineLivesReveal.self, #"{"k":"wrong","i":4,"d":7,"lives":2}"#) == .wrong(cell: 4, digit: 7, lives: 2, solution: nil))
        #expect(try Self.decode(NineLivesReveal.self, #"{"k":"wrong","i":4,"d":7}"#) == .wrong(cell: 4, digit: 7, lives: 0, solution: nil))
        let solution = Array(repeating: 5, count: 81)
        #expect(
            try Self.decode(NineLivesReveal.self, #"{"k":"wrong","i":4,"d":7,"lives":0,"solution":\#(solution)}"#)
                == .wrong(cell: 4, digit: 7, lives: 0, solution: solution))
        // A short solution is none.
        #expect(try Self.decode(NineLivesReveal.self, #"{"k":"wrong","i":4,"d":7,"lives":0,"solution":[1]}"#) == .wrong(cell: 4, digit: 7, lives: 0, solution: nil))
        #expect(try Self.decode(NineLivesReveal.self, #"{"k":"sparkle","i":1}"#) == .other)
        #expect(try Self.decode(NineLivesReveal.self, #"{"k":"wrong","i":1}"#) == .other)
    }

    /// The server's samples (`apps/play-api/fixtures/daily/protocol/nine-lives.json`).
    @Test func theServersSamplesDecode() throws {
        func start(_ name: String) throws -> (DailyStart, NineLivesState) {
            let start = try DailyFixtures.decode(DailyStart.self, "nine-lives", name)
            return (start, try start.state.decoded(as: NineLivesState.self))
        }
        func reveals(_ name: String) throws -> [NineLivesReveal] {
            guard case .accepted(_, let reveals, _, _) = try DailyFixtures.decode(DailyMovesAnswer.self, "nine-lives", name) else {
                Issue.record("\(name) refused")
                return []
            }
            return try reveals.map { try $0.decoded(as: NineLivesReveal.self) }
        }
        // The 1.2 and 1.3 apps' runs: the first rules, 30 seconds a hint.
        let (first, firstState) = try start("firstRules")
        #expect(first.hintMs == 30_000 && firstState.rules == .first)
        let (fresh, state) = try start("start")
        #expect(fresh.hintMs == 0 && state.rules == .lives && state.lives == 3 && state.hintsLeft == 3 && state.wrong.isEmpty)
        #expect(try reveals("movesRight").isEmpty)
        #expect(try reveals("movesWrong") == [.wrong(cell: 2, digit: 1, lives: 2, solution: nil)])
        #expect(try reveals("hint") == [.hint(cell: 5, digit: 1)])
        let (_, resumed) = try start("resumed")
        #expect(resumed.lives == 2 && resumed.hintsLeft == 2 && resumed.wrong == [NineLivesWrong(i: 2, d: 1)] && resumed.hinted == [5])
        #expect(try DailyFixtures.decode(DailyMovesAnswer.self, "nine-lives", "hintNoneLeft") == .refused(.illegal, at: 0, seq: 2))
        #expect(try DailyFixtures.decode(DailyMovesAnswer.self, "nine-lives", "movesClear") == .refused(.illegal, at: 0, seq: 0))
        let out = try reveals("movesOutOfLives")
        guard case .wrong(11, 9, 0, let solution?) = out.last else {
            Issue.record("no solution on the last wrong number: \(out)")
            return
        }
        #expect(out.count == 2 && solution.count == 81)
        guard case .accepted(_, _, _, let result?) = try DailyFixtures.decode(DailyMovesAnswer.self, "nine-lives", "movesOutOfLives") else {
            Issue.record("no result")
            return
        }
        #expect(result.outcome == .missed && DailyCatalog.nineLives.summary(result) == "Out of lives")
        let (ended, endedState) = try start("resumedOutOfLives")
        #expect(ended.result?.outcome == .missed && endedState.lives == 0 && endedState.solution == solution)
        // A board picked up from it is out of lives and shows the solution.
        let board = NineLivesBoard(puzzle: try ended.puzzle.decoded(as: NineLivesPuzzle.self), state: endedState)
        #expect(board.isOutOfLives && board.solution == solution && board.hintsLeft == 0 && !board.hintsAvailable)
    }

    @Test func livesLockRightDigitsAndCountWrongOnes() {
        var givens = [Int](repeating: 0, count: 81)
        givens[0] = 5
        var board = NineLivesBoard(givens: givens, rules: .lives)
        #expect(board.playsLives && board.lives == 3 && board.hintsLeft == 3)
        // A set goes in, and a right one locks: it can't be cleared or changed.
        #expect(board.apply(.set(cell: 1, digit: 3)) == nil)
        #expect(board.isLocked(1))
        #expect(board.apply(.set(cell: 1, digit: 4)) == .illegal)
        #expect(board.apply(.clear(cell: 2)) == .illegal)
        // A wrong one comes out, costs a life and is remembered.
        #expect(board.apply(.set(cell: 2, digit: 8)) == nil)
        board.applyWrong(cell: 2, digit: 8, lives: 2)
        #expect(board.cells[2] == 0 && !board.isLocked(2) && board.lives == 2 && board.costALife(2, 8) && !board.costALife(2, 7))
        // The same answer twice (a resent batch) counts once.
        board.applyWrong(cell: 2, digit: 8, lives: 2)
        #expect(board.wrong == [NineLivesWrong(i: 2, d: 8)] && board.lives == 2)
        // Hints run out at three; lives never limit them.
        board.applyReveal(cell: 10, digit: 1)
        board.applyReveal(cell: 11, digit: 2)
        board.applyReveal(cell: 12, digit: 3)
        #expect(board.hintsLeft == 0 && !board.hintsAvailable && board.lives == 2)
        // The third wrong number ends it, and the solution comes.
        board.applyWrong(cell: 3, digit: 1, lives: 1)
        board.applyWrong(cell: 4, digit: 1, lives: 0)
        #expect(board.isOutOfLives)
        #expect(board.apply(.set(cell: 5, digit: 1)) == .over)
        board.applySolution(Array(repeating: 9, count: 81))
        #expect(board.solution?.count == 81)
        // The state carries it all.
        let state = board.state
        #expect(state.rules == .lives && state.lives == 0 && state.hintsLeft == 0 && state.wrong.count == 3 && state.solution != nil)
        #expect(NineLivesBoard(puzzle: NineLivesPuzzle(givens: givens), state: state) == board)
    }

    @Test func theFirstRulesKeepUnlimitedHints() {
        var board = NineLivesBoard(givens: [Int](repeating: 0, count: 81))
        for i in 0..<5 { board.applyReveal(cell: i, digit: i + 1) }
        #expect(board.hintsAvailable && !board.playsLives && !board.isLocked(9))
        #expect(board.apply(.set(cell: 9, digit: 1)) == nil)
        #expect(board.apply(.clear(cell: 9)) == nil)
    }

    /// Clashes run on the main actor on every tap, so the scan must stay a fixed, small amount of
    /// work: each cell, and a filled cell's 20 peers at most, never more as the board fills. This
    /// counts the cell reads, which a clock in a parallel test run can't measure honestly; the
    /// time on a device is the iPhone frame gate's (`NineLivesTests.testNineLivesHoldsTheFrameRate`).
    @Test func clashesAreCheap() {
        let most = NineLivesBoard.cellCount * (1 + 20)
        // A solved grid: no clash, so every cell reads all 20 peers. The most there can be.
        let solved = (0..<81).map { i in (i / 9 * 3 + i / 27 + i % 9) % 9 + 1 }
        #expect(Self.reads(solved) == (most, []))
        // An empty grid reads each cell once.
        #expect(Self.reads([Int](repeating: 0, count: 81)) == (81, []))
        // A grid of one digit stops at each cell's first peer.
        #expect(Self.reads([Int](repeating: 5, count: 81)) == (81 * 2, Array(0..<81)))
        // Any other grid, among them the vectors' boards, is in between, and the counted scan is the board's.
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            let cells = (0..<81).map { _ in Int.random(in: 0...9, using: &rng) }
            let (n, clashes) = Self.reads(cells)
            #expect(n <= most, "\(n) reads")
            #expect(clashes == NineLivesBoard(givens: cells).clashes)
        }
    }

    /// The clash scan over `cells`, and how many cell reads it made.
    private static func reads(_ cells: [Int]) -> (Int, [Int]) {
        let counted = Counted(cells)
        let clashes = NineLivesBoard.clashes(in: counted)
        return (counted.count.n, clashes)
    }
}

/// Cells that count their reads.
private struct Counted: RandomAccessCollection {
    final class Count { var n = 0 }
    let cells: [Int]
    let count = Count()
    init(_ cells: [Int]) { self.cells = cells }
    var startIndex: Int { 0 }
    var endIndex: Int { cells.count }
    subscript(i: Int) -> Int {
        count.n += 1
        return cells[i]
    }
}
