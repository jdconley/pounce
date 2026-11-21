import Foundation

/// A letter's mark, as the server worked it out: right spot (a filled paw), elsewhere in the word
/// (an outlined paw), or not in it (plain). Sniff's marks are never computed on a client.
public enum SniffMark: String, Codable, Sendable, Hashable {
    case spot, near, none

    fileprivate var rank: Int {
        switch self {
        case .none: 0
        case .near: 1
        case .spot: 2
        }
    }
}

/// A guess and its marks.
public struct SniffGuess: Codable, Sendable, Equatable, Hashable {
    public let word: String
    public let marks: [SniffMark]

    public init(word: String, marks: [SniffMark]) {
        self.word = word
        self.marks = marks
    }

    public var isSolved: Bool { marks.count == SniffBoard.letters && marks.allSatisfy { $0 == .spot } }
}

/// A guess move's `reveal` on the wire: `{ word, marks, answer? }`, the answer only when that
/// guess ended the run.
public struct SniffReveal: Codable, Sendable, Equatable {
    public let guess: SniffGuess
    public let answer: String?

    public init(guess: SniffGuess, answer: String?) {
        self.guess = guess
        self.answer = answer
    }

    private enum CodingKeys: String, CodingKey { case word, marks, answer }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guess = SniffGuess(word: try c.decode(String.self, forKey: .word), marks: try c.decode([SniffMark].self, forKey: .marks))
        answer = try c.decodeIfPresent(String.self, forKey: .answer)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(guess.word, forKey: .word)
        try c.encode(guess.marks, forKey: .marks)
        try c.encodeIfPresent(answer, forKey: .answer)
    }
}

/// What a press of Enter does.
public enum SniffSubmit: Equatable, Sendable {
    /// Send this guess to the server.
    case send(String)
    /// Fewer than five letters: nothing happens.
    case short
    /// Not a word we know: the row shakes; it isn't counted or sent.
    case unknown
    /// Still waiting on the last guess's marks.
    case busy
    /// The run is over.
    case over
}

/// Sniff's board as one value: the server's guesses and marks, the row being typed, and a guess
/// waiting on the server. The play view and the TV's watch view draw from it.
public struct SniffBoard: Sendable, Equatable {
    public static let letters = 5
    public static let tries = 6

    public private(set) var guesses: [SniffGuess]
    public private(set) var draft = ""
    public private(set) var pending: String?
    public private(set) var answer: String?

    public init(guesses: [SniffGuess] = [], answer: String? = nil) {
        self.guesses = guesses
        self.answer = answer
    }

    public var isSolved: Bool { guesses.contains(where: \.isSolved) }
    public var isOver: Bool { isSolved || guesses.count >= Self.tries }
    private var canType: Bool { !isOver && pending == nil }

    public mutating func type(_ letter: Character) {
        guard canType, draft.count < Self.letters, letter.isASCII, letter.isLetter else { return }
        draft.append(Character(letter.lowercased()))
    }

    public mutating func delete() {
        guard canType, !draft.isEmpty else { return }
        draft.removeLast()
    }

    public mutating func submit(words: SniffWords) -> SniffSubmit {
        if isOver { return .over }
        if pending != nil { return .busy }
        if draft.count < Self.letters { return .short }
        if !words.allows(draft) { return .unknown }
        pending = draft
        return .send(draft)
    }

    /// The server's marks for the pending guess (or any guess, when resuming).
    public mutating func reveal(_ guess: SniffGuess, answer: String?) {
        guesses.append(guess)
        if let answer { self.answer = answer }
        pending = nil
        draft = ""
    }

    /// The server refused the pending guess (too soon, or the connection dropped): try again.
    public mutating func refused() {
        pending = nil
    }

    /// The best mark each letter has had: what the keyboard shows.
    public var keyboard: [Character: SniffMark] {
        var keys: [Character: SniffMark] = [:]
        for guess in guesses {
            for (letter, mark) in zip(guess.word, guess.marks) where mark.rank > (keys[letter]?.rank ?? -1) {
                keys[letter] = mark
            }
        }
        return keys
    }
}
