#if DEBUG
import PounceKit
import SwiftUI

/// Nine Lives on its own with the local driver, in a few set states, for screenshots before the
/// Daily Dish host exists. `-nine-lives-demo start|midway|clash|notquite|solved|watch`.
struct NineLivesDemoScreen: View {
    enum Preset: String { case start, midway, clash, notquite, solved, watch }

    let preset: Preset
    @State private var driver = NineLivesLocalDriver()
    @State private var model: NineLivesModel?

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
            if preset == .watch {
                let s = Self.state(.midway)
                NineLivesWatchView(
                    puzzle: NineLivesPuzzle(givens: NineLivesLocalDriver.givens), state: s.state
                )
                .padding(40)
            } else if let model {
                NineLivesPlayView(model: model)
            }
        }
        .task {
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
    static func state(_ preset: Preset) -> (state: NineLivesState, notes: [Int: [Int]], selected: Int?) {
        let givens = NineLivesLocalDriver.givens
        let solution = NineLivesLocalDriver.solution
        let open = givens.indices.filter { givens[$0] == 0 }
        var cells = givens
        var hinted: [Int] = []
        var notes: [Int: [Int]] = [:]
        var selected: Int?
        switch preset {
        case .start, .watch:
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
#endif
