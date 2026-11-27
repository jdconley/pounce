import Foundation

// The Daily Dish's wire shapes (docs/daily-protocol.md). Samples of every one are in
// apps/play-api/fixtures/daily/protocol/; `DailyWireTests` decodes them all. Everything here is
// additive and decodes leniently: a field the server adds later is ignored, and a message kind
// this app doesn't know is skipped.

/// How a run ended.
public enum DailyOutcome: String, Sendable, Hashable, Codable {
    case solved, missed, gaveUp, closed, done
    /// A kind a newer server sends.
    case other

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = DailyOutcome(rawValue: raw) ?? .other
    }

    /// Solved, or Box Fort's normal ending: a result to be pleased with.
    public var finished: Bool { self == .solved || self == .done }
}

/// A run's result, worked out only by the server.
public struct DailyResult: Sendable, Hashable, Codable {
    public let game: String
    public let date: String
    public let number: Int
    public let outcome: DailyOutcome
    /// The run's active time when it ended (the time the puzzle was on screen), plus the run's
    /// `hintMs` a hint. A run stored before active time: from start to the move that ended it.
    public let timeMs: Int
    public let hints: Int
    public let progress: Double
    /// How far it got by the game's own measure, rounded down: 100 only once finished. A result
    /// stored before 2026-11-26 has none: use `shownPercent`.
    public let percent: Int?
    /// Faster than the game's floor: kept, but off every board.
    public let tooFast: Bool
    /// Sniff only.
    public let guesses: Int?
    /// Box Fort only.
    public let points: Int?

    public init(
        game: String, date: String, number: Int, outcome: DailyOutcome, timeMs: Int, hints: Int = 0, progress: Double,
        percent: Int? = nil, tooFast: Bool = false, guesses: Int? = nil, points: Int? = nil
    ) {
        self.game = game
        self.date = date
        self.number = number
        self.outcome = outcome
        self.timeMs = timeMs
        self.hints = hints
        self.progress = progress
        self.percent = percent
        self.tooFast = tooFast
        self.guesses = guesses
        self.points = points
    }

    private enum Key: String, CodingKey { case game, date, number, outcome, timeMs, hints, progress, percent, tooFast, guesses, points }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        game = try c.decode(String.self, forKey: .game)
        date = try c.decode(String.self, forKey: .date)
        number = try c.decode(Int.self, forKey: .number)
        outcome = try c.decode(DailyOutcome.self, forKey: .outcome)
        timeMs = try c.decode(Int.self, forKey: .timeMs)
        hints = try c.decodeIfPresent(Int.self, forKey: .hints) ?? 0
        progress = try c.decodeIfPresent(Double.self, forKey: .progress) ?? 0
        // Lenient: an odd percent is none, and the progress stands in.
        percent = ((try? c.decodeIfPresent(Int.self, forKey: .percent)) ?? nil).map { min(max($0, 0), 100) }
        tooFast = try c.decodeIfPresent(Bool.self, forKey: .tooFast) ?? false
        guesses = try c.decodeIfPresent(Int.self, forKey: .guesses)
        points = try c.decodeIfPresent(Int.self, forKey: .points)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        try c.encode(game, forKey: .game)
        try c.encode(date, forKey: .date)
        try c.encode(number, forKey: .number)
        try c.encode(outcome.rawValue, forKey: .outcome)
        try c.encode(timeMs, forKey: .timeMs)
        try c.encode(hints, forKey: .hints)
        try c.encode(progress, forKey: .progress)
        try c.encodeIfPresent(percent, forKey: .percent)
        try c.encode(tooFast, forKey: .tooFast)
        try c.encodeIfPresent(guesses, forKey: .guesses)
        try c.encodeIfPresent(points, forKey: .points)
    }

    /// The percent to show: the server's, or for an older result `floor(progress * 100)`.
    public var shownPercent: Int { percent ?? min(100, max(0, Int((progress * 100).rounded(.down)))) }
}

