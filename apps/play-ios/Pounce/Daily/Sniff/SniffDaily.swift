import PounceKit
import SwiftUI

/// Sniff on the Dish's host (`DailyGameHost.swift`): the trails and keyboard, playing a real run.
/// Each guess goes to the server at once and waits for its marks (`session.play`); a resync puts
/// the server's board back; the end stops input while the host shows the result.
struct SniffDaily: DailyGameView {
    nonisolated static let game = DailyCatalog.sniff

    private let session: DailyRunSession
    @SwiftUI.State private var model: SniffPlayModel

    init(session: DailyRunSession, puzzle: SniffPublic, state: SniffView) {
        self.session = session
        _model = SwiftUI.State(initialValue: SniffPlayModel(board: state.board, referee: SessionReferee(session: session)))
    }

    /// The share card: a row of paws per guess, no letters (spec §7).
    nonisolated static func shareMarks(_ state: SniffView) -> [[DailyShareMark]]? {
        state.guesses.map { guess in
            guess.marks.map { mark in
                switch mark {
                case .spot: .hit
                case .near: .near
                case .none: .miss
                }
            }
        }
    }

    var body: some View {
        SniffPlayView(model: model)
            .task {
                for await event in await session.events(reveal: SniffReveal.self, state: SniffView.self) {
                    switch event {
                    case .resync(let state, _, _): model.resync(state.board)
                    case .ended: model.stop()
                    case .accepted, .hinted, .link: break
                    }
                }
            }
    }
}

/// The server, through the run: a guess's reveal, or nil when it was refused (a resync follows).
private struct SessionReferee: SniffReferee {
    let session: DailyRunSession

    func guess(_ word: String) async -> SniffReveal? {
        switch await session.play(SniffMove(word: word), revealing: SniffReveal.self) {
        case .accepted(let reveals): reveals.last
        case .refused: nil
        }
    }
}
