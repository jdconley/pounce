import Foundation
import Testing

@testable import PounceKit

/// The server's daily protocol samples (`apps/play-api/fixtures/daily/protocol/<name>.json`), each
/// an object of sample name to JSON, as raw data per sample.
enum DailyFixtures {
    static func samples(_ name: String) throws -> [String: Data] {
        let data = try Data(contentsOf: Fixtures.url("daily/protocol/\(name).json"))
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Fixtures.FixtureError.malformed(name)
        }
        return try object.mapValues { try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys, .fragmentsAllowed]) }
    }

    static func decode<T: Decodable>(_ type: T.Type, _ file: String, _ sample: String) throws -> T {
        guard let data = try samples(file)[sample] else { throw Fixtures.FixtureError.malformed("\(file).\(sample)") }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

@Suite struct DailyWireTests {
    @Test func everyHTTPSampleDecodes() throws {
        let start = try DailyFixtures.decode(DailyStart.self, "http", "start")
        #expect(start.game == "test" && start.seq == 0 && start.result == nil && start.puzzle["target"] == .int(4))
        let resumed = try DailyFixtures.decode(DailyStart.self, "http", "resumed")
        #expect(resumed.seq == 2 && resumed.state["n"] == .int(2))

        for name in ["movesOk", "movesSolved", "movesIllegal", "movesStale", "movesOver", "hint", "gaveUp"] {
            _ = try DailyFixtures.decode(DailyMovesAnswer.self, "http", name)
        }
        let solved = try DailyFixtures.decode(DailyMovesAnswer.self, "http", "movesSolved")
        guard case .accepted(3, [], 1, let result?) = solved else { Issue.record("movesSolved: \(solved)"); return }
        #expect(result.outcome == .solved && result.timeMs == 125_000 && result.hints == 1 && !result.tooFast)
        #expect(try DailyFixtures.decode(DailyMovesAnswer.self, "http", "movesIllegal") == .refused(.illegal, at: 0, seq: 2))
        #expect(try DailyFixtures.decode(DailyMovesAnswer.self, "http", "movesStale") == .refused(.stale, at: 0, seq: 2))
        #expect(try DailyFixtures.decode(DailyMovesAnswer.self, "http", "movesOver") == .refused(.over, at: 0, seq: 3))
        let hint = try DailyFixtures.decode(DailyMovesAnswer.self, "http", "hint")
        #expect(hint == .accepted(seq: 2, reveals: [.object(["n": .int(3)])], progress: 0.75, result: nil))

        let board = try DailyFixtures.decode(DailyBoard.self, "http", "board")
        #expect(board.tvs == 1)
        #expect(board.games.first?.rows.count == 3)
        #expect(board.mine("test")?.result?.outcome == .solved)
        #expect(board.best("test")?.isMe == true)
        let grandpa = board.games.first?.rows.last
        #expect(grandpa?.name == "Grandpa" && grandpa?.rank == nil && grandpa?.playing?.progress == 0.5)
        #expect(board.dish.rows.first?.points == 4 && board.dish.rows.first?.crowns == ["test"])

        let stats = try DailyFixtures.decode(DailyStatsList.self, "http", "stats")
        let test = try #require(stats.games["test"])
        #expect(test.played == 1 && test.solveRate == 1 && test.bestTimeMs == 125_000 && test.guesses.count == 6)
        #expect(test.last30.first?.result.outcome == .solved)
    }

    @Test func everySocketSampleDecodes() throws {
        let samples = try DailyFixtures.samples("socket")
        #expect(samples.count >= 11)
        for (name, data) in samples {
            let message = try JSONDecoder().decode(DailyBoardMessage.self, from: data)
            switch (name, message) {
            case ("board", .board(let b)): #expect(b.tvs == 1)
            case ("result", .result(let player, let r)): #expect(player.hasPrefix("pr_") && r.outcome == .solved)
            case ("progress", .progress(_, "test", 0.5)): break
            case ("watchOffer", .watchOffer(_, "Kid", 5, "test")): break
            case ("watch", .watch(_, "test", let puzzle, let state)): #expect(state["n"] == .int(2) && puzzle["target"] == .int(4))
            case ("watchEnd", .watchEnd(_, _, let r)): #expect(r != nil)
            case ("watchEndOff", .watchEnd(_, _, nil)): break
            case ("pong", .pong): break
            case ("error", .error("not_allowed")): break
            case ("tvs", .tvs(1)): break
            // The TV's screen socket says `{t: "board", token}`; on the board socket it's no snapshot.
            case ("linkBoard", .unknown("board")): break
            default: Issue.record("\(name) decoded as \(message)")
            }
        }
    }

    @Test func unknownKindsAreSkipped() {
        #expect(DailyBoardMessage.decode(#"{"t":"later","x":1}"#) == .unknown("later"))
        #expect(DailyBoardMessage.decode("not json") == nil)
    }

    @Test func clientBodiesEncode() throws {
        struct Step: Encodable { var k = "step"; let n: Int }
        let body = DailyMovesBody(from: 0, moves: [try DailyJSON(Step(n: 1)), try DailyJSON(Step(n: 2))])
        let ours = try JSONDecoder().decode(DailyJSON.self, from: JSONEncoder().encode(body))
        let theirs = try DailyFixtures.decode(DailyJSON.self, "client", "moves")
        #expect(ours == theirs)
        // The hint's body: the hints used so far, as the session sends it.
        let hint = try JSONDecoder().decode(DailyJSON.self, from: JSONEncoder().encode(["hints": 0]))
        #expect(hint == (try DailyFixtures.decode(DailyJSON.self, "client", "hint")))
    }

    @Test func aResultForAnotherDateLeavesTheBoard() throws {
        let board = try DailyFixtures.decode(DailyBoard.self, "http", "board")
        let yesterday = DailyResult(game: "test", date: "2026-11-22", number: -26337, outcome: .closed, timeMs: 1, progress: 0.1)
        #expect(board.adding(yesterday, for: "pr_Hn5sW2qLp7Xy3Zc8Vb1MkA") == board)
    }

    @Test func addingAResultFillsTheRow() throws {
        let board = try DailyFixtures.decode(DailyBoard.self, "http", "board")
        let done = DailyResult(game: "test", date: "2026-11-23", number: -26336, outcome: .solved, timeMs: 200_000, progress: 1)
        let next = board.adding(done, for: "pr_Hn5sW2qLp7Xy3Zc8Vb1MkA")
        let row = next.games.first?.rows.last
        #expect(row?.result == done && row?.playing == nil)
        let moved = board.moving("pr_Hn5sW2qLp7Xy3Zc8Vb1MkA", game: "test", progress: 0.75)
        #expect(moved.games.first?.rows.last?.playing?.progress == 0.75)
        #expect(board.with(tvs: 0).tvs == 0)
    }

    @Test func theDishShowsNobodyAtZero() {
        let dish = DailyDish(rows: [
            DailyDishRow(player: "me", name: "Mom", cat: 1, rank: 1, points: 6, crowns: [], ended: 2),
            DailyDishRow(player: "pr_a", name: "Kid", cat: 2, rank: 1, points: 6, crowns: [], ended: 2),
            DailyDishRow(player: "pr_b", name: "Gramps", cat: 3, rank: 3, points: 0, crowns: [], ended: 0),
        ])
        #expect(dish.shown.map(\.player) == ["me", "pr_a"])
        #expect(dish.shown.map(\.rank) == [1, 1])
    }

    @Test func summariesReadAsTheSpecSays() {
        func r(_ outcome: DailyOutcome, ms: Int = 247_000, guesses: Int? = nil, points: Int? = nil, n: Int = 12) -> DailyResult {
            DailyResult(game: "x", date: "d", number: n, outcome: outcome, timeMs: ms, progress: 1, guesses: guesses, points: points)
        }
        #expect(DailyCatalog.sniff.line(r(.solved, guesses: 4)) == "Sniff 12: 4 of 6")
        #expect(DailyCatalog.sniff.line(r(.missed, guesses: 6)) == "Sniff 12: X of 6")
        #expect(DailyCatalog.nineLives.line(r(.solved)) == "Nine Lives 12: 4:07")
        #expect(DailyCatalog.catNap.line(r(.gaveUp)) == "Cat Nap 12: Gave up")
        #expect(DailyCatalog.boxFort.line(r(.done, points: 1240)) == "Box Fort 12: 1,240 points")
        #expect(DailyCatalog.sniff.short(r(.solved, guesses: 3)) == "3/6")
    }
}