/// `POST /v1/daily/{game}/start`: a new run, or the one already going (another device carries on).
public struct DailyStart: Sendable, Hashable, Codable {
    public let run: String
    public let game: String
    public let date: String
    public let number: Int
    public let level: Int
    /// Epoch milliseconds, the server's clock.
    public let startedAt: Int64
    public let now: Int64
    /// The game's public puzzle. Never a solution, an answer or a future set.
    public let puzzle: DailyJSON
    /// The game's public state: what a resuming client draws.
    public let state: DailyJSON
    /// Moves the server has accepted.
    public let seq: Int
    public let hints: Int
    /// Set once the run has ended: show the end screen.
    public let result: DailyResult?
    public let closesAt: Int64
    /// What one hint adds to the run's time: 30 seconds, or 0 under Nine Lives' `"lives"` rules.
    /// A server before this field always added 30 seconds.
    public let hintMs: Int
    /// The run's active time so far, from the server (`## Active time`): carry on from it. Nil from
    /// a server before active time: count from `startedAt` (`DailyClock.activeMs`).
    public let activeMs: Int64?

    public static let firstHintMs = 30_000

    public init(
        run: String, game: String, date: String, number: Int, level: Int, startedAt: Int64, now: Int64, puzzle: DailyJSON,
        state: DailyJSON, seq: Int, hints: Int, result: DailyResult?, closesAt: Int64, hintMs: Int = DailyStart.firstHintMs,
        activeMs: Int64? = nil
    ) {
        self.run = run
        self.game = game
        self.date = date
        self.number = number
        self.level = level
        self.startedAt = startedAt
        self.now = now
        self.puzzle = puzzle
        self.state = state
        self.seq = seq
        self.hints = hints
        self.result = result
        self.closesAt = closesAt
        self.hintMs = hintMs
        self.activeMs = activeMs
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        run = try c.decode(String.self, forKey: .run)
        game = try c.decode(String.self, forKey: .game)
        date = try c.decode(String.self, forKey: .date)
        number = try c.decode(Int.self, forKey: .number)
        level = try c.decode(Int.self, forKey: .level)
        startedAt = try c.decode(Int64.self, forKey: .startedAt)
        now = try c.decode(Int64.self, forKey: .now)
        puzzle = try c.decode(DailyJSON.self, forKey: .puzzle)
        state = try c.decode(DailyJSON.self, forKey: .state)
        seq = try c.decode(Int.self, forKey: .seq)
        hints = try c.decode(Int.self, forKey: .hints)
        result = try c.decodeIfPresent(DailyResult.self, forKey: .result)
        closesAt = try c.decode(Int64.self, forKey: .closesAt)
        // Lenient: missing, or not a whole number of milliseconds, is the first rules' 30 seconds.
        hintMs = (try? c.decodeIfPresent(Int.self, forKey: .hintMs)).flatMap { $0 }.map { max(0, $0) } ?? Self.firstHintMs
        activeMs = (try? c.decodeIfPresent(Int64.self, forKey: .activeMs)).flatMap { $0 }.map { max(0, $0) }
    }
}

/// Why the server refused a batch, a hint or a give-up.
public enum DailyRefusal: String, Sendable, Hashable, Codable {
    /// A move breaks the rules: undo from it.
    case illegal
    /// A move came closer to the last than the game allows: wait, then resend.
    case tooSoon = "too_soon"
    /// Not one of the game's moves: a client bug.
    case badMessage = "bad_message"
    /// `from` isn't the server's `seq`: start again to resync.
    case stale
    /// The run has ended: start again to see the result.
    case over
    case other

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = DailyRefusal(rawValue: raw) ?? .other
    }
}

/// The answer to moves, a hint or a give-up.
public enum DailyMovesAnswer: Sendable, Hashable, Decodable {
    /// `reveals` holds what the server worked out, in order, for the moves that reveal something.
    case accepted(seq: Int, reveals: [DailyJSON], progress: Double, result: DailyResult?)
    case refused(DailyRefusal, at: Int, seq: Int)

