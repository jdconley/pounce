import PounceKit
import SwiftUI

/// A Nine Lives run as a TV shows it while someone plays (spec §8): the server's board, read only.
/// No selection and no notes: those stay on the phone. The puzzle's givens draw white. SwiftUI and
/// PounceKit only, and nothing from the play screen: the TV builds this folder (`NineLives/TV`).
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
        // Fills the box the TV gives it (a wide stage is 1792 by 848): the quilt square, as large as
        // the box's shorter side allows with its lip (a shadow 1.4% of its side, at least 3 points)
        // also inside, the two centred together. The grid draws its quilt half a lip below the top
        // of its frame and the lip under that, so the frame goes up one lip
        // (NineLivesWatchTests measures it).
        GeometryReader { geo in
            let side = max(0, min(geo.size.width, geo.size.height / 1.014, geo.size.height - 3))
            let lip = NineLivesGrid.Metrics(side: side).lip
            NineLivesGrid(board: board, clashes: Set(board.clashes), marks: NineLivesMarks(solved: board.looksSolved))
                .frame(width: side, height: side)
                .offset(y: -lip)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // A container, so each cell keeps its own identifier.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nine-lives-watch")
    }
}
