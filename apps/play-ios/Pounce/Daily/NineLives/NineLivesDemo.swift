#if DEBUG
import PounceKit
import SwiftUI

/// Nine Lives on its own, in a few set states, for screenshots and for trying the game with no
/// server. `-nine-lives-demo start|midway|clash|notquite|solved|watch|dish|dish-almost`. `dish` plays the
/// Dish's own screen (`NineLivesDaily`) over a real `DailyRunSession`, refereed in the app by
/// `NineLivesDemoServer` (`dish-almost`: two cells from done).
struct NineLivesDemoScreen: View {
    enum Preset: String { case start, midway, clash, notquite, solved, watch, dish, dishAlmost = "dish-almost" }

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
            if preset == .dish || preset == .dishAlmost {
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
            if preset == .dish || preset == .dishAlmost {
                let server = NineLivesDemoServer(almost: preset == .dishAlmost)
                guard dish == nil,
                    let session = try? await DailyRunSession.begin(game: "nine-lives", service: server, person: nil),
                    let playable = try? await NineLivesDaily.prepare(session)
                else { return }
                dish = (session, playable)
                return
            }
            guard model == nil, preset != .watch else { return }
            let s = Self.state(preset)
            let m = NineLivesModel(board: NineLivesBoard(puzzle: NineLivesPuzzle(givens: NineLivesLocalDriver.givens), state: s.state), driver: driver)
            for (cell, notes) in s.notes {
                m.tap(cell)
                m.toggleNotes()
                for d in notes { m.press(d) }
                m.toggleNotes()
            }
            if let sel = s.selected { m.tap(sel) }
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
        switch preset {
        case .start, .watch, .dish, .dishAlmost:
            selected = open.first
            if preset == .watch { fallthrough }
        case .midway:
            for i in open.prefix(open.count / 2) { cells[i] = solution[i] }
            hinted = [open[open.count / 2]]
            cells[hinted[0]] = solution[hinted[0]]
            let free = open.suffix(open.count / 2 - 1)
            notes[free.first!] = [2, 5, 8]
            notes[free.dropFirst(3).first!] = [1, 4]
            selected = open[open.count / 3]
        case .clash:
            for i in open.prefix(open.count / 3) { cells[i] = solution[i] }
            let i = open[open.count / 3]
            let row = i / 9
            let given = (0..<9).map { givens[row * 9 + $0] }.first { $0 != 0 }!
            cells[i] = given
            selected = i
        case .notquite:
            for i in open { cells[i] = solution[i] }
            let a = open[open.count - 1]
            cells[a] = solution[a] % 9 + 1
            selected = a
        case .solved:
            for i in open { cells[i] = solution[i] }
        }
        return (NineLivesState(cells: cells, hinted: hinted), notes, selected)
    }
}

/// A stand-in for the server, for the `dish` demo: it referees the sample puzzle with the app's
/// rules and answers hints from the sample's solution, which no real client ever has.
actor NineLivesDemoServer: DailyService {
    struct NotHere: Error {}

    private var board: NineLivesBoard
    private var seq = 0
    private var hints = 0
    private var result: DailyResult?
    private let startedAt: Int64
    private let date: String
    private let number: Int

    private var now: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    /// `almost`: two cells from done. `midway`: half the open cells filled, three minutes in (the
    /// Dish demo's puzzle in play).
    init(almost: Bool = false, midway: Bool = false, date: String = "2027-01-04", number: Int = 1) {
        var board = NineLivesBoard(givens: NineLivesLocalDriver.givens)
        let open = board.givens.indices.filter { board.givens[$0] == 0 }
        // Midway: about half, scattered over the board as a person fills it.
        let filled = almost ? Array(open.dropLast(2)) : midway ? open.enumerated().filter { ($0.offset * 7) % 11 < 6 }.map(\.element) : []
        for i in filled { board.apply(.set(cell: i, digit: NineLivesLocalDriver.solution[i])) }
        self.board = board
        self.date = date
        self.number = number
        startedAt = Int64(Date().timeIntervalSince1970 * 1000) - (midway ? 187_000 : 0)
    }

    func start(game: String, person: String?) async throws -> DailyStart {
        try DailyStart(
            run: "demo", game: "nine-lives", date: date, number: number, level: 1, startedAt: startedAt, now: now,
            puzzle: DailyJSON(NineLivesPuzzle(givens: board.givens)), state: DailyJSON(board.state), seq: seq, hints: hints,
            result: result, closesAt: now + 3_600_000)
    }

    func moves(run: String, body: DailyMovesBody, person: String?) async throws -> DailyMovesAnswer {
        if result != nil { return .refused(.over, at: 0, seq: seq) }
        var next = board
        for (at, raw) in body.moves.enumerated() {
            guard let move = try? raw.decoded(as: NineLivesMove.self), next.apply(move) == nil else {
                return .refused(.illegal, at: at, seq: seq)
            }
        }
        board = next
        seq += body.moves.count
        return answer([])
    }

    func hint(run: String, hints used: Int, person: String?) async throws -> DailyMovesAnswer {
        // A resent hint (the count says it was already given) costs nothing more.
        if used < hints { return answer([]) }
        let solution = NineLivesLocalDriver.solution
        guard result == nil, let i = board.cells.indices.first(where: { board.cells[$0] != solution[$0] }) else {
            return .refused(.over, at: 0, seq: seq)
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
        if result == nil, board.cells == NineLivesLocalDriver.solution { end(.solved) }
        return .accepted(seq: seq, reveals: reveals, progress: board.progress, result: result)
    }

    private func end(_ outcome: DailyOutcome) {
        let time = Int(now - startedAt) + 30_000 * hints
        result = DailyResult(
            game: "nine-lives", date: date, number: number, outcome: outcome, timeMs: time, hints: hints,
            progress: outcome == .solved ? 1 : board.progress)
    }
}
#endif
