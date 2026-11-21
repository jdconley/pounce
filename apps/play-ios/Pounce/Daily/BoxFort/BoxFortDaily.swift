import PounceKit
import SwiftUI

/// Box Fort in the Daily Dish: the board on the run the host gives it (`DailyGameHost.swift`).
/// The host draws the top bar, the clock, Show on TV, give up and the end; Box Fort draws the
/// rug, the pieces and the score.
///
/// Placements go to the session one at a time, in order, through `outbox`: a set's last piece and
/// the run's last move are urgent, so the next set (or the result) comes straight back. The
/// session's answers deal the next set, or hand over the server's state after a refusal.
struct BoxFortDaily: DailyGameView {
    nonisolated static let game = DailyCatalog.boxFort

    let session: DailyRunSession
    @SwiftUI.State private var model: BoxFortPlayModel
    private let outbox: AsyncStream<(BoxFortMove, Bool)>

    init(session: DailyRunSession, puzzle: BoxFortPublicPuzzle, state: BoxFortState) {
        self.session = session
        let (outbox, mail) = AsyncStream<(BoxFortMove, Bool)>.makeStream()
        self.outbox = outbox
        _model = SwiftUI.State(initialValue: BoxFortPlayModel(state: state) { move, urgent in mail.yield((move, urgent)) })
    }

    var body: some View {
        BoxFortPlayView(model: model)
            .task {
                for await (move, urgent) in outbox { await session.send(move: move, urgent: urgent) }
            }
            .task {
                for await event in await session.events(reveal: BoxFortReveal.self, state: BoxFortState.self) {
                    switch event {
                    case .accepted(_, let reveals, _):
                        for reveal in reveals { await model.receive(reveal) }
                    case .resync(let state, _, _):
                        model.resync(state)
                    case .ended:
                        model.stop()
                    case .hinted, .link:
                        break
                    }
                }
            }
    }
}
