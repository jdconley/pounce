#if DEBUG
import PounceKit
import SwiftUI

/// Nine Lives on its own, in a few set states, for screenshots and for trying the game with no
/// server. `-nine-lives-demo start|midway|wrong|spent|out|clash|notquite|solved|watch|dish|dish-almost|dish-last`.
/// They play the lives rules, but `clash` and `notquite`, which are the first rules' (no lives).
/// `wrong`: a life lost, the wrong number still in its cell. `spent`: one life, no hints left.
/// `out`: out of lives, the solution filled in. `dish` plays the Dish's own screen
/// (`NineLivesDaily`) over a real `DailyRunSession`, refereed in the app by `NineLivesDemoServer`
/// (`dish-almost`: two cells from done; `dish-last`: one life and one hint left).
struct NineLivesDemoScreen: View {
    enum Preset: String {
        case start, midway, wrong, spent, out, clash, notquite, solved, watch, dish
        case dishAlmost = "dish-almost"
        case dishLast = "dish-last"

        var isDish: Bool { self == .dish || self == .dishAlmost || self == .dishLast }
    }

    let preset: Preset
    @State private var driver = NineLivesLocalDriver()
    @State private var model: NineLivesModel?
    @State private var dish: (session: DailyRunSession, playable: DailyPlayable)?

    static func preset(arguments: [String] = CommandLine.arguments) -> Preset? {
        guard let i = arguments.firstIndex(of: "-nine-lives-demo"), arguments.indices.contains(i + 1) else { return nil }
        return Preset(rawValue: arguments[i + 1])
    }

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [Palette.violet.mix(with: Palette.night, by: 0.4), Palette.night], center: .top,
                startRadius: 40, endRadius: 700
            )
            .ignoresSafeArea()
            if preset.isDish {
                if let dish { dish.playable.make(dish.session) }
            } else if preset == .watch {
                let s = Self.state(.midway)
                NineLivesWatch(
                    puzzle: NineLivesPuzzle(givens: NineLivesLocalDriver.givens), state: s.state
                )
                .padding(40)
            } else if let model {
                NineLivesPlayView(model: model)
            }
        }
        .task {
            if preset.isDish {
                let server = NineLivesDemoServer(almost: preset == .dishAlmost, last: preset == .dishLast)
                guard dish == nil,
                    let session = try? await DailyRunSession.begin(game: "nine-lives", service: server, person: nil),
                    let playable = try? await NineLivesDaily.prepare(session)
                else { return }
                dish = (session, playable)
                return
            }
            guard model == nil, preset != .watch else { return }
            let s = Self.state(preset)
            driver.resume(s.state)
            let m = NineLivesModel(board: NineLivesBoard(puzzle: NineLivesPuzzle(givens: NineLivesLocalDriver.givens), state: s.state), driver: driver)
            for (cell, notes) in s.notes {
                m.tap(cell)
                m.toggleNotes()
                for d in notes { m.press(d) }
                m.toggleNotes()
            }
            if let sel = s.selected { m.tap(sel) }
            // The wrong number shown in its cell: entered again, which costs nothing (it already cost its life).
            if let w = s.state.wrong.last, s.state.lives > 0, s.state.cells[w.i] == 0 {
                m.tap(w.i)
                m.press(w.d)
            }
            model = m
        }
    }

    /// A board for each preset, built from the sample's solution.
    /// (`dish` starts from the empty board, like `start`.)
    static func state(_ preset: Preset) -> (state: NineLivesState, notes: [Int: [Int]], selected: Int?) {
        let givens = NineLivesLocalDriver.givens
        let solution = NineLivesLocalDriver.solution
        let open = givens.indices.filter { givens[$0] == 0 }
        var cells = givens
        var hinted: [Int] = []
        var notes: [Int: [Int]] = [:]
        var selected: Int?
        var rules = NineLivesRules.lives
        var lives = NineLivesRules.lifeCount
        var hintsLeft = NineLivesRules.hintCount
        var wrong: [NineLivesWrong] = []
        var shownSolution: [Int]?
        /// A wrong digit for `cell`: one that clashes with nothing in sight is the honest kind.
        func wrongDigit(_ cell: Int) -> Int { solution[cell] % 9 + 1 }
        switch preset {
        case .start, .watch, .dish, .dishAlmost, .dishLast:
            selected = open.first
            if preset == .watch { fallthrough }
        case .midway, .wrong:
            for i in open.prefix(open.count / 2) { cells[i] = solution[i] }
            hinted = [open[open.count / 2]]
            cells[hinted[0]] = solution[hinted[0]]
            hintsLeft = 2
            let free = open.suffix(open.count / 2 - 1)
            notes[free.first!] = [2, 5, 8]
            notes[free.dropFirst(3).first!] = [1, 4]
            selected = open[open.count / 3]
            if preset == .wrong || preset == .watch {
                let w = Array(free)[6]
                wrong = [NineLivesWrong(i: w, d: wrongDigit(w))]
                lives = 2
                selected = w
            }
        case .spent:
            for i in open.prefix(open.count * 3 / 4) { cells[i] = solution[i] }
            let rest = Array(open.dropFirst(open.count * 3 / 4))
            hinted = Array(rest.prefix(3))
            for i in hinted { cells[i] = solution[i] }
            hintsLeft = 0
            wrong = [rest[3], rest[5]].map { NineLivesWrong(i: $0, d: wrongDigit($0)) }
            lives = 1
            selected = rest[4]
        case .out:
            for i in open.prefix(open.count * 2 / 3) { cells[i] = solution[i] }
            hinted = [open[open.count / 4]]
            hintsLeft = 2
            let rest = Array(open.dropFirst(open.count * 2 / 3))
            wrong = [rest[1], rest[4], rest[9]].map { NineLivesWrong(i: $0, d: wrongDigit($0)) }
            lives = 0
            shownSolution = solution
        case .clash:
            rules = .first
            for i in open.prefix(open.count / 3) { cells[i] = solution[i] }
            let i = open[open.count / 3]
            let row = i / 9
            let given = (0..<9).map { givens[row * 9 + $0] }.first { $0 != 0 }!
            cells[i] = given
            selected = i
        case .notquite:
            rules = .first
            for i in open { cells[i] = solution[i] }
            let a = open[open.count - 1]
            cells[a] = solution[a] % 9 + 1
            selected = a
        case .solved:
            for i in open { cells[i] = solution[i] }
        }
        hinted.sort()
        let state = NineLivesState(
            cells: cells, hinted: hinted, rules: rules, lives: lives, hintsLeft: hintsLeft, wrong: wrong, solution: shownSolution)
        return (state, notes, selected)
    }
}

