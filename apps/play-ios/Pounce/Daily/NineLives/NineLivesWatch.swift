import PounceKit
import SwiftUI

/// A Nine Lives run as a TV shows it while someone plays (spec §8): the server's board, read only.
/// No selection and no notes: those stay on the phone. The puzzle's givens draw white. SwiftUI and
/// PounceKit only: the TV builds this file with `NineLivesGrid` and `NineLivesArt`.
struct NineLivesWatch: DailyWatchView {
    nonisolated static let game = DailyCatalog.nineLives

    let puzzle: NineLivesPuzzle
    let state: NineLivesState

    init(puzzle: NineLivesPuzzle, state: NineLivesState) {
        self.puzzle = puzzle
        self.state = state
    }

    var body: some View {
        let board = NineLivesBoard(puzzle: puzzle, state: state)
        NineLivesGrid(board: board, clashes: Set(board.clashes), marks: NineLivesMarks(solved: board.looksSolved))
            // A container, so each cell keeps its own identifier.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("nine-lives-watch")
    }
}
