import PounceKit
import SwiftUI

// The contract every daily game plugs into (daily games plan, "The contracts" §2).
//
// The host (`DailyPuzzleScreen`) draws the top bar, the clock, Show on TV, give up, the end
// screen and share. A game draws only its board and controls, as a `DailyGameView`, and a
// read-only `DailyWatchView` for the TV. Both are listed once in a registry: play views in
// `DailyGames.swift`, watch views in `DailyWatchGames.swift` (the TV builds only that one).
//
// How a game talks to the run (`DailyRunSession`, PounceKit `Daily/DailyClient.swift`):
// - Draw each move at once, then `await session.send(move:urgent:)`. It never waits on the
//   network; the session batches. Mark urgent a move whose answer the player waits for
//   (Box Fort's last piece of a set). For a move that needs its answer before it can be drawn
//   (a Sniff guess), `await session.play(move, revealing: Reveal.self)` returns its reveals.
// - A hint: `await session.hint(as: Reveal.self)`; nil when there's none.
// - Listen once, in a `.task`, to `await session.events(reveal: Reveal.self, state: State.self)`:
//   `.accepted` brings reveals (Box Fort's next set), `.resync` the server's state after it refused
//   something (draw it, drop anything drawn since), `.ended` the result (the host shows the end
//   screen; a game may stop taking input). Decoding happens on the session, never here.
// - Rule checks over 1 ms on an iPhone SE run off the main actor (`@concurrent`), as everywhere.

/// A daily game's play screen: its board and controls, nothing else.
@MainActor
protocol DailyGameView: View {
    /// The game's public puzzle, as the start answer's `puzzle`.
    associatedtype Puzzle: Decodable & Sendable
    /// The game's public state, as the start answer's `state` and a resync's.
    associatedtype State: Decodable & Sendable

    /// The game this screen plays (`DailyCatalog`). Write it `nonisolated static let game = DailyCatalog.sniff`.
    nonisolated static var game: DailyGameInfo { get }

    /// Built once the host has decoded the start answer, off the main actor. `state` is where
    /// the run stands: empty for a new run, the server's for a resumed one.
    init(session: DailyRunSession, puzzle: Puzzle, state: State)

    /// The share card's grid for a finished run, from the server's final public state: marks with
    /// no letters or digits (Sniff's guesses). Nil (the default): the card shows the result alone.
    nonisolated static func shareMarks(_ state: State) -> [[DailyShareMark]]?
}

extension DailyGameView {
    nonisolated static func shareMarks(_ state: State) -> [[DailyShareMark]]? { nil }
}

/// A daily game as the TV draws it while someone plays (spec §8): read-only, from the server's
/// public state alone (a `watch` frame carries only `state`). SwiftUI and PounceKit only, so the
/// TV target can build it.
@MainActor
protocol DailyWatchView: View {
    associatedtype State: Decodable & Sendable

    nonisolated static var game: DailyGameInfo { get }

    init(state: State)
}

/// A game's play screen, ready to show: the start answer decoded, and a way to build the view.
struct DailyPlayable: Sendable {
    let game: DailyGameInfo
    let make: @MainActor @Sendable (DailyRunSession) -> AnyView
    /// The share card's marks from a final state (decoded off the main actor by the caller).
    let marks: @Sendable (DailyJSON) -> [[DailyShareMark]]?
}

extension DailyGameView {
    /// Decodes the start answer off the main actor and returns the screen's builder.
    nonisolated static func prepare(_ session: DailyRunSession) async throws -> DailyPlayable {
        let (puzzle, state) = try await session.decodeStart(puzzle: Puzzle.self, state: State.self)
        return DailyPlayable(
            game: Self.game, make: { session in AnyView(Self(session: session, puzzle: puzzle, state: state)) },
            marks: { json in (try? json.decoded(as: State.self)).flatMap(Self.shareMarks) })
    }
}

extension DailyWatchView {
    /// One watch frame's state decoded off the main actor, and its view's builder. Nil when the
    /// state isn't this game's.
    @concurrent nonisolated static func frame(_ state: DailyJSON) async -> (@MainActor @Sendable () -> AnyView)? {
        guard let decoded = try? state.decoded(as: State.self) else { return nil }
        return { AnyView(Self(state: decoded)) }
    }
}

enum DailyHost {
    /// The play screen for `game`, when this app has one.
    static func playable(_ game: String) -> (any DailyGameView.Type)? {
        DailyGames.play.first { $0.game.id == game }
    }

    /// The games the Dish shows today: those the server lists on the board that this app can play,
    /// in the server's order (Sniff, Nine Lives, Cat Nap, Box Fort). Debug's `-demo-dish` shows
    /// every game the catalog knows.
    static func shown(_ board: DailyBoard?) -> [DailyGameInfo] {
        guard let board else { return [] }
        return board.games.compactMap { game in
            guard let info = DailyCatalog.info(game.game) else { return nil }
            #if DEBUG
                if DailyDemo.active { return info }
            #endif
            return playable(game.game) == nil ? nil : info
        }
    }

    /// The first game shown that I haven't finished, after `game` (the end screen's Next puzzle).
    static func next(after game: String, board: DailyBoard?) -> DailyGameInfo? {
        let games = shown(board).filter { $0.id != game }
        return games.first { board?.mine($0.id)?.result == nil }
    }

    /// Opens the existential to prepare a game's screen.
    static func prepare(_ type: any DailyGameView.Type, _ session: DailyRunSession) async throws -> DailyPlayable {
        try await type.prepare(session)
    }
}
