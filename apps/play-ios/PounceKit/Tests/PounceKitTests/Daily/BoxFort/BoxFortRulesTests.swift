import Foundation
import Testing
@testable import PounceKit

struct BoxFortRulesTests {
    private func piece(_ picture: String, tint: Int = 1) -> BoxFortPiece {
        var cells: [BoxFortCell] = []
        for (r, line) in picture.split(separator: "/").enumerated() {
            for (c, ch) in line.enumerated() where ch == "#" { cells.append(BoxFortCell(row: r, col: c)) }
        }
        return BoxFortPiece(id: picture, tint: tint, cells: cells)
    }

    private let empty = [Int](repeating: 0, count: 64)

    @Test func scoringMatchesTheServer() {
        #expect((0...4).map(BoxFortRules.lineBonus) == [0, 10, 30, 60, 100])
        #expect((0...3).map(BoxFortRules.comboBonus) == [0, 0, 15, 30])
        #expect(BoxFortRules.fullFort == 200)
    }

    @Test func fitsStaysOnTheRugAndOffBoxes() {
        let sq3 = piece("###/###/###").cells
        #expect(BoxFortRules.fits(empty, sq3, row: 5, col: 5))
        #expect(!BoxFortRules.fits(empty, sq3, row: 6, col: 5))
        #expect(!BoxFortRules.fits(empty, sq3, row: -1, col: 0))
        var rug = empty
        rug[9] = BoxFortRules.clutter
        #expect(!BoxFortRules.fits(rug, sq3, row: 0, col: 0))
    }

    @Test func anyFitsOffTheMainActorAgrees() async {
        let full = [Int](repeating: BoxFortRules.clutter, count: 63) + [0]
        let pieces = [piece("##/##"), piece("#")]
        #expect(BoxFortRules.anyFits(full, pieces))
        #expect(await BoxFortRules.anyFitsOffMain(rug: full, pieces: pieces))
        #expect(!(await BoxFortRules.anyFitsOffMain(rug: full, pieces: [piece("##")])))
    }

    @Test func pieceDecodesCellsAsPairs() throws {
        let json = #"{"id":"nook-a","tint":3,"cells":[[0,0],[0,1],[1,0]]}"#
        let decoded = try JSONDecoder().decode(BoxFortPiece.self, from: Data(json.utf8))
        #expect(decoded.cells == [BoxFortCell(row: 0, col: 0), BoxFortCell(row: 0, col: 1), BoxFortCell(row: 1, col: 0)])
        #expect(decoded.size == BoxFortCell(row: 2, col: 2))
        let again = try JSONDecoder().decode(BoxFortPiece.self, from: JSONEncoder().encode(decoded))
        #expect(again == decoded)
    }

    @Test func aStateRoundTripsAsThePublicState() throws {
        let state = BoxFortRules.start(BoxFortPublicPuzzle(rug: empty, sets: 3, pieces: [piece("#"), piece("#"), piece("#")]))
        let again = try JSONDecoder().decode(BoxFortState.self, from: JSONEncoder().encode(state))
        #expect(again == state)
        #expect(state.over == nil)
        #expect(state.left == [0, 1, 2])
    }
}
