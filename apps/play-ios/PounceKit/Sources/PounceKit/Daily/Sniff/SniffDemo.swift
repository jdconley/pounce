import Foundation

/// The DEBUG demo's stand-in for the server (`-demo sniff`, screenshots and phase-A UI tests): the
/// server's own reveals for one run, copied from `apps/play-api/fixtures/daily/sniff/runs.json`
/// (the repeated-letter run; `SniffTests` checks they match). Any other word comes back plain.
/// Marks are never worked out on a client.
public enum SniffDemo {
    public static let answer = "kitty"

    /// The run's guesses, in order, as the server revealed them.
    public static let script: [SniffReveal] = [
        reveal("tatty", "none none spot spot spot"),
        reveal("otter", "none near spot none none"),
        reveal("witty", "none spot spot spot spot"),
        reveal("bitty", "none spot spot spot spot"),
        reveal("ditty", "none spot spot spot spot"),
        SniffReveal(guess: guess("kitty", "spot spot spot spot spot"), answer: answer),
    ]

    public static func reveal(_ word: String) -> SniffReveal {
        script.first { $0.guess.word == word }
            ?? SniffReveal(guess: SniffGuess(word: word, marks: Array(repeating: .none, count: SniffBoard.letters)), answer: nil)
    }

    private static func guess(_ word: String, _ marks: String) -> SniffGuess {
        SniffGuess(word: word, marks: marks.split(separator: " ").compactMap { SniffMark(rawValue: String($0)) })
    }

    private static func reveal(_ word: String, _ marks: String) -> SniffReveal {
        SniffReveal(guess: guess(word, marks), answer: nil)
    }
}