    private enum Key: String, CodingKey { case ok, seq, reveals, progress, result, error, at }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        let seq = try c.decode(Int.self, forKey: .seq)
        if try c.decode(Bool.self, forKey: .ok) {
            self = .accepted(
                seq: seq, reveals: try c.decodeIfPresent([DailyJSON].self, forKey: .reveals) ?? [],
                progress: try c.decodeIfPresent(Double.self, forKey: .progress) ?? 0,
                result: try c.decodeIfPresent(DailyResult.self, forKey: .result))
        } else {
            self = .refused(
                try c.decode(DailyRefusal.self, forKey: .error), at: try c.decodeIfPresent(Int.self, forKey: .at) ?? 0, seq: seq)
        }
    }
}

/// `{ from, moves, activeMs }`, the moves route's body.
public struct DailyMovesBody: Sendable, Hashable, Codable {
    public let from: Int
    public let moves: [DailyJSON]
    /// The run's active time when the batch went (`## Active time`).
    public let activeMs: Int64?

    public init(from: Int, moves: [DailyJSON], activeMs: Int64? = nil) {
        self.from = from
        self.moves = moves
        self.activeMs = activeMs
    }
}

/// `{ hints, activeMs }`, the hint route's body.
public struct DailyHintBody: Sendable, Hashable, Codable {
    public let hints: Int
    public let activeMs: Int64?

    public init(hints: Int, activeMs: Int64? = nil) {
        self.hints = hints
        self.activeMs = activeMs
    }
}

/// `{ activeMs }`, the give-up route's body.
public struct DailyGiveUpBody: Sendable, Hashable, Codable {
    public let activeMs: Int64?

    public init(activeMs: Int64? = nil) { self.activeMs = activeMs }
}

// MARK: the board

/// Someone playing now, with spoiler-free progress (0 to 1).
public struct DailyPlaying: Sendable, Hashable, Codable {
    public let progress: Double

    public init(progress: Double) { self.progress = progress }
}

/// One person on one game's board: a result, or playing now.
public struct DailyBoardRow: Sendable, Hashable, Codable, Identifiable {
    /// `"me"` for the board's owner, a pair id for a connection. Never a player id.
    public let player: String
    public let name: String
    public let cat: Int
    /// A competition rank (ties share it); nil while playing.
    public let rank: Int?
    public let result: DailyResult?
    public let playing: DailyPlaying?

    public var id: String { player }
    public var isMe: Bool { player == DailyBoard.me }

    public init(player: String, name: String, cat: Int, rank: Int?, result: DailyResult?, playing: DailyPlaying?) {
        self.player = player
        self.name = name
        self.cat = cat
        self.rank = rank
        self.result = result
        self.playing = playing
    }
}

/// One game's board for a date.
public struct DailyGameBoard: Sendable, Hashable, Codable, Identifiable {
    public let game: String
    public let number: Int
    public let rows: [DailyBoardRow]

    public var id: String { game }

    public init(game: String, number: Int, rows: [DailyBoardRow]) {
        self.game = game
        self.number = number
        self.rows = rows
    }
}

/// One person on the Dish: points over every game, and a crown for each game won.
public struct DailyDishRow: Sendable, Hashable, Codable, Identifiable {
    public let player: String
    public let name: String
    public let cat: Int
    public let rank: Int
    public let points: Int
    public let crowns: [String]
    public let ended: Int

    public var id: String { player }
    public var isMe: Bool { player == DailyBoard.me }

    public init(player: String, name: String, cat: Int, rank: Int, points: Int, crowns: [String], ended: Int) {
        self.player = player
        self.name = name
        self.cat = cat
        self.rank = rank
        self.points = points
        self.crowns = crowns
        self.ended = ended
    }
}

public struct DailyDish: Sendable, Hashable, Codable {
    public let rows: [DailyDishRow]

