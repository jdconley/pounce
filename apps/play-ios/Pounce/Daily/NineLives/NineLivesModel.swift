import Observation
import PounceKit

/// The server's answer to one set under the lives rules.
enum NineLivesCheck: Sendable, Equatable {
    /// The answer's digit: it stays and locks.
    case right
    /// Wrong: one life gone, `lives` left. The set that leaves none brings the solution.
    case wrong(lives: Int, solution: [Int]?)
    /// Refused or lost: the session resyncs, and the board adopts the server's state.
    case refused
}

/// Where a Nine Lives board's moves go: the Daily Dish's run session (`NineLivesSessionDriver`),
/// or `NineLivesLocalDriver` for the DEBUG demo.
@MainActor
protocol NineLivesDriver: AnyObject {
    /// The first rules: a move the board already shows. The driver sends it on; it never waits.
    /// `urgent`: the move that fills the grid, so the server's answer (and the end) comes at once.
    func send(_ move: NineLivesMove, urgent: Bool)
    /// The lives rules: a set the board already shows, sent at once; the server's verdict on it.
    func check(cell: Int, digit: Int) async -> NineLivesCheck
    /// The server's hint: the cell it filled and its digit, or nil when there is none.
    func hint() async -> (cell: Int, digit: Int)?
}

/// One Nine Lives board on screen: the rules' board, the selection and the notes. Small state
/// updates only; the clash scan is a fixed 81 by 20 pass (`NineLivesRulesTests.clashesAreCheap`).
///
/// Under the lives rules (docs/daily-protocol.md, "## Nine Lives") a set shows at once and waits
/// for the server: a right digit locks, a wrong one comes out of the board and shows red in its
/// cell until it's replaced or erased, and costs a life. Erase is the phone's own: nothing is sent.
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
    /// Bumped on each life lost (the lives row drops a cat; the tip waits for the first).
    private(set) var livesLostBump = 0
    /// False once the run has ended (the host shows its end screen over the board).
    private(set) var playing = true

    @ObservationIgnored private weak var driver: (any NineLivesDriver)?
    @ObservationIgnored private var placements = 0
    /// Sets waiting for the server's verdict, by cell (lives rules).
    @ObservationIgnored private var pending: [Int: Int] = [:]

    init(board: NineLivesBoard, driver: any NineLivesDriver) {
        self.board = board
        self.driver = driver
        clashes = board.playsLives ? [] : Set(board.clashes)
        marks.notes = Array(repeating: [], count: NineLivesBoard.cellCount)
        marks.solved = board.looksSolved
        marks.solution = board.solution
        marks.selected = board.isOutOfLives ? nil : (0..<NineLivesBoard.cellCount).first { board.cells[$0] == 0 }
        if board.isOutOfLives { playing = false }
    }

    var lives: Bool { board.playsLives }
    var livesLeft: Int { board.lives }
    var hintsLeft: Int { board.hintsLeft }
    var outOfLives: Bool { board.isOutOfLives }
    var isSolved: Bool { board.looksSolved && pending.isEmpty }
    /// Taking input: the run is on, the grid isn't solved and lives are left.
    var live: Bool { playing && !isSolved && !board.isOutOfLives }
    /// The first rules: full, with a clash. With one solution, that's exactly "full and wrong".
    var notQuite: Bool { !lives && board.isFull && !clashes.isEmpty }
    /// The Hint button works: the run is on, and (lives rules) a hint is left.
    var canHint: Bool { live && !asking && board.hintsAvailable }
    var selected: Int? { marks.selected }

    /// How many cells hold `digit`.
    func count(of digit: Int) -> Int { board.count(of: digit) }

    /// All nine of `digit` are placed and none clashes: its key rests. A clashing one keeps the
    /// key awake, or a mistake could lock out the right cell.
    func isDone(_ digit: Int) -> Bool {
        board.count(of: digit) >= 9 && !clashes.contains { board.cells[$0] == digit }
    }

    func tap(_ cell: Int) {
        guard live else { return }
        marks.selected = cell
    }

    func toggleNotes() {
        guard live else { return }
        notesOn.toggle()
    }

    /// The run has ended: no more input. Out of lives, the solution shows once it is here.
    func end() {
        playing = false
        marks.selected = nil
        notesOn = false
    }

    /// A number pressed: a note in notes mode, else the cell's digit.
    func press(_ digit: Int) {
        guard let cell = marks.selected, live, !board.isLocked(cell) else { return }
        if notesOn {
            guard board.cells[cell] == 0, marks.wrong[cell] == nil else { return }
            if marks.notes[cell].contains(digit) { marks.notes[cell].remove(digit) } else { marks.notes[cell].insert(digit) }
            return
        }
        if lives {
            set(cell, digit)
        } else if board.cells[cell] == digit {
            play(.clear(cell: cell))
        } else {
            play(.set(cell: cell, digit: digit))
        }
    }

    func erase() {
        guard let cell = marks.selected, live, !board.isLocked(cell) else { return }
        if lives, marks.wrong[cell] != nil {
            // The phone's own: the server never held it.
            marks.wrong[cell] = nil
        } else if !lives, board.cells[cell] != 0 {
            play(.clear(cell: cell))
        } else {
            marks.notes[cell] = []
        }
    }

    func hint() async {
        guard canHint, let driver else { return }
        asking = true
        defer { asking = false }
        guard let reveal = await driver.hint() else { return }
        board.applyReveal(cell: reveal.cell, digit: reveal.digit)
        marks.wrong[reveal.cell] = nil
        marks.selected = reveal.cell
        afterPlacing(reveal.cell, digit: reveal.digit)
    }

    /// The server's own board (it refused something): it wins, and what was drawn since goes. A
    /// wrong number shown in a cell that is still empty stays: the server never held it anyway.
    func adopt(_ state: NineLivesState) {
        board = NineLivesBoard(puzzle: NineLivesPuzzle(givens: board.givens), state: state)
        pending = [:]
        marks.pending = []
        clashes = lives ? [] : Set(board.clashes)
        marks.wrong = marks.wrong.filter { board.cells[$0.key] == 0 }
        marks.solved = board.looksSolved
        if let solution = board.solution { showSolution(solution) }
        if let s = marks.selected, board.isLocked(s) { marks.selected = nil }
    }

    // MARK: the lives rules

    private func set(_ cell: Int, _ digit: Int) {
        guard marks.wrong[cell] != digit else { return }
        if board.costALife(cell, digit) {
            // Already wrong once: shown again, never sent again (it would cost another life).
            marks.wrong[cell] = digit
            marks.wrongBump += 1
            marks.wrongCell = cell
            return
        }
        guard board.apply(.set(cell: cell, digit: digit)) == nil else { return }
        marks.wrong[cell] = nil
        pending[cell] = digit
        marks.pending.insert(cell)
        placements += 1
        marks.placed = (cell, placements)
        guard let driver else { return }
        Task {
            let verdict = await driver.check(cell: cell, digit: digit)
            settle(cell, digit, verdict)
        }
    }

    /// The server's verdict on a set. It may come after the run's end (the third wrong number
    /// ends it), so it never waits on `live`.
    private func settle(_ cell: Int, _ digit: Int, _ verdict: NineLivesCheck) {
        guard pending[cell] == digit else { return }
        pending[cell] = nil
        marks.pending.remove(cell)
        switch verdict {
        case .right:
            afterRight(cell, digit: digit)
        case .wrong(let left, let solution):
            board.applyWrong(cell: cell, digit: digit, lives: left)
            if board.cells[cell] == 0 { marks.wrong[cell] = digit }
            marks.wrongBump += 1
            marks.wrongCell = cell
            livesLostBump += 1
            if let solution { board.applySolution(solution) }
            if board.isOutOfLives {
                marks.selected = nil
                notesOn = false
                if let solution = board.solution { showSolution(solution) }
            }
        case .refused:
            // The resync that follows brings the server's board.
            board.takeBack(cell: cell)
        }
    }

    private func afterRight(_ cell: Int, digit: Int) {
        marks.notes[cell] = []
        for p in NineLivesBoard.peers(of: cell) { marks.notes[p].remove(digit) }
        if isSolved {
            marks.solved = true
            marks.selected = nil
        }
    }

    /// Out of lives: the rest of the grid fills in, softly, from the server's solution.
    private func showSolution(_ solution: [Int]) {
        guard marks.solution == nil else { return }
        marks.wrong = [:]
        marks.solution = solution
    }

    // MARK: the first rules

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
        // Under lives the board holds only right digits (and sets on their way): no clashes.
        clashes = lives ? [] : Set(board.clashes)
        if notQuite && !wasNotQuite { notQuiteBump += 1 }
        if isSolved {
            marks.solved = true
            marks.selected = nil
        }
    }
}
