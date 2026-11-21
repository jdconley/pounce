import PounceKit
import SwiftUI

/// A Nine Lives run as a TV shows it while someone plays (spec §8): the server's board, read only.
/// No selection and no notes: those stay on the phone. The puzzle's givens draw white; without
/// them (a frame that carries only the state) every digit draws as a player's.
struct NineLivesWatch: DailyWatchView {
    nonisolated static let game = DailyCatalog.nineLives

    let puzzle: NineLivesPuzzle
    let state: NineLivesState

    init(puzzle: NineLivesPuzzle, state: NineLivesState) {
        self.puzzle = puzzle
        self.state = state
    }

    init(state: NineLivesState) {
        self.init(puzzle: NineLivesPuzzle(givens: Array(repeating: 0, count: NineLivesBoard.cellCount)), state: state)
    }

    var body: some View {
        let board = NineLivesBoard(puzzle: puzzle, state: state)
        NineLivesGrid(board: board, clashes: Set(board.clashes), marks: NineLivesMarks(solved: board.looksSolved))
            .accessibilityIdentifier("nine-lives-watch")
    }
}
