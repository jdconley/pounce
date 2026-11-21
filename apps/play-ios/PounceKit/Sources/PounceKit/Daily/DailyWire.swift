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
    /// From start to the move that ended it, plus 30 seconds a hint.
    public let timeMs: Int
    public let hints: Int
    public let progress: Double
    /// Faster than the game's floor: kept, but off every board.
    public let tooFast: Bool
    /// Sniff only.
    public let guesses: Int?
    /// Box Fort only.
    public let points: Int?

    public init(
        game: String, date: String, number: Int, outcome: DailyOutcome, timeMs: Int, hints: Int = 0, progress: Double,
        tooFast: Bool = false, guesses: Int? = nil, points: Int? = nil
    ) {
        self.game = game
        self.date = date
        self.number = number
        self.outcome = outcome
        self.timeMs = timeMs
        self.hints = hints
        self.progress = progress
        self.tooFast = tooFast
        self.guesses = guesses
        self.points = points
    }
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

    public init(
        run: String, game: String, date: String, number: Int, level: Int, startedAt: Int64, now: Int64, puzzle: DailyJSON,
        state: DailyJSON, seq: Int, hints: Int, result: DailyResult?, closesAt: Int64
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

/// `{ from, moves }`, the moves route's body.
public struct DailyMovesBody: Sendable, Hashable, Codable {
    public let from: Int
    public let moves: [DailyJSON]

    public init(from: Int, moves: [DailyJSON]) {
        self.from = from
        self.moves = moves
    }
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
    case watch(player: String, game: String, state: DailyJSON)
    /// `result` nil: Show on TV was turned off.
    case watchEnd(player: String, game: String, result: DailyResult?)
    case tvs(Int)
    case pong
    case error(String)
    case unknown(String)

    private enum Key: String, CodingKey { case t, board, player, result, game, progress, name, cat, state, count, error }

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
                state: try c.decode(DailyJSON.self, forKey: .state))
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
