import PounceKit
import SwiftUI

/// Nine Lives in the Daily Dish (the host contract, `Pounce/Daily/DailyGameHost.swift`). The host
/// draws the bar, the clock, give up, the end and share; this is the board and its keys, talking
/// to the server only through the run session.
struct NineLivesDaily: DailyGameView {
    nonisolated static let game = DailyCatalog.nineLives

    /// What the server reveals: a hint's cell, and under the lives rules a wrong number (the last
    /// one with the solution). PounceKit, `NineLivesReveal`.
    typealias Reveal = NineLivesReveal

    /// Out of lives, the board fills in the solution under "Out of lives" before the end screen.
    nonisolated static func endHold(_ result: DailyResult) -> Duration {
        result.outcome == .missed ? .milliseconds(2600) : .zero
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

    /// A set under the lives rules: sent at once (everything waiting goes with it), and the
    /// server's verdict read from its batch's reveals.
    func check(cell: Int, digit: Int) async -> NineLivesCheck {
        switch await session.play(NineLivesMove.set(cell: cell, digit: digit), revealing: NineLivesReveal.self) {
        case .refused:
            return .refused
        case .accepted(let reveals):
            // The batch's reveals: this set's, if it was wrong; the solution rides on the last life's.
            var verdict = NineLivesCheck.right
            var solution: [Int]?
            for case .wrong(let i, let d, let left, let cells) in reveals {
                if let cells { solution = cells }
                if i == cell && d == digit { verdict = .wrong(lives: left, solution: nil) }
            }
            if case .wrong(let left, _) = verdict { return .wrong(lives: left, solution: solution) }
            // The run ended in this batch, and a set after the ending one was dropped: unless it's
            // the answer, it comes back out, and the solution shows there.
            if let solution, solution[cell] != digit { return .refused }
            return verdict
        }
    }

    func hint() async -> (cell: Int, digit: Int)? {
        guard case .hint(let cell, let digit)? = await session.hint(as: NineLivesReveal.self) else { return nil }
        return (cell, digit)
    }

    /// Hands each move to the session in order, for as long as the screen is up.
    func pump() async {
        for await (move, urgent) in moves {
            await session.send(move: move, urgent: urgent)
        }
    }
}
