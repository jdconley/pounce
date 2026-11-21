import Foundation
import Testing
@testable import PounceKit

/// Sniff's client side: the allowed-guess check, the board as typed, and the keyboard's marks.
/// Marks themselves come only from the server; these tests read its fixtures by path.
@Suite struct SniffTests {
    /// `apps/` from this file: Daily -> PounceKitTests -> Tests -> PounceKit -> play-ios -> apps.
    static func apps(_ relative: String) -> URL {
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { dir.deleteLastPathComponent() }
        return dir.appendingPathComponent(relative)
    }

    static let allowedURL = apps("play-api/src/daily/sniff/words/allowed.txt")
    static let words = SniffWords(data: try! Data(contentsOf: allowedURL))!

    static func json(_ relative: String) throws -> [String: Any] {
        let data = try Data(contentsOf: apps("play-api/fixtures/daily/sniff/\(relative)"))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    static func guess(_ word: String, _ marks: [String]) -> SniffGuess {
        SniffGuess(word: word, marks: marks.map { SniffMark(rawValue: $0)! })
    }

    // MARK: The allowed list

    @Test func everyAllowedWordPasses() throws {
        let list = try String(contentsOf: Self.allowedURL, encoding: .utf8).split(separator: "\n")
        #expect(list.count > 9000)
        for word in list { #expect(Self.words.allows(String(word)), "\(word)") }
    }

    @Test func theAppsCopyIsTheServers() throws {
        let app = Self.apps("play-ios/Pounce/Daily/Sniff/sniff-allowed.txt")
        #expect(try Data(contentsOf: app) == Data(contentsOf: Self.allowedURL))
    }

    @Test func nonWordsCapsAndWrongLengthsFail() {
        for word in ["zzzzz", "aaaaa", "PLANT", "Plant", "plan", "plants", "pl@nt", "", "plänt"] {
            #expect(!Self.words.allows(word), "\(word)")
        }
        #expect(Self.words.allows("plant"))
        #expect(Self.words.allows("sniff"))
    }

    @Test func aListThatIsntWholeWordsIsRefused() {
        #expect(SniffWords(data: Data("plant\nsnif".utf8)) == nil)
        #expect(SniffWords(data: Data()) == nil)
        #expect(SniffWords(data: Data("plant\n".utf8))?.allows("plant") == true)
    }

    // MARK: The board

    @Test func typingStopsAtFiveAndDeleteStopsAtNothing() {
        var board = SniffBoard()
        for letter in "PLANTS" { board.type(letter) }
        #expect(board.draft == "plant")
        board.type("1")
        #expect(board.draft == "plant")
        for _ in 0..<7 { board.delete() }
        #expect(board.draft == "")
    }

    @Test func submitIsShortThenUnknownThenSent() {
        var board = SniffBoard()
        for letter in "pla" { board.type(letter) }
        #expect(board.submit(words: Self.words) == .short)
        for letter in "zz" { board.type(letter) }
        #expect(board.submit(words: Self.words) == .unknown)
        #expect(board.guesses.isEmpty)
        board.delete(); board.delete()
        for letter in "nt" { board.type(letter) }
        #expect(board.submit(words: Self.words) == .send("plant"))
        #expect(board.pending == "plant")
        // Waiting on the server: no typing, no second send.
        board.delete()
        board.type("x")
        #expect(board.draft == "plant")
        #expect(board.submit(words: Self.words) == .busy)
    }

    @Test func aRevealAddsTheGuessAndClearsTheDraft() {
        var board = SniffBoard()
        for letter in "crane" { board.type(letter) }
        _ = board.submit(words: Self.words)
        board.reveal(Self.guess("crane", ["none", "none", "spot", "spot", "none"]), answer: nil)
        #expect(board.guesses.count == 1)
        #expect(board.draft == "")
        #expect(board.pending == nil)
        #expect(!board.isOver)
    }

    @Test func aRefusedSendKeepsTheDraftToTryAgain() {
        var board = SniffBoard()
        for letter in "crane" { board.type(letter) }
        _ = board.submit(words: Self.words)
        board.refused()
        #expect(board.pending == nil)
        #expect(board.draft == "crane")
        #expect(board.guesses.isEmpty)
    }

    @Test func solvedOrSixGuessesIsOver() {
        var solved = SniffBoard()
        solved.reveal(Self.guess("plant", Array(repeating: "spot", count: 5)), answer: "plant")
        #expect(solved.isOver)
        #expect(solved.isSolved)
        #expect(solved.answer == "plant")
        solved.type("a")
        #expect(solved.draft == "")
        #expect(solved.submit(words: Self.words) == .over)

        let none = Array(repeating: "none", count: 5)
        var missed = SniffBoard(guesses: (0..<6).map { _ in Self.guess("dummy", none) }, answer: "plant")
        #expect(missed.isOver)
        #expect(!missed.isSolved)
        #expect(missed.submit(words: Self.words) == .over)
    }

    // MARK: The keyboard

    @Test func theKeyboardKeepsTheBestMarkEachLetterHad() {
        let board = SniffBoard(guesses: [
            Self.guess("crate", ["none", "none", "near", "none", "near"]),
            Self.guess("plant", ["none", "none", "spot", "none", "none"]),
            Self.guess("slate", ["none", "none", "none", "none", "spot"]),
        ])
        #expect(board.keyboard["a"] == .spot)
        #expect(board.keyboard["e"] == .spot)
        #expect(board.keyboard["c"] == SniffMark.none)
        #expect(board.keyboard["t"] == SniffMark.none)
        #expect(board.keyboard["z"] == nil)
    }

    @Test func theKeyboardFollowsEveryServerVector() throws {
        let vectors = try #require(try Self.json("marks.json")["vectors"] as? [[String: Any]])
        #expect(vectors.count >= 12)
        for v in vectors {
            let word = try #require(v["guess"] as? String)
            let marks = try #require(v["marks"] as? [String])
            let board = SniffBoard(guesses: [Self.guess(word, marks)])
            for letter in Set(word) {
                let best = zip(word, marks).filter { $0.0 == letter }.map(\.1)
                let expected: SniffMark = best.contains("spot") ? .spot : best.contains("near") ? .near : .none
                #expect(board.keyboard[letter] == expected, "\(word) \(letter)")
            }
        }
    }

    // MARK: The wire

    @Test func aRevealDecodesFromTheServersJSON() throws {
        let runs = try #require(try Self.json("runs.json")["runs"] as? [[String: Any]])
        let first = try #require(runs.first?["answers"] as? [[String: Any]])
        let data = try JSONSerialization.data(withJSONObject: try #require(first.last?["reveal"]))
        let reveal = try JSONDecoder().decode(SniffReveal.self, from: data)
        #expect(reveal.guess.word == "plant")
        #expect(reveal.guess.marks == Array(repeating: .spot, count: 5))
        #expect(reveal.answer == "plant")
    }

}


// MARK: The Dish's wire

extension SniffTests {
    @Test func theServersPublicStateDecodesBeforeAndAfterTheEnd() throws {
        let runs = try #require(try Self.json("runs.json")["runs"] as? [[String: Any]])
        let answers = try #require(runs[0]["answers"] as? [[String: Any]])
        let decode = { (any: Any) throws -> SniffView in
            try JSONDecoder().decode(SniffView.self, from: JSONSerialization.data(withJSONObject: any))
        }
        let first = try decode(try #require(answers[0]["view"]))
        #expect(first.guesses.map(\.word) == ["crane"])
        #expect(first.answer == nil)
        let last = try decode(try #require(answers[2]["view"]))
        #expect(last.answer == "plant")
        #expect(last.board == SniffBoard(guesses: last.guesses, answer: "plant"))
        #expect(last.board.isSolved)
    }

    @Test func thePublicPuzzleDecodes() throws {
        let puzzle = try JSONDecoder().decode(SniffPublic.self, from: Data(#"{"letters":5,"tries":6}"#.utf8))
        #expect(puzzle == SniffPublic(letters: 5, tries: 6))
    }

    @Test func aGuessEncodesAsTheServerParsesIt() throws {
        let data = try JSONEncoder().encode(SniffMove(word: "plant"))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: String])
        #expect(object == ["k": "guess", "word": "plant"])
    }
}

// MARK: A run through the Dish's session

extension SniffTests {
    /// The server's first recorded run (`runs.json`), answered by H1's in-memory server.
    @Test func aRunPlaysThroughTheSessionWithTheServersReveals() async throws {
        let runs = try #require(try Self.json("runs.json")["runs"] as? [[String: Any]])
        let answers = try #require(runs[0]["answers"] as? [[String: Any]])
        let reveals = try answers.map { a in
            try JSONDecoder().decode(DailyJSON.self, from: JSONSerialization.data(withJSONObject: try #require(a["reveal"])))
        }
        let start = DailyStart(
            run: "run1", game: "sniff", date: "2026-11-23", number: 1, level: 1, startedAt: 1_000_000, now: 1_000_000,
            puzzle: .object(["letters": .int(5), "tries": .int(6)]), state: .object(["guesses": .array([])]), seq: 0, hints: 0,
            result: nil, closesAt: 2_000_000)
        let fake = FakeDaily(start: start)
        await fake.script(reveals.enumerated().map { i, r in .success(.accepted(seq: i + 1, reveals: [r], progress: Double(i + 1) / 6, result: nil)) })
        let session = DailyRunSession(start: start, service: fake, person: "p1", window: .milliseconds(80), retry: .milliseconds(10))

        let (puzzle, state) = try await session.decodeStart(puzzle: SniffPublic.self, state: SniffView.self)
        #expect(puzzle == SniffPublic(letters: 5, tries: 6))
        var board = state.board
        for word in ["crane", "slant", "plant"] {
            guard case .accepted(let got) = await session.play(SniffMove(word: word), revealing: SniffReveal.self), let reveal = got.last else {
                Issue.record("\(word) refused")
                return
            }
            #expect(reveal.guess.word == word)
            board.reveal(reveal.guess, answer: reveal.answer)
        }
        #expect(board.isSolved)
        #expect(board.answer == "plant")
        let sent = await fake.bodies.flatMap(\.moves)
        #expect(sent == [try DailyJSON(SniffMove(word: "crane")), try DailyJSON(SniffMove(word: "slant")), try DailyJSON(SniffMove(word: "plant"))])
    }

    @Test func anIllegalGuessComesBackRefused() async throws {
        let start = DailyStart(
            run: "run1", game: "sniff", date: "2026-11-23", number: 1, level: 1, startedAt: 1_000_000, now: 1_000_000,
            puzzle: .object(["letters": .int(5), "tries": .int(6)]), state: .object(["guesses": .array([])]), seq: 0, hints: 0,
            result: nil, closesAt: 2_000_000)
        let fake = FakeDaily(start: start)
        await fake.script([.success(.refused(.illegal, at: 0, seq: 0))])
        let session = DailyRunSession(start: start, service: fake, person: "p1", window: .milliseconds(80), retry: .milliseconds(10))
        guard case .refused = await session.play(SniffMove(word: "crane"), revealing: SniffReveal.self) else {
            Issue.record("expected refused")
            return
        }
    }
}