    public init(rows: [DailyDishRow]) { self.rows = rows }

    /// The rows the Dish shows: never someone at 0 points (a run closed at 04:00 in fourth place or
    /// lower earns nothing), so nobody reads as last. Ranks are the server's, ties shared.
    public var shown: [DailyDishRow] { rows.filter { $0.points > 0 } }
}

/// `GET /v1/daily/board`, and the socket's snapshot.
public struct DailyBoard: Sendable, Hashable, Codable {
    /// The `player` of the board's owner.
    public static let me = "me"

    public let date: String
    /// In the Dish's order: Sniff, Nine Lives, Cat Nap, Box Fort.
    public let games: [DailyGameBoard]
    public let dish: DailyDish
    /// TV board sockets open now that show a board this person is on. Show on TV only while above 0.
    public let tvs: Int

    private enum Key: String, CodingKey { case date, games, dish, tvs }

    public init(date: String, games: [DailyGameBoard], dish: DailyDish, tvs: Int = 0) {
        self.date = date
        self.games = games
        self.dish = dish
        self.tvs = tvs
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        date = try c.decode(String.self, forKey: .date)
        games = try c.decode([DailyGameBoard].self, forKey: .games)
        dish = try c.decode(DailyDish.self, forKey: .dish)
        tvs = try c.decodeIfPresent(Int.self, forKey: .tvs) ?? 0
    }

    public func game(_ id: String) -> DailyGameBoard? { games.first { $0.game == id } }

    /// My row on a game's board, if I played or am playing.
    public func mine(_ game: String) -> DailyBoardRow? { self.game(game)?.rows.first(where: \.isMe) }

    /// The best result on a game's board (rank 1), if anyone has finished.
    public func best(_ game: String) -> DailyBoardRow? { self.game(game)?.rows.first { $0.rank == 1 && $0.result != nil } }

    /// This board with one result in place: the socket's `result` arrives before its fresh snapshot.
    public func adding(_ result: DailyResult, for player: String) -> DailyBoard {
        guard result.date == date else { return self }
        let games = games.map { board -> DailyGameBoard in
            guard board.game == result.game else { return board }
            var rows = board.rows
            if let i = rows.firstIndex(where: { $0.player == player }) {
                let row = rows[i]
                rows[i] = DailyBoardRow(player: row.player, name: row.name, cat: row.cat, rank: row.rank, result: result, playing: nil)
            }
            return DailyGameBoard(game: board.game, number: board.number, rows: rows)
        }
        return DailyBoard(date: date, games: games, dish: dish, tvs: tvs)
    }

    /// This board with someone's progress moved.
    public func moving(_ player: String, game: String, progress: Double) -> DailyBoard {
        let games = games.map { board -> DailyGameBoard in
            guard board.game == game else { return board }
            let rows = board.rows.map { row -> DailyBoardRow in
                guard row.player == player, row.result == nil else { return row }
                return DailyBoardRow(
                    player: row.player, name: row.name, cat: row.cat, rank: nil, result: nil, playing: DailyPlaying(progress: progress))
            }
            return DailyGameBoard(game: board.game, number: board.number, rows: rows)
        }
        return DailyBoard(date: date, games: games, dish: dish, tvs: tvs)
    }

    public func with(tvs: Int) -> DailyBoard { DailyBoard(date: date, games: games, dish: dish, tvs: tvs) }
}

// MARK: stats

public struct DailyDay: Sendable, Hashable, Codable {
    public let date: String
    public let result: DailyResult

    public init(date: String, result: DailyResult) {
        self.date = date
        self.result = result
    }
}

/// One game's lifetime stats for this person.
public struct DailyStats: Sendable, Hashable, Codable {
    public let played: Int
    public let solved: Int
    /// Consecutive days with an ended run in this game; 0 once a day is missed.
    public let streak: Int
    public let best: Int
    public let bestTimeMs: Int?
    public let bestPoints: Int?
    /// Sniff: solves in 1 to 6 guesses.
    public let guesses: [Int]
    /// Days with a result in the last 30, oldest first.
    public let last30: [DailyDay]
    public let lastEnded: String?

