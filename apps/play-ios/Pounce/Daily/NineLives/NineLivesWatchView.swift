import PounceKit
import SwiftUI

/// A Nine Lives run as a TV shows it while someone plays (spec §8): the server's board, read only.
/// No selection and no notes: those stay on the phone.
struct NineLivesWatchView: View {
    let puzzle: NineLivesPuzzle
    let state: NineLivesState

    var body: some View {
        let board = NineLivesBoard(puzzle: puzzle, state: state)
        NineLivesGrid(board: board, clashes: Set(board.clashes), marks: NineLivesMarks(solved: board.looksSolved))
            .accessibilityIdentifier("nine-lives-watch")
    }
}
