import Foundation
import Testing
@testable import PounceKit

/// One file of `apps/play-api/fixtures/daily/box-fort/`: a puzzle as a client sees it, then every
/// move with what the server answered and the public state after it. Written by the TS rules
/// (`pnpm --filter @pounce/play-api vectors:box-fort`); the client shows the score at once, so it
/// has to agree with the server's on every step.
struct BoxFortVector: Decodable, Sendable, CustomTestStringConvertible {
    struct Move: Decodable, Sendable {
        let k: String
        let slot: Int
        let row: Int
        let col: Int
    }

    struct Step: Decodable, Sendable {
        let move: Move
        let ok: Bool
        let reason: String?
        let gained: Int?
        let cleared: BoxFortCleared?
        let reveal: BoxFortReveal?
        let end: String?
        let state: BoxFortState
    }

    let name: String
    let start: BoxFortPublicPuzzle
    let steps: [Step]

    var testDescription: String { name }

    static func all() throws -> [BoxFortVector] {
        let dir = Fixtures.url("daily/box-fort")
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(".json") }
            .sorted()
        return try files.map { try JSONDecoder().decode(BoxFortVector.self, from: Data(contentsOf: dir.appendingPathComponent($0))) }
    }
}

struct BoxFortVectorTests {
    @Test func theVectorsAreThere() throws {
        let names = try BoxFortVector.all().map(\.name)
        #expect(names.count >= 15)
        for name in ["clears", "combos", "cross", "full-fort", "illegal", "nothing-fits-mid-set", "nothing-fits-on-deal", "placements"] {
            #expect(names.contains(name), "missing \(name)")
        }
    }

    @Test(arguments: try BoxFortVector.all())
    func everyStepMatchesTheServer(_ vector: BoxFortVector) throws {
        var state = BoxFortRules.start(vector.start)
        for (i, step) in vector.steps.enumerated() {
            let move = step.move
            #expect(move.k == "place")
            let out = BoxFortRules.step(state, slot: move.slot, row: move.row, col: move.col)
            guard step.ok else {
                #expect(out == nil, "\(vector.name) step \(i): the server refused it (\(step.reason ?? ""))")
                #expect(state == step.state, "\(vector.name) step \(i)")
                continue
            }
            let placed = try #require(out, "\(vector.name) step \(i): the server took it")
            #expect(placed.cleared == step.cleared, "\(vector.name) step \(i)")
            var next = placed.state
            if placed.setDone {
                if let reveal = step.reveal {
                    #expect(reveal.set == state.set + 1)
                    next = BoxFortRules.deal(next, next: reveal.pieces)
                } else {
                    #expect(next.set + 1 == next.sets, "\(vector.name) step \(i): no set dealt before the last")
                    next = BoxFortRules.deal(next, next: nil)
                }
            } else {
                #expect(step.reveal == nil)
            }
            #expect(next.points - state.points == step.gained, "\(vector.name) step \(i)")
            #expect((next.over != nil) == (step.end == "done"), "\(vector.name) step \(i)")
            #expect(next == step.state, "\(vector.name) step \(i)")
            state = next
        }
    }
}
