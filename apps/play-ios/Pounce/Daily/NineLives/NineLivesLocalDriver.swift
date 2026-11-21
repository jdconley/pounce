#if DEBUG
import PounceKit

/// Plays Nine Lives with no server, for the views' first build and their screenshots. It knows the
/// sample's solution, which no real client ever does: real hints come from the server.
@MainActor
final class NineLivesLocalDriver: NineLivesDriver {
    /// The server's pinned Monday sample (`apps/play-api/src/daily/nine-lives/samples.ts`).
    static let givens = digits("600350270050900130030804906400000003080000020500000009301205080025008040064073002")
    static let solution = digits("649351278258967134137824956412589763983716425576432819391245687725698341864173592")

    private(set) var sent: [NineLivesMove] = []
    private var cells: [Int] = givens

    func send(_ move: NineLivesMove) {
        sent.append(move)
        switch move {
        case .set(let cell, let digit): cells[cell] = digit
        case .clear(let cell): cells[cell] = 0
        }
    }

    func hint() async -> (cell: Int, digit: Int)? {
        guard let cell = cells.indices.first(where: { cells[$0] != Self.solution[$0] }) else { return nil }
        cells[cell] = Self.solution[cell]
        return (cell, Self.solution[cell])
    }

    private static func digits(_ text: String) -> [Int] { text.map { Int(String($0))! } }
}
#endif
