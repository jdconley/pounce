import PounceKit
import SwiftUI

/// Sniff watched on a TV (spec §8): the run as the server sees it, guesses with their letters,
/// read-only. Built from the run's `publicState` (`{ guesses, answer? }`); nothing is typed here,
/// so no draft row shows. The TV's host draws whose run it is and the result.
struct SniffWatchView: View {
    let board: SniffBoard

    var body: some View {
        GeometryReader { geo in
            let showsAnswer = board.answer != nil && !board.isSolved
            let tag = SniffTrail.tagWidth(
                fitting: CGSize(width: geo.size.width * 0.9, height: geo.size.height * 0.92),
                rows: SniffBoard.tries + (showsAnswer ? 1 : 0), cap: 150)
            SniffTrail(board: board, tagWidth: tag)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .contain)
    }
}
