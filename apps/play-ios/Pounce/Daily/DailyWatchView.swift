import PounceKit
import SwiftUI

// The TV's half of the daily games contract. SwiftUI and PounceKit only: the TV target builds
// this file, `DailyWatchGames.swift` and the watch views listed there, and nothing else of
// `Pounce/Daily`.

/// A daily game as the TV draws it while someone plays (spec §8): read-only, from a `watch`
/// frame's public puzzle and public state (exactly what `start` shows the player). SwiftUI and
/// PounceKit only, so the TV target can build it.
@MainActor
protocol DailyWatchView: View, SendableMetatype {
    associatedtype Puzzle: Decodable & Sendable
    associatedtype State: Decodable & Sendable

    nonisolated static var game: DailyGameInfo { get }

    init(puzzle: Puzzle, state: State)
}

extension DailyWatchView {
    /// One watch frame decoded off the main actor, and its view's builder. Nil when the frame
    /// isn't this game's.
    @concurrent nonisolated static func frame(puzzle: DailyJSON, state: DailyJSON) async -> (@MainActor @Sendable () -> AnyView)? {
        guard let p = try? puzzle.decoded(as: Puzzle.self), let s = try? state.decoded(as: State.self) else { return nil }
        return { AnyView(Self(puzzle: p, state: s)) }
    }
}
