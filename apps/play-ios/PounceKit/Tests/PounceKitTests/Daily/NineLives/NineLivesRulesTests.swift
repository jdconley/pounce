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

    /// Clashes run on the main actor on every tap; they must stay far under a frame.
    @Test func clashesAreCheap() {
        var cells = [Int](repeating: 0, count: 81)
        for i in 0..<81 { cells[i] = (i * 7) % 9 + 1 }
        let board = NineLivesBoard(givens: cells)
        let start = ContinuousClock.now
        for _ in 0..<1000 { _ = board.clashes }
        let each = (ContinuousClock.now - start) / 1000
        #expect(each < .microseconds(200), "clashes took \(each)")
    }
}
