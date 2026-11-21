import PounceKit
import SwiftUI

/// Nine Lives in the Daily Dish (the host contract, `Pounce/Daily/DailyGameHost.swift`). The host
/// draws the bar, the clock, give up, the end and share; this is the board and its keys, talking
/// to the server only through the run session.
struct NineLivesDaily: DailyGameView {
    nonisolated static let game = DailyCatalog.nineLives

    /// What a hint fills: cell `i` holds `d` (the server's `nineLives.hint`).
    struct Reveal: Decodable, Sendable {
        let i: Int
        let d: Int
    }

    private let session: DailyRunSession
    @SwiftUI.State private var driver: NineLivesSessionDriver
    @SwiftUI.State private var model: NineLivesModel

    init(session: DailyRunSession, puzzle: NineLivesPuzzle, state: NineLivesState) {
        self.session = session
        let driver = NineLivesSessionDriver(session: session)
        _driver = SwiftUI.State(initialValue: driver)
        _model = SwiftUI.State(initialValue: NineLivesModel(board: NineLivesBoard(puzzle: puzzle, state: state), driver: driver))
    }

    var body: some View {
        NineLivesPlayView(model: model)
            .task {
                for await event in await session.events(reveal: Reveal.self, state: NineLivesState.self) {
                    switch event {
                    case .resync(let state, _, _): model.adopt(state)
                    case .ended: model.end()
                    case .accepted, .hinted, .link: break
                    }
                }
            }
            .task { await driver.pump() }
    }
}

/// The run session as the board's driver. Moves go out through one queue, in the order they were
/// played, and never make the board wait.
@MainActor
final class NineLivesSessionDriver: NineLivesDriver {
    private let session: DailyRunSession
    private let moves: AsyncStream<(NineLivesMove, Bool)>
    private let queue: AsyncStream<(NineLivesMove, Bool)>.Continuation

    init(session: DailyRunSession) {
        self.session = session
        (moves, queue) = AsyncStream.makeStream()
    }

    func send(_ move: NineLivesMove, urgent: Bool) {
        queue.yield((move, urgent))
    }

    func hint() async -> (cell: Int, digit: Int)? {
        guard let reveal = await session.hint(as: NineLivesDaily.Reveal.self) else { return nil }
        return (reveal.i, reveal.d)
    }

    /// Hands each move to the session in order, for as long as the screen is up.
    func pump() async {
        for await (move, urgent) in moves {
            await session.send(move: move, urgent: urgent)
        }
    }
}