    public init(
        played: Int, solved: Int, streak: Int, best: Int, bestTimeMs: Int?, bestPoints: Int?, guesses: [Int], last30: [DailyDay],
        lastEnded: String?
    ) {
        self.played = played
        self.solved = solved
        self.streak = streak
        self.best = best
        self.bestTimeMs = bestTimeMs
        self.bestPoints = bestPoints
        self.guesses = guesses
        self.last30 = last30
        self.lastEnded = lastEnded
    }

    public static let empty = DailyStats(
        played: 0, solved: 0, streak: 0, best: 0, bestTimeMs: nil, bestPoints: nil, guesses: Array(repeating: 0, count: 6),
        last30: [], lastEnded: nil)

    /// Solved out of played, 0 to 1.
    public var solveRate: Double { played == 0 ? 0 : Double(solved) / Double(played) }
}

/// `GET /v1/daily/stats`.
public struct DailyStatsList: Sendable, Hashable, Codable {
    public let games: [String: DailyStats]

    public init(games: [String: DailyStats]) { self.games = games }
}

// MARK: the board socket

/// What the board socket says. Kinds this app doesn't know decode as `.unknown` and are skipped.
public enum DailyBoardMessage: Sendable, Hashable, Decodable {
    case board(DailyBoard)
    case result(player: String, result: DailyResult)
    case progress(player: String, game: String, progress: Double)
    case watchOffer(player: String, name: String, cat: Int, game: String)
    /// A frame: the run's public puzzle (as start gives it) and public state, enough to draw it.
    case watch(player: String, game: String, puzzle: DailyJSON, state: DailyJSON)
    /// `result` nil: Show on TV was turned off.
    case watchEnd(player: String, game: String, result: DailyResult?)
    case tvs(Int)
    case pong
    case error(String)
    case unknown(String)

    private enum Key: String, CodingKey { case t, board, player, result, game, progress, name, cat, puzzle, state, count, error }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        let t = try c.decode(String.self, forKey: .t)
        switch t {
        case "board" where c.contains(.board): self = .board(try c.decode(DailyBoard.self, forKey: .board))
        case "result":
            self = .result(player: try c.decode(String.self, forKey: .player), result: try c.decode(DailyResult.self, forKey: .result))
        case "progress":
            self = .progress(
                player: try c.decode(String.self, forKey: .player), game: try c.decode(String.self, forKey: .game),
                progress: try c.decode(Double.self, forKey: .progress))
        case "watchOffer":
            self = .watchOffer(
                player: try c.decode(String.self, forKey: .player), name: try c.decode(String.self, forKey: .name),
                cat: try c.decode(Int.self, forKey: .cat), game: try c.decode(String.self, forKey: .game))
        case "watch":
            self = .watch(
                player: try c.decode(String.self, forKey: .player), game: try c.decode(String.self, forKey: .game),
                puzzle: try c.decodeIfPresent(DailyJSON.self, forKey: .puzzle) ?? .null, state: try c.decode(DailyJSON.self, forKey: .state))
        case "watchEnd":
            self = .watchEnd(
                player: try c.decode(String.self, forKey: .player), game: try c.decode(String.self, forKey: .game),
                result: try c.decodeIfPresent(DailyResult.self, forKey: .result))
        case "tvs": self = .tvs(try c.decode(Int.self, forKey: .count))
        case "pong": self = .pong
        case "error": self = .error(try c.decodeIfPresent(String.self, forKey: .error) ?? "")
        default: self = .unknown(t)
        }
    }

    /// One frame of text, or nil when it isn't JSON with a `t`.
    public static func decode(_ text: String) -> DailyBoardMessage? {
        try? JSONDecoder().decode(DailyBoardMessage.self, from: Data(text.utf8))
    }
}
