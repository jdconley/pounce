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
