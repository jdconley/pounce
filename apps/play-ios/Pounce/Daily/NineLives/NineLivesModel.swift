import Observation
import PounceKit

/// Where a Nine Lives board's moves go: the Daily Dish's run session (`NineLivesSessionDriver`),
/// or `NineLivesLocalDriver` for the DEBUG demo.
@MainActor
protocol NineLivesDriver: AnyObject {
    /// A move the board already shows. The driver sends it on; it never waits. `urgent`: the move
    /// that fills the grid, so the server's answer (and the end) comes at once.
    func send(_ move: NineLivesMove, urgent: Bool)
    /// The server's hint: the cell it filled and its digit, or nil when there is none.
    func hint() async -> (cell: Int, digit: Int)?
}

/// One Nine Lives board on screen: the rules' board, the selection and the notes. Small state
/// updates only; the clash scan is a fixed 81 by 20 pass (`NineLivesRulesTests.clashesAreCheap`).
@MainActor @Observable
final class NineLivesModel {
    private(set) var board: NineLivesBoard
    private(set) var clashes: Set<Int>
    private(set) var marks = NineLivesMarks()
    private(set) var notesOn = false
    /// A hint is on its way.
    private(set) var asking = false
    /// Bumped when "Not quite" appears, so it shakes.
    private(set) var notQuiteBump = 0
    /// False once the run has ended (the host shows its end screen over the board).
    private(set) var playing = true

    @ObservationIgnored private weak var driver: (any NineLivesDriver)?
    @ObservationIgnored private var placements = 0

    init(board: NineLivesBoard, driver: any NineLivesDriver) {
        self.board = board
        self.driver = driver
        clashes = Set(board.clashes)
        marks.notes = Array(repeating: [], count: NineLivesBoard.cellCount)
        marks.solved = board.looksSolved
        marks.selected = (0..<NineLivesBoard.cellCount).first { board.cells[$0] == 0 }
    }

    var isSolved: Bool { board.looksSolved }
    /// Taking input: the run is on and the grid isn't solved.
    var live: Bool { playing && !board.looksSolved }
    /// Full, with a clash: with one solution, that's exactly "full and wrong".
    var notQuite: Bool { board.isFull && !clashes.isEmpty }
    var selected: Int? { marks.selected }

    /// How many cells hold `digit`; at nine it's done.
    func count(of digit: Int) -> Int { board.count(of: digit) }

    func tap(_ cell: Int) {
        guard live else { return }
        marks.selected = cell
    }

    func toggleNotes() {
        guard live else { return }
        notesOn.toggle()
    }

    /// The run has ended: no more input.
    func end() {
        playing = false
        marks.selected = nil
    }

    /// A number pressed: a note in notes mode, else the cell's digit (or off again, the same digit twice).
    func press(_ digit: Int) {
        guard let cell = marks.selected, live, !board.isLocked(cell) else { return }
        if notesOn {
            guard board.cells[cell] == 0 else { return }
            if marks.notes[cell].contains(digit) { marks.notes[cell].remove(digit) } else { marks.notes[cell].insert(digit) }
            return
        }
        if board.cells[cell] == digit {
            play(.clear(cell: cell))
        } else {
            play(.set(cell: cell, digit: digit))
        }
    }

    func erase() {
        guard let cell = marks.selected, live, !board.isLocked(cell) else { return }
        if board.cells[cell] != 0 {
            play(.clear(cell: cell))
        } else {
            marks.notes[cell] = []
        }
    }

    func hint() async {
        guard live, !asking, let driver else { return }
        asking = true
        defer { asking = false }
        guard let reveal = await driver.hint() else { return }
        board.applyReveal(cell: reveal.cell, digit: reveal.digit)
        marks.selected = reveal.cell
        afterPlacing(reveal.cell, digit: reveal.digit)
    }

    /// The server's own board (it refused something): it wins, and what was drawn since goes.
    func adopt(_ state: NineLivesState) {
        board = NineLivesBoard(puzzle: NineLivesPuzzle(givens: board.givens), state: state)
        clashes = Set(board.clashes)
        marks.solved = board.looksSolved
        if let s = marks.selected, board.isLocked(s) { marks.selected = nil }
    }

    private func play(_ move: NineLivesMove) {
        guard board.apply(move) == nil else { return }
        driver?.send(move, urgent: board.looksSolved)
        if case .set(let cell, let digit) = move {
            afterPlacing(cell, digit: digit)
        } else {
            refresh()
        }
    }

    private func afterPlacing(_ cell: Int, digit: Int) {
        marks.notes[cell] = []
        // A placed digit can't be a note anywhere it would clash.
        for p in NineLivesBoard.peers(of: cell) { marks.notes[p].remove(digit) }
        placements += 1
        marks.placed = (cell, placements)
        let before = clashes
        refresh()
        if clashes.contains(cell) && !before.contains(cell) { marks.clashBump += 1 }
    }

    private func refresh() {
        let wasNotQuite = notQuite
        clashes = Set(board.clashes)
        if notQuite && !wasNotQuite { notQuiteBump += 1 }
        if board.looksSolved {
            marks.solved = true
            marks.selected = nil
        }
    }
}
