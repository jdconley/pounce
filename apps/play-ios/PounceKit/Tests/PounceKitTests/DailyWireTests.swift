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
        let hint = try JSONDecoder().decode(DailyJSON.self, from: JSONEncoder().encode(DailyHintBody(hints: 0)))
        #expect(hint == (try DailyFixtures.decode(DailyJSON.self, "client", "hint")))
        // With active time: every moves batch, hint and give-up carries it.
        func json(_ value: some Encodable) throws -> DailyJSON { try JSONDecoder().decode(DailyJSON.self, from: JSONEncoder().encode(value)) }
        let active = DailyMovesBody(from: 0, moves: body.moves, activeMs: 18_250)
        #expect(try json(active) == (try DailyFixtures.decode(DailyJSON.self, "client", "movesActive")))
        #expect(try json(DailyHintBody(hints: 0, activeMs: 31_000)) == (try DailyFixtures.decode(DailyJSON.self, "client", "hintActive")))
        #expect(try json(DailyGiveUpBody(activeMs: 95_500)) == (try DailyFixtures.decode(DailyJSON.self, "client", "giveUpActive")))
        #expect(try json(["rules": DailyCatalog.nineLives.rules]) == (try DailyFixtures.decode(DailyJSON.self, "client", "startLives")))
    }

    @Test func activeTimeAndPercentDecode() throws {
        #expect(try DailyFixtures.decode(DailyStart.self, "http", "start").activeMs == 0)
        #expect(try DailyFixtures.decode(DailyStart.self, "http", "resumed").activeMs == 25_000)
        guard case .accepted(_, _, _, let solved?) = try DailyFixtures.decode(DailyMovesAnswer.self, "http", "movesSolved") else {
            Issue.record("no result")
            return
        }
        #expect(solved.percent == 100)
        let gaveUp = try DailyFixtures.decode(DailyMovesAnswer.self, "http", "gaveUp")
        guard case .accepted(_, _, _, let quit?) = gaveUp else { Issue.record("no result"); return }
        #expect(quit.percent == 25 && DailyCatalog.test.summary(quit) == "25%")
        // A result stored before percent: floor(progress * 100).
        let old = try JSONDecoder().decode(
            DailyResult.self,
            from: Data(#"{"game":"nine-lives","date":"d","number":1,"outcome":"missed","timeMs":1,"hints":0,"progress":0.629,"tooFast":false}"#.utf8))
        #expect(old.percent == nil && old.shownPercent == 62)
        let odd = try JSONDecoder().decode(
            DailyResult.self,
            from: Data(#"{"game":"nine-lives","date":"d","number":1,"outcome":"missed","timeMs":1,"progress":0.5,"percent":"lots"}"#.utf8))
        #expect(odd.shownPercent == 50 && odd.hints == 0)
        // And back again, as the store keeps it.
        let back = try JSONDecoder().decode(DailyResult.self, from: JSONEncoder().encode(quit))
        #expect(back == quit)
    }

    @Test func aResultForAnotherDateLeavesTheBoard() throws {
        let board = try DailyFixtures.decode(DailyBoard.self, "http", "board")
        let yesterday = DailyResult(game: "test", date: "2026-11-22", number: 1, outcome: .closed, timeMs: 1, progress: 0.1)
        #expect(board.adding(yesterday, for: "pr_Hn5sW2qLp7Xy3Zc8Vb1MkA") == board)
    }

    @Test func addingAResultFillsTheRow() throws {
        let board = try DailyFixtures.decode(DailyBoard.self, "http", "board")
        let done = DailyResult(game: "test", date: "2026-11-23", number: 2, outcome: .solved, timeMs: 200_000, progress: 1)
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
        #expect(DailyCatalog.sniff.line(r(.missed, guesses: 6)) == "Sniff 12: X of 6, 100%")
        #expect(DailyCatalog.nineLives.line(r(.solved)) == "Nine Lives 12: 4:07")
        #expect(DailyCatalog.catNap.line(r(.gaveUp)) == "Cat Nap 12: Gave up, 100%")
        #expect(DailyCatalog.boxFort.line(r(.done, points: 1240)) == "Box Fort 12: 1,240 points")
        #expect(DailyCatalog.sniff.short(r(.solved, guesses: 3)) == "3/6")
        // A run that didn't finish says how far it got (spec §6, "Ranking"); the share line also
        // says how it ended: Nine Lives' third wrong number is "Out of lives".
        func unfinished(_ outcome: DailyOutcome, percent: Int?, progress: Double = 0.4) -> DailyResult {
            DailyResult(game: "x", date: "d", number: 12, outcome: outcome, timeMs: 1, progress: progress, percent: percent)
        }
        #expect(DailyCatalog.nineLives.line(unfinished(.missed, percent: 62)) == "Nine Lives 12: Out of lives, 62%")
        #expect(DailyCatalog.nineLives.short(unfinished(.missed, percent: 62)) == "62%")
        #expect(DailyCatalog.nineLives.summary(unfinished(.closed, percent: nil, progress: 0.629)) == "62%")
        #expect(DailyCatalog.sniff.short(unfinished(.missed, percent: 40)) == "40%")
        #expect(DailyCatalog.sniff.ending(unfinished(.missed, percent: 40)) == "X of 6")
        #expect(DailyCatalog.boxFort.summary(unfinished(.gaveUp, percent: 30)) == "30%")
        #expect(DailyCatalog.catNap.ending(unfinished(.closed, percent: 0)) == "Out of time")
        #expect(DailyCatalog.nineLives.ending(r(.solved)) == nil)
        #expect(DailyCatalog.nineLives.spoken(unfinished(.missed, percent: 62)) == "Out of lives, 62%")
        #expect(DailyCatalog.nineLives.spoken(r(.solved)) == "4:07")
        #expect(DailyCatalog.nineLives.rules == "lives" && DailyCatalog.sniff.rules == nil)
    }

    @Test func startReadsHintMsLeniently() throws {
        func start(_ extra: String) throws -> DailyStart {
            let json = """
                {"run":"r","game":"nine-lives","date":"2026-11-23","number":1,"level":1,"startedAt":1,"now":1,
                 "puzzle":{},"state":{},"seq":0,"hints":0,"result":null,"closesAt":2\(extra)}
                """
            return try JSONDecoder().decode(DailyStart.self, from: Data(json.utf8))
        }
        // A server before the field: 30 seconds a hint.
        #expect(try start("").hintMs == 30_000)
        #expect(try start(#","hintMs":0"#).hintMs == 0)
        #expect(try start(#","hintMs":30000"#).hintMs == 30_000)
        #expect(try start(#","hintMs":"soon""#).hintMs == 30_000)
        #expect(try start(#","hintMs":-5"#).hintMs == 0)
    }

    @Test func startAsksForRulesInItsBody() throws {
        // The body the client sends: `{ "rules": "lives" }`, or none.
        let body: [String: String]? = DailyCatalog.nineLives.rules.map { ["rules": $0] }
        let encoder = JSONEncoder()
        #expect(String(data: try encoder.encode(body), encoding: .utf8) == #"{"rules":"lives"}"#)
        #expect(DailyCatalog.boxFort.rules == nil)
    }
}
