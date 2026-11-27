import PounceKit
import SwiftUI

/// A Nine Lives run as a TV shows it while someone plays (spec §8): the server's board, read only.
/// No selection and no notes: those stay on the phone. The puzzle's givens draw white. Under the
/// lives rules, beside the quilt: the lives left as cat heads and the hints left, and in the quilt
/// each cell's last wrong number while the cell is still empty; out of lives, the solution. SwiftUI
/// and PounceKit only, and nothing from the play screen: the TV builds this folder (`NineLives/TV`).
struct NineLivesWatch: DailyWatchView {
    nonisolated static let game = DailyCatalog.nineLives

    let puzzle: NineLivesPuzzle
    let state: NineLivesState

    init(puzzle: NineLivesPuzzle, state: NineLivesState) {
        self.puzzle = puzzle
        self.state = state
    }

    /// The counters' room beside the quilt (a wide box) or under it (a tall or square one).
    static let panelWide: CGFloat = 400
    static let panelTall: CGFloat = 190
    static let gap: CGFloat = 48

    var body: some View {
        let board = NineLivesBoard(puzzle: puzzle, state: state)
        // Fills the box the TV gives it (a wide stage is 1792 by 848): the quilt square, as large as
        // the box allows with its lip (a shadow 1.4% of its side, at least 3 points) also inside,
        // and the counters, the whole centred. The grid draws its quilt half a lip below the top of
        // its frame and the lip under that, so the frame goes up one lip (NineLivesWatchTests
        // measures it).
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            if board.playsLives {
                if w >= h * 1.4 {
                    let side = Self.side(width: w - Self.panelWide - Self.gap, height: h)
                    HStack(spacing: Self.gap) {
                        quilt(board, side: side)
                        counters(board, stacked: true).frame(width: Self.panelWide)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    let side = Self.side(width: w, height: h - Self.panelTall - Self.gap)
                    VStack(spacing: Self.gap) {
                        quilt(board, side: side)
                        counters(board, stacked: false).frame(height: Self.panelTall)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                let side = Self.side(width: w, height: h)
                NineLivesGrid(board: board, clashes: Set(board.clashes), marks: Self.marks(board))
                    .frame(width: side, height: side)
                    .offset(y: -NineLivesGrid.Metrics(side: side).lip)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // A container, so each cell keeps its own identifier.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nine-lives-watch")
    }

    /// The largest quilt, lip included, inside `width` by `height`.
    static func side(width: CGFloat, height: CGFloat) -> CGFloat {
        max(0, min(width, height / 1.014, height - 3))
    }

    /// The quilt in a frame of its own size with its lip, to sit beside the counters.
    private func quilt(_ board: NineLivesBoard, side: CGFloat) -> some View {
        let lip = NineLivesGrid.Metrics(side: side).lip
        return NineLivesGrid(board: board, clashes: [], marks: Self.marks(board))
            .frame(width: side, height: side)
            .offset(y: -lip)
            .frame(width: side, height: side + lip)
    }

    /// What the quilt draws besides the board: solved, each empty cell's last wrong number, and
    /// out of lives the solution.
    static func marks(_ board: NineLivesBoard) -> NineLivesMarks {
        var marks = NineLivesMarks(solved: board.looksSolved)
        guard board.playsLives else { return marks }
        for w in board.wrong where board.cells[w.i] == 0 { marks.wrong[w.i] = w.d }
        marks.solution = board.solution
        return marks
    }

    @ViewBuilder private func counters(_ board: NineLivesBoard, stacked: Bool) -> some View {
        let layout = stacked ? AnyLayout(VStackLayout(spacing: 40)) : AnyLayout(HStackLayout(spacing: 72))
        layout {
            LivesRow(left: board.lives, size: 104)
                .animation(.spring(duration: 0.4, bounce: 0.5), value: board.lives)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Lives", comment: "TV: Nine Lives' lives left"))
                .accessibilityValue(Text("\(board.lives) of \(NineLivesRules.lifeCount)", comment: "TV: lives left, e.g. 2 of 3"))
                .accessibilityIdentifier("nine-lives-watch-lives")
            if board.isOutOfLives {
                OutlinedText(String(localized: "Out of lives", comment: "TV: a watched Nine Lives run, out of lives"), size: 60, width: 5)
                    .accessibilityIdentifier("nine-lives-watch-out")
            } else {
                OutlinedText(Self.hintsWords(board.hintsLeft), size: 56, fill: board.hintsLeft > 0 ? Palette.yellow : .white, width: 5)
                    .opacity(board.hintsLeft > 0 ? 1 : 0.6)
                    .accessibilityIdentifier("nine-lives-watch-hints")
            }
        }
        .compositingGroup()
    }

    /// "2 hints left", "1 hint left", "No hints left".
    static func hintsWords(_ left: Int) -> String {
        switch left {
        case 0: String(localized: "No hints left", comment: "TV: Nine Lives, every hint used")
        case 1: String(localized: "1 hint left", comment: "TV: Nine Lives, one hint left")
        default: String(localized: "\(left) hints left", comment: "TV: Nine Lives, hints left, e.g. 2 hints left")
        }
    }
}
