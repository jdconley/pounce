import Foundation

/// Sniff's public puzzle, the start answer's `puzzle`: only its size, never the answer.
public struct SniffPublic: Codable, Sendable, Equatable {
    public let letters: Int
    public let tries: Int

    public init(letters: Int, tries: Int) {
        self.letters = letters
        self.tries = tries
    }
}

/// Sniff's public state, the start answer's and a resync's `state` and a TV's watch frame:
/// the server's guesses with their marks, and the answer once the run ended (solved or missed).
public struct SniffView: Codable, Sendable, Equatable {
    public let guesses: [SniffGuess]
    public let answer: String?

    public init(guesses: [SniffGuess], answer: String? = nil) {
        self.guesses = guesses
        self.answer = answer
    }

    /// The board to draw from it.
    public var board: SniffBoard { SniffBoard(guesses: guesses, answer: answer) }
}

/// A guess, as the server's `parseMove` takes it: `{ "k": "guess", "word": "plant" }`.
public struct SniffMove: Codable, Sendable, Equatable {
    public var k = "guess"
    public let word: String

    public init(word: String) {
        self.word = word
    }
}
