import Foundation
import PounceKit

/// What Tonight's board shows (daily games design §6, §8), worked out from the board socket's
/// messages: pure, so it's tested without a screen. The web TV's `tv-board-model.ts` is the same,
/// rule for rule.
struct TVBoardState: Equatable, Sendable {
    /// How long the watch card stays up.
    static let offerTime: TimeInterval = 20
    /// How long a watched run's result shows before the board comes back.
    static let endedTime: TimeInterval = 6
    /// How long a row cheers when its result lands.
    static let cheerTime: TimeInterval = 2.4
    /// Rows a game's card shows before "+N more": a whole family, at a row height that fits.
    static let rowsShown = 6

    struct Offer: Equatable, Sendable {
        let player: String
        let name: String
        let cat: Int
        let game: String
        let until: Date
    }

    struct Cheer: Equatable, Sendable {
        let player: String
        let game: String
        let solved: Bool
        let until: Date
    }

    struct Watching: Equatable, Sendable {
        let player: String
        let name: String
        let cat: Int
        let game: String
    }

    struct Ended: Equatable, Sendable {
        let result: DailyResult
        let name: String
        let until: Date
    }

    /// A watched run as the server last sent it: the game's public puzzle and public state.
    struct Frame: Equatable, Sendable {
        let game: String
        let puzzle: DailyJSON
        let state: DailyJSON
    }

    var board: DailyBoard?
    var offer: Offer?
    /// The latest frame of each run offered to this TV, by player, kept from the offer on.
    var frames: [String: Frame] = [:]
    var watching: Watching?
    var ended: Ended?
    var cheer: Cheer?

    // MARK: the socket

    mutating func apply(_ message: DailyBoardMessage, now: Date) {
        switch message {
        case .board(let board):
            self.board = board
        case .result(let player, let result):
            cheer = Cheer(player: player, game: result.game, solved: result.finished, until: now + Self.cheerTime)
        case .progress(let player, let game, let progress):
            guard let board else { return }
            var moved = false
            let games = board.games.map { g -> DailyGameBoard in
                guard g.game == game else { return g }
                return DailyGameBoard(game: g.game, number: g.number, rows: g.rows.map { r in
                    guard r.player == player, r.playing != nil else { return r }
                    moved = true
                    return DailyBoardRow(player: r.player, name: r.name, cat: r.cat, rank: r.rank, result: r.result, playing: DailyPlaying(progress: progress))
                })
            }
            if moved { self.board = DailyBoard(date: board.date, games: games, dish: board.dish, tvs: board.tvs) }
        case .watchOffer(let player, let name, let cat, let game):
            offer = Offer(player: player, name: name, cat: cat, game: game, until: now + Self.offerTime)
        case .watch(let player, let game, let puzzle, let state):
            frames[player] = Frame(game: game, puzzle: puzzle, state: state)
        case .watchEnd(let player, _, let result):
            if offer?.player == player { offer = nil }
            guard watching?.player == player else {
                frames[player] = nil
                return
            }
            if let result, let watching {
                // The run's last frame stays under its result until the board comes back.
                ended = Ended(result: result, name: watching.name, until: now + Self.endedTime)
            } else {
                frames[player] = nil
                watching = nil
                ended = nil
            }
        case .tvs, .pong, .error, .unknown:
            break
        }
    }

    // MARK: presses and time

    /// Watch, on the card: the offered run, from its latest frame.
    mutating func watch() {
        guard let offer else { return }
        watching = Watching(player: offer.player, name: offer.name, cat: offer.cat, game: offer.game)
        ended = nil
        self.offer = nil
    }

    /// Not now, on the card. The frames stay.
    mutating func notNow() {
        offer = nil
    }

    /// Back from watching: the board.
    mutating func stopWatching() {
        if ended != nil, let watching { frames[watching.player] = nil }
        watching = nil
        ended = nil
    }

    /// What time does: the card goes, a result shown gives way to the board, a cheer ends.
    mutating func tick(now: Date) {
        if let offer, now > offer.until { self.offer = nil }
        if let ended, now > ended.until { stopWatching() }
        if let cheer, now > cheer.until { self.cheer = nil }
    }

    /// When `tick` next has something to do.
    var nextTick: Date? {
        [offer?.until, ended?.until, cheer?.until].compactMap { $0 }.min().map { $0.addingTimeInterval(0.001) }
    }

    // MARK: words

    /// A game's name, as the Dish says it (`DailyCatalog`).
    static func title(_ game: String) -> String { DailyCatalog.info(game)?.title ?? game }

    /// The card: "Mom is playing Sniff. Spoilers."
    static func offerWords(name: String, game: String) -> String {
        String(localized: "\(name) is playing \(title(game)). Spoilers.", comment: "TV: the watch card, when a player turns on Show on TV")
    }

    /// A time as m:ss, or h:mm:ss.
    static func clock(_ ms: Int) -> String {
        let total = max(0, ms / 1000)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// What a row says for its result: the time, guesses or points, or for a run that didn't
    /// finish how far it got, "62%" (spec §6, "Ranking").
    static func resultWords(_ r: DailyResult) -> String {
        switch r.outcome {
        case .gaveUp, .closed, .missed, .other: return "\(r.shownPercent)%"
        case .solved, .done:
            if let points = r.points { return points.formatted(.number.locale(Locale(identifier: "en_US"))) }
            if let guesses = r.guesses { return String(localized: "\(guesses) of 6", comment: "TV board: Sniff guesses used") }
            return clock(r.timeMs)
        }
    }

    /// A game's rows to draw, and how many more.
    static func visibleRows(_ g: DailyGameBoard, max: Int = rowsShown) -> (rows: [DailyBoardRow], more: Int) {
        (Array(g.rows.prefix(max)), Swift.max(0, g.rows.count - max))
    }
}

extension DailyResult {
    /// Solved, or Box Fort's ending: a run that finished well.
    var finished: Bool { outcome.finished }
}
