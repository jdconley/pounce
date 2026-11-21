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

    // MARK: The wire and the demo

    @Test func aRevealDecodesFromTheServersJSON() throws {
        let runs = try #require(try Self.json("runs.json")["runs"] as? [[String: Any]])
        let first = try #require(runs.first?["answers"] as? [[String: Any]])
        let data = try JSONSerialization.data(withJSONObject: try #require(first.last?["reveal"]))
        let reveal = try JSONDecoder().decode(SniffReveal.self, from: data)
        #expect(reveal.guess.word == "plant")
        #expect(reveal.guess.marks == Array(repeating: .spot, count: 5))
        #expect(reveal.answer == "plant")
    }

    @Test func theDemoRevealsAreTheServersRepeatedLetterRun() throws {
        let runs = try #require(try Self.json("runs.json")["runs"] as? [[String: Any]])
        let run = runs[1]
        #expect(SniffDemo.answer == run["answer"] as? String)
        let answers = try #require(run["answers"] as? [[String: Any]]).filter { $0["reveal"] != nil }
        #expect(SniffDemo.script.count == answers.count)
        for answer in answers {
            let data = try JSONSerialization.data(withJSONObject: try #require(answer["reveal"]))
            let reveal = try JSONDecoder().decode(SniffReveal.self, from: data)
            #expect(SniffDemo.reveal(reveal.guess.word) == reveal)
        }
    }
}

extension SniffTests {
    @Test func theDemoMarksAnyOtherWordPlain() {
        #expect(SniffDemo.reveal("crane") == SniffReveal(guess: SniffGuess(word: "crane", marks: Array(repeating: .none, count: 5)), answer: nil))
    }
}
