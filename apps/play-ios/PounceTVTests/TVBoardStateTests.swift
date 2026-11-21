import Foundation
import PounceKit
import Testing
@testable import PounceTV

/// The board socket's messages, as the server makes them (`apps/play-api/fixtures/daily/protocol/socket.json`).
enum BoardFixtures {
    static let url: URL = {
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { dir.deleteLastPathComponent() }  // PounceTVTests -> play-ios -> apps
        return dir.appendingPathComponent("play-api/fixtures/daily/protocol/socket.json")
    }()

    /// Each message's JSON text, by its name in the file.
    static let texts: [String: String] = {
        guard let data = try? Data(contentsOf: url),
              let all = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return all.compactMapValues { value in
            (try? JSONSerialization.data(withJSONObject: value)).flatMap { String(data: $0, encoding: .utf8) }
        }
    }()

    static func message(_ name: String) -> BoardWire.Message {
        guard let text = texts[name], let m = BoardWire.Message.decode(text) else {
            Issue.record("no fixture \(name)")
            return .other
        }
        return m
    }
}

@Suite("Tonight's board, as the TV works it out")
struct TVBoardStateTests {
    let kid = "pr_8tGqLm2vXc9RzK1wYb4NdA"
    let grandpa = "pr_Hn5sW2qLp7Xy3Zc8Vb1MkA"
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func run(_ names: [String], at now: Date? = nil, from start: TVBoardState = TVBoardState()) -> TVBoardState {
        var s = start
        for name in names { s.apply(BoardFixtures.message(name), now: now ?? t0) }
        return s
    }

    private func result(_ outcome: BoardWire.Result.Outcome, game: String = "test", timeMs: Int = 125_000, guesses: Int? = nil, points: Int? = nil) -> BoardWire.Result {
        BoardWire.Result(game: game, date: "2026-11-23", number: 12, outcome: outcome, timeMs: timeMs, hints: 0, progress: 1, tooFast: false, guesses: guesses, points: points)
    }

    @Test func everyFixtureDecodes() {
        for name in ["board", "result", "progress", "watchOffer", "watch", "watchEnd"] {
            #expect(BoardFixtures.message(name) != .other, "\(name)")
        }
        #expect(BoardWire.Message.decode(#"{"t":"tvs","count":2}"#) == .other)
        #expect(BoardWire.Message.decode(#"{"t":"later"}"#) == .other)
        #expect(BoardWire.Message.decode("nope") == nil)
    }

    @Test func aSnapshotIsTheBoardShown() {
        let s = run(["board"])
        #expect(s.board?.games.first?.game == "test")
        #expect(s.board?.dish.rows.first?.name == "Mom")
    }

    @Test func aResultCheersThatRowThenTheCheerEnds() {
        var s = run(["board", "result", "board"])
        #expect(s.cheer == .init(player: kid, game: "test", solved: true, until: t0 + 2.4))
        s.tick(now: t0 + 2.41)
        #expect(s.cheer == nil)
    }

    @Test func progressMovesAPlayingRowAndAddsNobody() {
        var s = run(["board"])
        s.apply(.progress(player: grandpa, game: "test", progress: 0.75), now: t0)
        s.apply(.progress(player: "pr_nobody", game: "test", progress: 0.5), now: t0)
        let rows = s.board?.games.first?.rows ?? []
        #expect(rows.first { $0.player == grandpa }?.playing == .init(progress: 0.75))
        #expect(rows.count == 3)
    }

    @Test func anOfferIsUpForTwentySecondsAndANewerOneReplacesIt() {
        var s = run(["board", "watchOffer"])
        #expect(s.offer == .init(player: kid, name: "Kid", cat: 5, game: "test", until: t0 + 20))
        s.apply(.watchOffer(player: grandpa, name: "Grandpa", cat: 1, game: "test"), now: t0 + 8)
        #expect(s.offer?.player == grandpa)
        s.tick(now: t0 + 28)
        #expect(s.offer != nil)
        s.tick(now: t0 + 28.01)
        #expect(s.offer == nil)
    }

    @Test func framesAreKeptAfterNotNowAndWatchDrawsTheLatest() {
        var s = run(["watchOffer", "watch"])
        s.notNow()
        #expect(s.offer == nil)
        #expect(s.frames[kid] == .init(game: "test", puzzle: .object(["target": .number(4)]), state: .object(["n": .number(2)])))
        s = run(["watchOffer", "watch"])
        s.watch()
        #expect(s.watching == .init(player: kid, name: "Kid", cat: 5, game: "test"))
    }

    @Test func theWatchedRunsEndShowsItsResultOverItsLastFrameThenTheBoard() {
        var s = run(["watchOffer", "watch"])
        s.watch()
        s.apply(BoardFixtures.message("watchEnd"), now: t0 + 1)
        #expect(s.ended?.name == "Kid")
        #expect(s.frames[kid] != nil)
        s.tick(now: t0 + 7.01)
        #expect(s.watching == nil)
        #expect(s.ended == nil)
        #expect(s.frames[kid] == nil)
    }

    @Test func showOnTVTurnedOffGoesBackToTheBoardAtOnce() {
        var s = run(["watchOffer"])
        s.watch()
        s.apply(.watchEnd(player: kid, game: "test", result: nil), now: t0)
        #expect(s.watching == nil)
        #expect(s.ended == nil)
    }

    @Test func anEndForSomeoneNotWatchedClearsTheirOfferAndFrames() {
        var s = run(["watchOffer", "watch"])
        s.apply(.watchEnd(player: kid, game: "test", result: nil), now: t0)
        #expect(s.offer == nil)
        #expect(s.frames[kid] == nil)
    }

    @Test func theWords() {
        #expect(TVBoardState.offerWords(name: "Mom", game: "sniff") == "Mom is playing Sniff. Spoilers.")
        #expect(TVBoardState.resultWords(result(.solved)) == "2:05")
        #expect(TVBoardState.resultWords(result(.solved, timeMs: 3_725_000)) == "1:02:05")
        #expect(TVBoardState.resultWords(result(.solved, game: "sniff", guesses: 4)) == "4 of 6")
        #expect(TVBoardState.resultWords(result(.missed, game: "sniff", guesses: 6)) == "Missed")
        #expect(TVBoardState.resultWords(result(.done, game: "box-fort", points: 1240)) == "1,240")
        #expect(TVBoardState.resultWords(result(.gaveUp)) == "Gave up")
        #expect(TVBoardState.resultWords(result(.closed)) == "Closed")
    }

    @Test func aLongBoardShowsFourAndCountsTheRest() throws {
        let game = try #require(run(["board"]).board?.games.first)
        let row = try #require(game.rows.first)
        let nine = BoardWire.Game(game: "test", number: 1, rows: (0..<9).map { i in
            BoardWire.Row(player: "p\(i)", name: row.name, cat: row.cat, rank: i + 1, result: row.result, playing: nil)
        })
        let shown = TVBoardState.visibleRows(nine)
        #expect(shown.rows.map(\.player) == ["p0", "p1", "p2", "p3"])
        #expect(shown.more == 5)
    }
}