/// A stand-in for the server, for the `dish` demo: it referees the sample puzzle with the lives
/// rules (docs/daily-protocol.md, "## Nine Lives") and answers hints from the sample's solution,
/// which no real client ever has.
actor NineLivesDemoServer: DailyService {
    struct NotHere: Error {}

    private var board: NineLivesBoard
    private var seq = 0
    private var hints = 0
    private var result: DailyResult?
    private let startedAt: Int64
    private let date: String
    private let number: Int
    private let solution = NineLivesLocalDriver.solution

    private var now: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    /// `almost`: two cells from done. `midway`: half the open cells filled, three minutes in (the
    /// Dish demo's puzzle in play). `last`: a third filled, one life and one hint left.
    init(almost: Bool = false, midway: Bool = false, last: Bool = false, date: String = "2027-01-04", number: Int = 1) {
        var board = NineLivesBoard(givens: NineLivesLocalDriver.givens, rules: .lives)
        let open = board.givens.indices.filter { board.givens[$0] == 0 }
        // Midway: about half, scattered over the board as a person fills it.
        let filled =
            almost ? Array(open.dropLast(2))
            : midway ? open.enumerated().filter { ($0.offset * 7) % 11 < 6 }.map(\.element)
            : last ? Array(open.prefix(open.count / 3)) : []
        for i in filled { board.apply(.set(cell: i, digit: NineLivesLocalDriver.solution[i])) }
        if last {
            let rest = Array(open.dropFirst(open.count / 3))
            for i in rest.prefix(2) { board.applyReveal(cell: i, digit: NineLivesLocalDriver.solution[i]) }
            for i in [rest[3], rest[6]] {
                let d = NineLivesLocalDriver.solution[i] % 9 + 1
                board.apply(.set(cell: i, digit: d))
                board.applyWrong(cell: i, digit: d, lives: board.lives - 1)
            }
            hints = 2
        }
        self.board = board
        self.date = date
        self.number = number
        startedAt = Int64(Date().timeIntervalSince1970 * 1000) - (midway ? 187_000 : 0)
    }

    func start(game: String, person: String?) async throws -> DailyStart {
        try DailyStart(
            run: "demo", game: "nine-lives", date: date, number: number, level: 1, startedAt: startedAt, now: now,
            puzzle: DailyJSON(NineLivesPuzzle(givens: board.givens)), state: DailyJSON(board.state), seq: seq, hints: hints,
            result: result, closesAt: now + 3_600_000, hintMs: 0)
    }

    func moves(run: String, body: DailyMovesBody, person: String?) async throws -> DailyMovesAnswer {
        if result != nil { return .refused(.over, at: 0, seq: seq) }
        var next = board
        var reveals: [DailyJSON] = []
        var taken = 0
        for (at, raw) in body.moves.enumerated() {
            guard let move = try? raw.decoded(as: NineLivesMove.self), next.apply(move) == nil else {
                return .refused(.illegal, at: at, seq: seq)
            }
            taken += 1
            if case .set(let i, let d) = move, solution[i] != d {
                next.applyWrong(cell: i, digit: d, lives: next.lives - 1)
                var reveal: [String: DailyJSON] = ["k": .string("wrong"), "i": .int(i), "d": .int(d), "lives": .int(next.lives)]
                if next.isOutOfLives {
                    reveal["solution"] = .array(solution.map { .int($0) })
                    next.applySolution(solution)
                }
                reveals.append(.object(reveal))
                if next.isOutOfLives { break }
            }
            // The solving move ends the batch too.
            if next.cells == solution { break }
        }
        board = next
        seq += taken
        if board.isOutOfLives { end(.missed) }
        return answer(reveals)
    }

    func hint(run: String, hints used: Int, person: String?) async throws -> DailyMovesAnswer {
        // A resent hint (the count says it was already given) costs nothing more.
        if used < hints { return answer([]) }
        guard result == nil, board.hintsAvailable, let i = board.cells.indices.first(where: { board.cells[$0] != solution[$0] }) else {
            return .refused(.illegal, at: 0, seq: seq)
        }
        board.applyReveal(cell: i, digit: solution[i])
        hints += 1
        return answer([.object(["i": .int(i), "d": .int(solution[i])])])
    }

    func giveUp(run: String, person: String?) async throws -> DailyMovesAnswer {
        end(.gaveUp)
        return answer([])
    }

    func showOnTV(run: String, on: Bool, person: String?) async throws {}
    func board(date: String?, person: String?) async throws -> DailyBoard { throw NotHere() }
    func stats(person: String?) async throws -> DailyStatsList { throw NotHere() }
    func linkBoard(_ key: ScreenKey, person: String?) async throws { throw NotHere() }
    func unlinkBoard(person: String?) async throws { throw NotHere() }

    private func answer(_ reveals: [DailyJSON]) -> DailyMovesAnswer {
        if result == nil, board.cells == solution { end(.solved) }
        return .accepted(seq: seq, reveals: reveals, progress: board.progress, result: result)
    }

    private func end(_ outcome: DailyOutcome) {
        guard result == nil else { return }
        result = DailyResult(
            game: "nine-lives", date: date, number: number, outcome: outcome, timeMs: Int(now - startedAt), hints: hints,
            progress: outcome == .solved ? 1 : board.progress)
    }
}
#endif
