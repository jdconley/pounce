import Foundation
import Testing
@testable import PounceKit

/// One entry of `apps/play-api/fixtures/daily/cat-nap/vectors.json`: a quilt, a start, and steps,
/// each with what the server's rules (`src/daily/cat-nap/rules.ts`) say after it. Read with
/// `JSONSerialization`, since a step's raw move is any JSON (the bad shapes are the point).
struct CatNapVector: CustomTestStringConvertible, @unchecked Sendable {
    struct Step {
        /// The step's input: a raw move, a hint's cell, a tap, or a drag's cells.
        let raw: [String: Any]
        let made: [String: Any]??
        let ok: Bool
        let state: NapState
        let clashes: NapClashes
        let complete: Bool
        let placed: Int
    }

    let name: String
    let quilt: NapQuilt
    let start: NapState
    let steps: [Step]

    var testDescription: String { name }

    static func load() throws -> [CatNapVector] {
        let data = try Data(contentsOf: Fixtures.url("daily/cat-nap/vectors.json"))
        let all = try #require(try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [[String: Any]])
        return try all.map { v in
            let q = try #require(v["quilt"] as? [String: Any])
            return CatNapVector(
                name: try #require(v["name"] as? String),
                quilt: NapQuilt(n: try #require(q["n"] as? Int), patches: try #require(q["patches"] as? [Int])),
                start: try state(v["start"]),
                steps: try #require(v["steps"] as? [[String: Any]]).map { s in
                    let c = try #require(s["clashes"] as? [String: [Int]])
                    return Step(
                        raw: s,
                        made: s.keys.contains("made") ? .some(s["made"] as? [String: Any]) : .none,
                        ok: try #require(s["ok"] as? Bool),
                        state: try state(s["state"]),
                        clashes: NapClashes(
                            rows: try #require(c["rows"]), cols: try #require(c["cols"]),
                            patches: try #require(c["patches"]), touching: try #require(c["touching"]),
                            cells: try #require(c["cells"])),
                        complete: try #require(s["complete"] as? Bool),
                        placed: try #require(s["placed"] as? Int))
                })
        }
    }

    private static func state(_ any: Any?) throws -> NapState {
        let s = try #require(any as? [String: Any])
        return NapState(cells: try #require(s["cells"] as? [Int]).map { UInt8($0) }, hinted: try #require(s["hinted"] as? [Int]))
    }
}

/// What a step's input does, by the Swift rules: `ok`, the board after it, and for taps and drags
/// the move the client helpers made.
private func run(_ quilt: NapQuilt, _ state: NapState, _ step: [String: Any]) -> (ok: Bool, state: NapState, made: NapMove?) {
    if let cell = step["hint"] as? Int { return (true, CatNapRules.applyHint(quilt, state, cell: cell), nil) }
    let made: NapMove?
    if let raw = step["move"] {
        made = NapMove(json: raw)
    } else if let cell = step["tap"] as? Int {
        made = CatNapRules.tapMove(state, cell: cell)
    } else {
        let cells = step["drag"] as? [Int] ?? []
        made = CatNapRules.dragPaint(state, start: cells[0]).flatMap { CatNapRules.dragMove(state, paint: $0, passed: cells) }
    }
    guard let made, let next = CatNapRules.apply(quilt, state, made) else { return (false, state, made) }
    return (true, next, made)
}

@Suite struct CatNapRulesTests {
    @Test(arguments: try CatNapVector.load())
    func vector(_ v: CatNapVector) throws {
        var state = v.start
        for (i, step) in v.steps.enumerated() {
            let out = run(v.quilt, state, step.raw)
            #expect(out.ok == step.ok, "step \(i)")
            if let expected = step.made {
                if let expected {
                    let json = try #require(out.made).json
                    #expect(json["cells"] as? [Int] == expected["cells"] as? [Int], "step \(i)")
                    #expect(json["to"] as? String == expected["to"] as? String, "step \(i)")
                    #expect(json["k"] as? String == "mark")
                } else {
                    #expect(out.made == nil, "step \(i)")
                }
            }
            state = out.state
            #expect(state == step.state, "step \(i)")
            #expect(CatNapRules.clashes(v.quilt, state) == step.clashes, "step \(i)")
            #expect(CatNapRules.complete(v.quilt, state) == step.complete, "step \(i)")
            #expect(CatNapRules.placed(v.quilt, state) == step.placed, "step \(i)")
        }
    }

    @Test func movesEncodeAsTheServerReadsThem() throws {
        let move = NapMove(cells: [3, 4], to: .x)
        let data = try JSONEncoder().encode(move)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["k"] as? String == "mark")
        #expect(NapMove(json: object) == move)
        #expect(try JSONDecoder().decode(NapMove.self, from: data) == move)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(NapMove.self, from: Data(#"{"k":"step","cells":[1],"to":"x"}"#.utf8)) }
    }

    @Test func aBooleanIsNotACell() {
        #expect(NapMove(json: ["k": "mark", "cells": [true], "to": "x"]) == nil)
    }

    @Test func checkOffMainMatches() async {
        let quilt = NapQuilt(n: 5, patches: [0, 0, 1, 1, 1, 0, 2, 2, 1, 1, 3, 2, 2, 2, 1, 3, 3, 2, 4, 4, 3, 3, 4, 4, 4])
        var state = NapState.empty(quilt)
        state.cells[0] = 2
        state.cells[1] = 2
        let check = await CatNapRules.check(quilt, state)
        #expect(check == CatNapRules.clashes(quilt, state))
        #expect(check.cells == [0, 1])
    }
}
