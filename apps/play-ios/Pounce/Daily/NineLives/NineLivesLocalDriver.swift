#if DEBUG
import PounceKit

/// Plays Nine Lives with no server, for the views' first build, their screenshots and the demo. It
/// knows the sample's solution, which no real client ever does: real checks and hints come from
/// the server. It plays the lives rules as the server does (docs/daily-protocol.md, "## Nine
/// Lives"), and the first rules for the old presets.
@MainActor
final class NineLivesLocalDriver: NineLivesDriver {
    /// The server's pinned Monday sample (`apps/play-api/src/daily/nine-lives/samples.ts`).
    nonisolated static let givens = digits("600350270050900130030804906400000003080000020500000009301205080025008040064073002")
    nonisolated static let solution = digits("649351278258967134137824956412589763983716425576432819391245687725698341864173592")

    private(set) var sent: [NineLivesMove] = []
    private var cells: [Int] = givens
    private var lives = NineLivesRules.lifeCount
    private var hintsLeft = NineLivesRules.hintCount

    /// Picks up where a preset's board stands.
    func resume(_ state: NineLivesState) {
        cells = state.cells
        lives = state.lives
        hintsLeft = state.rules == .lives ? state.hintsLeft : .max
    }

    func send(_ move: NineLivesMove, urgent: Bool) {
        sent.append(move)
        switch move {
        case .set(let cell, let digit): cells[cell] = digit
        case .clear(let cell): cells[cell] = 0
        }
    }

    func check(cell: Int, digit: Int) async -> NineLivesCheck {
        sent.append(.set(cell: cell, digit: digit))
        guard lives > 0 else { return .refused }
        if Self.solution[cell] == digit {
            cells[cell] = digit
            return .right
        }
        lives -= 1
        return .wrong(lives: lives, solution: lives == 0 ? Self.solution : nil)
    }

    func hint() async -> (cell: Int, digit: Int)? {
        guard hintsLeft > 0, let cell = cells.indices.first(where: { cells[$0] != Self.solution[$0] }) else { return nil }
        hintsLeft -= 1
        cells[cell] = Self.solution[cell]
        return (cell, Self.solution[cell])
    }

    nonisolated static func digits(_ text: String) -> [Int] { text.map { Int(String($0))! } }
}
#endif
